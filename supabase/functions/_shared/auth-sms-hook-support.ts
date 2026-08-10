/**
 * Pure helpers for the Supabase Auth "Send SMS Hook" Edge Function
 * (`auth-sms-hook`). Kept separate from the Deno entrypoint and from the
 * Standard Webhooks signature verification (which requires a Deno-only
 * `https://esm.sh/...` URL import) so this logic is testable under
 * Node/vitest.
 *
 * Contract note: Supabase's Send SMS Hook does NOT use the `{{ .Code }}`
 * Go-template syntax — that syntax belongs to the legacy Dashboard-configured
 * SMS *template* system (native Twilio/MessageBird/Vonage provider). With a
 * custom Send SMS Hook, Supabase instead calls this function with the real,
 * already-generated OTP value in the `sms.otp` field of the verified
 * payload, and the hook is fully responsible for composing the message
 * text — there is no template token to invent or substitute into.
 */

export type SmsSendOutcome =
  | { ok: true }
  | { ok: false; reason: string }

export type HookHttpResponse = {
  status: number
  body: Record<string, unknown>
}

/** Composes the auth OTP SMS body. Never logs or embeds anything beyond the OTP digits and fixed copy. */
export function buildAuthOtpMessage(otp: string): string {
  return `Your DeliveryOS verification code is ${otp}. It expires soon. Do not share this code.`
}

/**
 * Maps a provider send outcome to the Send SMS Hook's HTTP response
 * contract: empty JSON body + 200 on success ("No outputs are required. An
 * empty response with a status code of 200 is taken as a successful
 * response."), any non-200 status with a JSON body on failure. The failure
 * body is always a short, generic, pre-defined reason string — never the
 * raw provider response, never the OTP, never the original hook payload.
 */
export function buildHookHttpResponse(outcome: SmsSendOutcome): HookHttpResponse {
  if (outcome.ok) {
    return { status: 200, body: {} }
  }
  return { status: 500, body: { error: outcome.reason } }
}

export function buildHookRejectedResponse(reason: 'not_configured' | 'invalid_signature' | 'invalid_payload'): HookHttpResponse {
  const status = reason === 'not_configured' ? 503 : 401
  return { status, body: { error: reason } }
}
