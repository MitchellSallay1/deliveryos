import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { carrierAuthErrorResponse, verifySharedSecret } from "../_shared/carrier-auth.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
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

  const provider = Deno.env.get("EMAIL_PROVIDER") ?? "stub";
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const now = new Date().toISOString();
  const { data: rows, error } = await supabase
    .from("email_outbox")
    .select("id, to_email, subject, body_html, body_text, attempt_count")
    .in("status", ["pending", "failed"])
    .or(`next_attempt_at.is.null,next_attempt_at.lte.${now}`)
    .order("created_at", { ascending: true })
    .limit(25);

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500, headers: cors });
  }

  let sent = 0;
  let failed = 0;

  for (const row of rows ?? []) {
    await supabase
      .from("email_outbox")
      .update({ status: "processing", last_attempt_at: now })
      .eq("id", row.id);

    const attempt = (row.attempt_count ?? 0) + 1;
    try {
      if (provider === "stub") {
        await supabase
          .from("email_outbox")
          .update({
            status: "sent",
            sent_at: now,
            provider: "stub",
            provider_message_id: `stub-email-${row.id}`,
            attempt_count: attempt,
          })
          .eq("id", row.id);
        sent += 1;
        continue;
      }

      if (provider === "http") {
        const endpoint = Deno.env.get("EMAIL_HTTP_ENDPOINT");
        const token = Deno.env.get("EMAIL_HTTP_TOKEN");
        if (!endpoint) throw new Error("EMAIL_HTTP_ENDPOINT not set");

        const res = await fetch(endpoint, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: token ? `Bearer ${token}` : "",
          },
          body: JSON.stringify({
            to: row.to_email,
            subject: row.subject,
            html: row.body_html,
            text: row.body_text,
          }),
        });

        if (!res.ok) throw new Error(`provider HTTP ${res.status}`);
        const payload = await res.json().catch(() => ({}));

        await supabase
          .from("email_outbox")
          .update({
            status: "sent",
            sent_at: now,
            provider: "http",
            provider_message_id: String(payload.id ?? payload.message_id ?? ""),
            attempt_count: attempt,
          })
          .eq("id", row.id);
        sent += 1;
        continue;
      }

      throw new Error(`Unknown EMAIL_PROVIDER: ${provider}`);
    } catch (e) {
      const dead = attempt >= 5;
      await supabase
        .from("email_outbox")
        .update({
          status: dead ? "dead" : "failed",
          attempt_count: attempt,
          last_error: e instanceof Error ? e.message : "send failed",
          next_attempt_at: new Date(Date.now() + attempt * 60_000).toISOString(),
        })
        .eq("id", row.id);
      failed += 1;
    }
  }

  return new Response(JSON.stringify({ provider, sent, failed }), {
    headers: { ...cors, "Content-Type": "application/json" },
  });
});
