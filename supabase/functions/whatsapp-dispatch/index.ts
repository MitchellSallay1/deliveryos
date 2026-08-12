import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { carrierAuthErrorResponse, verifySharedSecret } from "../_shared/carrier-auth.ts";
import { normalizeLiberianPhone } from "../_shared/sms-provider.ts";
import { GupshupProvider, classifyGupshupFailure } from "../_shared/gupshup-provider.ts";

/**
 * Polls whatsapp_outbox and submits pending/failed-retry rows to Gupshup.
 * Same shape as sms-dispatch (internal-only, CRON_SECRET-gated, invoked by
 * jobs-scheduler), deliberately NOT merged into it — different provider,
 * different payload shape (template vs session), different failure
 * classification (Gupshup returns real HTTP status codes to classify by,
 * WinAggregator's response body is undocumented).
 *
 * A message is never marked "sent"/"delivered"/"read" here — only
 * "submitted" (Gupshup accepted the HTTP request). Real delivery state is
 * authoritative only from whatsapp-webhook's message-event handling.
 */

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
};

const BATCH_LIMIT = 25;
const MAX_ATTEMPTS = 5;
const TEMPLATE_NOT_READY_RECHECK_MS = 60 * 60 * 1000; // 1 hour — no point polling every 5 min while waiting on a human to approve a template.

type OutboxRow = {
  id: string;
  recipient_phone: string;
  message_kind: "template" | "session";
  semantic_event_key: string | null;
  template_params: string[];
  body_text: string | null;
  attempt_count: number;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  // Internal-only: invoked by jobs-scheduler, which forwards CRON_SECRET.
  const auth = verifySharedSecret(req, "CRON_SECRET", "x-cron-secret");
  if (!auth.ok) {
    return carrierAuthErrorResponse(auth, cors);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const apiKey = Deno.env.get("GUPSHUP_API_KEY");
  const appName = Deno.env.get("GUPSHUP_APP_NAME");
  const sourceNumber = Deno.env.get("GUPSHUP_SOURCE_NUMBER");

  if (!apiKey || !appName || !sourceNumber) {
    // Fail closed, not silently: the outbox keeps accumulating safely
    // (queue_outbound_whatsapp/dispatch_channel_notification already fall
    // back to SMS for anything not truly WhatsApp-eligible), this endpoint
    // just has nothing it can do until an operator sets the secrets.
    return new Response(
      JSON.stringify({ error: "not_configured", message: "GUPSHUP_API_KEY / GUPSHUP_APP_NAME / GUPSHUP_SOURCE_NUMBER not set" }),
      { status: 503, headers: { ...cors, "Content-Type": "application/json" } },
    );
  }

  const provider = new GupshupProvider({ apiKey, appName, sourceNumber });

  const now = new Date();
  const { data: rows, error } = await supabase
    .from("whatsapp_outbox")
    .select("id, recipient_phone, message_kind, semantic_event_key, template_params, body_text, attempt_count")
    .in("status", ["pending", "failed"])
    .lte("next_attempt_at", now.toISOString())
    .order("created_at", { ascending: true })
    .limit(BATCH_LIMIT);

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  // Claim the batch immediately: push next_attempt_at into the near future
  // for exactly these row ids, BEFORE sending any of them. Without this, an
  // overlapping invocation (e.g. this run took long enough that the next
  // scheduled trigger fired before it finished) would run the identical
  // SELECT above, get the SAME still-"pending" rows, and send each one a
  // second time — a real duplicate WhatsApp message, not just a duplicate
  // DB row. 2 minutes is far more than one row's worst case (a single
  // provider call is capped at an 8s timeout); once a row's status moves
  // out of pending/failed, this claim window becomes irrelevant to it.
  if (rows && rows.length > 0) {
    await supabase
      .from("whatsapp_outbox")
      .update({ next_attempt_at: new Date(Date.now() + 2 * 60_000).toISOString() })
      .in("id", rows.map((r) => r.id));
  }

  let submitted = 0;
  let deferred = 0; // template not yet approved — not a failure, just not ready
  let failed = 0;
  let dead = 0;

  for (const row of (rows ?? []) as OutboxRow[]) {
    const destination = normalizeLiberianPhone(row.recipient_phone);
    if (!destination) {
      await supabase.from("whatsapp_outbox").update({
        status: "dead",
        last_error: "invalid_phone",
        failed_at: new Date().toISOString(),
      }).eq("id", row.id);
      dead += 1;
      continue;
    }

    if (row.message_kind === "template") {
      const { data: template } = await supabase
        .from("whatsapp_template_registry")
        .select("status, gupshup_template_id")
        .eq("semantic_key", row.semantic_event_key)
        .maybeSingle();

      if (!template || template.status !== "approved" || !template.gupshup_template_id) {
        await supabase.from("whatsapp_outbox").update({
          last_error: "template_not_approved",
          next_attempt_at: new Date(Date.now() + TEMPLATE_NOT_READY_RECHECK_MS).toISOString(),
        }).eq("id", row.id);
        deferred += 1;
        continue;
      }

      const result = await provider.sendTemplate({
        destination,
        templateId: template.gupshup_template_id,
        params: (row.template_params ?? []).map((p) => String(p)),
      });
      await applyResult(supabase, row, result);
    } else {
      if (!row.body_text) {
        await supabase.from("whatsapp_outbox").update({
          status: "dead",
          last_error: "empty_session_body",
          failed_at: new Date().toISOString(),
        }).eq("id", row.id);
        dead += 1;
        continue;
      }
      const result = await provider.sendText({ destination, text: row.body_text });
      await applyResult(supabase, row, result);
    }
  }

  async function applyResult(
    sb: ReturnType<typeof createClient>,
    row: OutboxRow,
    result: Awaited<ReturnType<GupshupProvider["sendText"]>>,
  ) {
    const attempt = row.attempt_count + 1;
    if (result.ok) {
      await sb.from("whatsapp_outbox").update({
        status: "submitted",
        submitted_at: new Date().toISOString(),
        provider_message_id: result.providerMessageId,
        attempt_count: attempt,
        last_error: null,
      }).eq("id", row.id);
      submitted += 1;
      return;
    }

    const failureClass = classifyGupshupFailure(result);
    if (failureClass === "permanent") {
      await sb.from("whatsapp_outbox").update({
        status: "dead",
        attempt_count: attempt,
        last_error: result.error,
        failed_at: new Date().toISOString(),
      }).eq("id", row.id);
      dead += 1;
      return;
    }

    const backoffMs = failureClass === "rate_limited" ? 5 * 60_000 : attempt * 60_000;
    const isDead = attempt >= MAX_ATTEMPTS;
    await sb.from("whatsapp_outbox").update({
      status: isDead ? "dead" : "failed",
      attempt_count: attempt,
      last_error: result.error,
      next_attempt_at: new Date(Date.now() + backoffMs).toISOString(),
      failed_at: isDead ? new Date().toISOString() : null,
    }).eq("id", row.id);
    if (isDead) dead += 1; else failed += 1;
  }

  return new Response(
    JSON.stringify({ processed: (rows ?? []).length, submitted, deferred, failed, dead }),
    { headers: { ...cors, "Content-Type": "application/json" } },
  );
});
