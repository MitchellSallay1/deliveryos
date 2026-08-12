import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { carrierAuthErrorResponse, verifySharedSecretQueryParam } from "../_shared/carrier-auth.ts";
import { parseGupshupWebhookEvent } from "../_shared/gupshup-webhook.ts";

/**
 * Gupshup WhatsApp webhook — server-to-server, no user JWT (deploy with
 * --no-verify-jwt, same reasoning as auth-sms-hook and sms-inbound: the
 * caller is Gupshup's servers, not a signed-in DeliveryOS user).
 *
 * SECURITY MODEL (see docs/WHATSAPP.md for the full residual-risk writeup):
 * Gupshup's documented webhook setup (docs.gupshup.io/docs/set-webhookcallback-url)
 * is "paste a callback URL" with no custom header, shared secret, or
 * signature option exposed to app customers — confirmed by direct research
 * against their current docs, not assumed. Unlike auth-sms-hook (which gets
 * a real Standard Webhooks HMAC signature from Supabase), there is nothing
 * to verify a signature AGAINST here. This endpoint is instead protected by:
 *   1. A shared secret embedded in the callback URL itself (?token=...,
 *      GUPSHUP_WEBHOOK_SECRET) — the only place a secret CAN travel given
 *      Gupshup's config UI. Fails closed (503) if unconfigured.
 *   2. Payload app-name cross-check against GUPSHUP_APP_NAME when present.
 *   3. Idempotency: inbound messages dedup on provider_message_id (unique
 *      index), status events apply forward-only (see
 *      apply_whatsapp_status_event) — a replayed or duplicated call cannot
 *      duplicate a user-visible action or corrupt delivery-receipt state.
 *   4. The router only ever calls public, already-security-scoped RPCs
 *      (get_public_delivery_tracking, get_public_commerce_order_status) —
 *      it cannot mutate arbitrary Commerce/delivery records.
 * Residual risk: anyone who obtains the token URL can POST fabricated
 * inbound messages or status events. This is the same class of exposure
 * sms-inbound already accepts for its shared-secret header — treated as
 * acceptable here for the same reason (low blast radius: inbound messages
 * only trigger safe, idempotent, publicly-scoped lookups; status events
 * only move a message forward through its own lifecycle). Rotate
 * GUPSHUP_WEBHOOK_SECRET if leaked, same as any other shared secret.
 *
 * Persist-first: the DB write happens before any response is returned;
 * router processing for inbound messages runs via EdgeRuntime.waitUntil
 * AFTER the 200 is already sent, so Gupshup never waits on it (guards
 * against a slow router turning into a Gupshup-side timeout/retry storm).
 */

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type",
};

function jsonResponse(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "method_not_allowed" });
  }

  const auth = verifySharedSecretQueryParam(req, "GUPSHUP_WEBHOOK_SECRET", "token");
  if (!auth.ok) {
    return carrierAuthErrorResponse(auth, cors);
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return jsonResponse(400, { error: "invalid_json" });
  }

  const event = parseGupshupWebhookEvent(body);

  const expectedApp = Deno.env.get("GUPSHUP_APP_NAME");
  if (event.kind !== "unknown" && expectedApp && event.appName && event.appName !== expectedApp) {
    // Never log the payload itself — only that a mismatch occurred.
    console.error("whatsapp-webhook: app name mismatch, rejecting");
    return jsonResponse(401, { error: "app_mismatch" });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  if (event.kind === "unknown") {
    // Includes Gupshup's user-event (opted-in/opted-out) notifications and
    // any future event type — safely ignorable in Phase A (opt-in/out is
    // tracked from inbound STOP/START instead). Ack quickly either way.
    console.log("whatsapp-webhook: ignored event type", event.rawType ?? "unknown");
    return jsonResponse(200, { ok: true });
  }

  if (event.kind === "message-event") {
    const { error } = await supabase.rpc("apply_whatsapp_status_event", {
      p_provider_message_id: event.providerMessageId,
      p_status: event.status,
      p_error_reason: event.errorReason,
    });
    if (error) {
      // Non-2xx so Gupshup's own retry policy has a chance to redeliver a
      // genuinely transient DB failure — this function never fabricates
      // "processed" for a write that didn't happen.
      console.error("whatsapp-webhook: status update failed", error.message);
      return jsonResponse(500, { error: "status_update_failed" });
    }
    return jsonResponse(200, { ok: true });
  }

  // event.kind === "message" — persist first, ack, THEN route.
  const { data: recorded, error: recordError } = await supabase
    .rpc("record_whatsapp_inbound_message", {
      p_provider_message_id: event.providerMessageId,
      p_app_name: event.appName,
      p_sender_phone: event.senderPhone,
      p_message_type: event.messageType,
      p_message_text: event.text,
      p_media_reference: event.mediaReference,
    })
    .single();

  if (recordError || !recorded) {
    console.error("whatsapp-webhook: failed to persist inbound message", recordError?.message);
    return jsonResponse(500, { error: "persist_failed" });
  }

  const { id: inboundId, is_new: isNew } = recorded as { id: string; is_new: boolean };

  if (!isNew) {
    // Replay of an already-seen message — already processed once, ack and stop.
    return jsonResponse(200, { ok: true, duplicate: true });
  }

  const routeAndReply = async () => {
    try {
      const { data: routed, error: routeError } = await supabase
        .rpc("whatsapp_router_handle", { p_phone: event.senderPhone, p_text: event.text ?? "" })
        .single();

      if (routeError || !routed) {
        await supabase.rpc("mark_whatsapp_inbound_processed", {
          p_id: inboundId,
          p_status: "error",
          p_error: routeError?.message ?? "router returned no result",
          p_reply_sent: false,
        });
        return;
      }

      const replyMessage = (routed as { reply_message?: string }).reply_message;
      let replySent = false;
      if (replyMessage) {
        const { data: queued } = await supabase.rpc("queue_outbound_whatsapp_session_reply", {
          p_company_id: null,
          p_phone: event.senderPhone,
          p_body_text: replyMessage,
          p_idempotency_key: `router_reply:${event.providerMessageId}`,
        });
        replySent = Boolean(queued);
      }

      await supabase.rpc("mark_whatsapp_inbound_processed", {
        p_id: inboundId,
        p_status: "processed",
        p_error: null,
        p_reply_sent: replySent,
      });
    } catch (e) {
      console.error("whatsapp-webhook: router processing failed", e instanceof Error ? e.message : "unknown");
      await supabase.rpc("mark_whatsapp_inbound_processed", {
        p_id: inboundId,
        p_status: "error",
        p_error: e instanceof Error ? e.message : "unknown",
        p_reply_sent: false,
      });
    }
  };

  // deno-lint-ignore no-explicit-any
  const runtime = (globalThis as any).EdgeRuntime;
  if (runtime?.waitUntil) {
    runtime.waitUntil(routeAndReply());
  } else {
    // Local/dev fallback where EdgeRuntime isn't available — process inline
    // rather than silently dropping the message.
    await routeAndReply();
  }

  return jsonResponse(200, { ok: true });
});
