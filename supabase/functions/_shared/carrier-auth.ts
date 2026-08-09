/**
 * Provider-neutral, fail-closed shared-secret boundary for webhook-style Edge
 * Functions (SMS/USSD inbound, internal dispatch/cron triggers).
 *
 * This is NOT a carrier (MTN or otherwise) integration. It does not implement
 * any carrier-specific signature scheme, header set, or payload shape. It only
 * guarantees two things:
 *
 *  1. Fail closed: if the expected secret env var is not configured, the
 *     endpoint refuses all traffic (503) instead of silently accepting it.
 *  2. Constant-time comparison of whatever shared secret IS configured, so a
 *     misconfigured-but-present secret can't be brute-forced via timing.
 *
 * When the real MTN webhook specification is available (signing algorithm,
 * header names, replay protection, IP allowlist, etc.), replace or extend the
 * `verifySharedSecret` call sites below with a carrier-specific verifier —
 * this module intentionally stays generic until that spec exists.
 */

function timingSafeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder()
  const aBytes = enc.encode(a)
  const bBytes = enc.encode(b)
  const len = Math.max(aBytes.length, bBytes.length)
  let diff = aBytes.length ^ bBytes.length
  for (let i = 0; i < len; i++) {
    diff |= (aBytes[i] ?? 0) ^ (bBytes[i] ?? 0)
  }
  return diff === 0
}

export type CarrierAuthResult =
  | { ok: true }
  | { ok: false; status: 503; code: "not_configured"; message: string }
  | { ok: false; status: 401; code: "unauthorized"; message: string }

/**
 * Verifies a shared-secret header against an operator-configured env var.
 * Fails closed: an unset env var rejects the request rather than allowing it.
 */
export function verifySharedSecret(
  req: Request,
  envVarName: string,
  headerName: string,
): CarrierAuthResult {
  const expected = Deno.env.get(envVarName)
  if (!expected) {
    return {
      ok: false,
      status: 503,
      code: "not_configured",
      message: `${envVarName} is not configured. This endpoint is disabled until an operator sets it.`,
    }
  }

  const provided = req.headers.get(headerName)
  if (!provided || !timingSafeEqual(provided, expected)) {
    return { ok: false, status: 401, code: "unauthorized", message: "unauthorized" }
  }

  return { ok: true }
}

export function carrierAuthErrorResponse(
  result: Extract<CarrierAuthResult, { ok: false }>,
  corsHeaders: Record<string, string>,
): Response {
  return new Response(JSON.stringify({ error: result.code, message: result.message }), {
    status: result.status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}
