/**
 * Supabase Auth "Send SMS Hook" — delivers Supabase-generated phone OTPs
 * (login + registration) through WinAggregator, replacing the built-in
 * SMS provider integration Supabase Auth would otherwise use.
 *
 * Supabase remains the sole authentication authority: it generates the
 * OTP, tracks its expiry, verifies it (`supabase.auth.verifyOtp`), issues
 * sessions, and enforces its own rate limits. This function's ONLY job is
 * to deliver the SMS — it never stores, re-derives, or verifies an OTP
 * itself, and it is entirely separate from the operational `sms_outbox` /
 * `sms-dispatch` pipeline used for delivery/rider notifications.
 *
 * Deployed with `--no-verify-jwt`: Supabase Auth calls this function
 * server-side, before any user session/JWT exists, so the Supabase
 * gateway's normal JWT check cannot apply here (confirmed via Supabase's
 * own Auth Hooks docs and community guidance — this mirrors the existing
 * `sms-inbound --no-verify-jwt` deployment already used in this repo for
 * the analogous "external caller, no user JWT" case). Authenticity is
 * instead guaranteed entirely by the Standard Webhooks signature below —
 * this function fails closed if that cannot be verified.
 *
 * Payload/response contract (confirmed from supabase.com/docs/guides/auth/
 * auth-hooks/send-sms-hook and supabase.com/docs/guides/auth/auth-hooks,
 * not guessed):
 *   Request body: { user: { phone: string, ... }, sms: { otp: string } }
 *   Security headers: webhook-id, webhook-timestamp, webhook-signature
 *     (Standard Webhooks spec — https://www.standardwebhooks.com)
 *   Hook secret format: "v1,whsec_<base64>" — the "v1,whsec_" prefix is
 *     stripped before handing the raw base64 secret to the Webhook verifier.
 *   Success response: HTTP 200 with an empty JSON body.
 *   Failure response: any non-200 status; body format is not mandated by
 *     Supabase, so a short generic `{ error: "<reason>" }` is used.
 *   Hooks are expected to complete within 5 seconds.
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";
import { normalizeLiberianPhone, WinAggregatorSmsProvider } from "../_shared/sms-provider.ts";
import { buildAuthOtpMessage, buildHookHttpResponse, buildHookRejectedResponse } from "../_shared/auth-sms-hook-support.ts";

const DEFAULT_WINAGGREGATOR_ENDPOINT = "https://winaggregator-mtn.com/request/sms-service/1";
const DEFAULT_WINAGGREGATOR_SENDER_ID = "DelivOS";

function jsonResponse(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "method_not_allowed" });
  }

  // Fail closed: an unconfigured hook secret disables this endpoint rather
  // than accepting unsigned/unverifiable requests.
  const rawSecret = Deno.env.get("SEND_SMS_HOOK_SECRET");
  if (!rawSecret) {
    const { status, body } = buildHookRejectedResponse("not_configured");
    return jsonResponse(status, body);
  }
  const secret = rawSecret.replace("v1,whsec_", "");

  const payload = await req.text();
  const headers = Object.fromEntries(req.headers);

  let user: { phone?: string } | undefined;
  let sms: { otp?: string } | undefined;
  try {
    const wh = new Webhook(secret);
    const verified = wh.verify(payload, headers) as { user?: { phone?: string }; sms?: { otp?: string } };
    user = verified.user;
    sms = verified.sms;
  } catch {
    // Never log the payload or headers here — an invalid signature is the
    // expected shape of a spoofed/replayed request, not a diagnostic event
    // worth the risk of logging unverified attacker-controlled content.
    const { status, body } = buildHookRejectedResponse("invalid_signature");
    return jsonResponse(status, body);
  }

  const phone = user?.phone;
  const otp = sms?.otp;
  if (!phone || !otp) {
    const { status, body } = buildHookRejectedResponse("invalid_payload");
    return jsonResponse(status, body);
  }

  const provider = new WinAggregatorSmsProvider({
    endpoint: Deno.env.get("WINAGGREGATOR_SMS_ENDPOINT") ?? DEFAULT_WINAGGREGATOR_ENDPOINT,
    senderId: Deno.env.get("WINAGGREGATOR_SENDER_ID") ?? DEFAULT_WINAGGREGATOR_SENDER_ID,
  });

  const result = await provider.send({
    phone: normalizeLiberianPhone(phone),
    message: buildAuthOtpMessage(otp),
  });

  if (!result.ok) {
    // Sanitized: HTTP status only, never the raw provider response body
    // (which could — even if unlikely — echo back request content) and
    // never the OTP or phone number.
    console.error("auth-sms-hook: provider send failed", { httpStatus: result.httpStatus, error: result.error });
    const { status, body } = buildHookHttpResponse({ ok: false, reason: "sms_send_failed" });
    return jsonResponse(status, body);
  }

  const { status, body } = buildHookHttpResponse({ ok: true });
  return jsonResponse(status, body);
});
