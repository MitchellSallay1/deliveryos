/**
 * Provider-neutral outbound SMS transport.
 *
 * Liberia currently has ONE configured outbound SMS route (WinAggregator),
 * manually verified to deliver to both MTN Liberia and Orange Liberia
 * numbers. It is a general Liberia SMS gateway, not an MTN-specific
 * transport — do not name or treat it as MTN-only. If a future provider
 * documents genuinely separate MTN/Orange endpoints, add a second
 * SmsProvider implementation and route by network prefix; don't assume
 * that split exists today.
 *
 * This module is intentionally plain, dependency-free TypeScript (no
 * `Deno.*` calls) so it can be unit-tested under Node/vitest as well as
 * run under the Deno Edge Function runtime. Callers (Edge Function
 * entrypoints) are responsible for reading env vars and constructing the
 * provider.
 *
 * Confirmed production behavior: no API key or authentication header is
 * required by the current WinAggregator integration — none is sent, and
 * none should be added speculatively. If the provider ever documents an
 * auth requirement, add it explicitly then.
 *
 * The response body shape is undocumented — success/failure is determined
 * solely by HTTP status ("treat successful HTTP response as provider
 * acceptance"), and the raw response text is surfaced for diagnostics
 * rather than parsed into invented fields.
 */

export type SmsSendParams = {
  /** Any input phone format; normalized internally before sending. */
  phone: string
  message: string
}

export type SmsSendResult =
  | { ok: true; httpStatus: number; providerResponseRaw: string }
  | { ok: false; httpStatus: number | null; error: string; providerResponseRaw?: string }

export interface SmsProvider {
  send(params: SmsSendParams): Promise<SmsSendResult>
}

/**
 * Normalizes a Liberian MSISDN to bare-digit `231XXXXXXXXX` (no `+`), the
 * format the WinAggregator payload's `destination` field expects. Mirrors
 * the digit-handling rules of the Postgres `normalize_phone_lr` function
 * (9-digit local, 10-digit local with leading 0, already-231-prefixed),
 * minus the `+` that function adds.
 */
export function normalizeLiberianPhone(raw: string): string {
  const digits = (raw ?? '').replace(/\D/g, '')
  if (!digits) return ''

  if (digits.length === 9) {
    return `231${digits}`
  }
  if (digits.length === 10 && digits.startsWith('0')) {
    return `231${digits.slice(1)}`
  }
  if (digits.length >= 11 && digits.startsWith('231')) {
    return digits
  }
  return digits
}

const RAW_RESPONSE_LOG_LIMIT = 500

async function readRawResponse(res: Response): Promise<string> {
  try {
    const text = await res.text()
    return text.length > RAW_RESPONSE_LOG_LIMIT ? `${text.slice(0, RAW_RESPONSE_LOG_LIMIT)}…` : text
  } catch {
    return ''
  }
}

export type WinAggregatorConfig = {
  endpoint: string
  /** Registered sender ID / short name shown to recipients. Must be "DelivOS" per confirmed provider registration. */
  senderId: string
  /**
   * Abort the request if the provider hasn't responded within this many ms.
   * Defaults to 4000 — comfortably under the 5-second budget Supabase gives
   * an Auth Hook to finish, and still reasonable for the operational
   * (sms_outbox) send path, which previously had no timeout at all.
   */
  timeoutMs?: number
}

const DEFAULT_TIMEOUT_MS = 4000

/** WinAggregator SMS transport — current Liberia outbound SMS provider (covers MTN Liberia and Orange Liberia). */
export class WinAggregatorSmsProvider implements SmsProvider {
  constructor(private readonly config: WinAggregatorConfig) {}

  async send({ phone, message }: SmsSendParams): Promise<SmsSendResult> {
    const destination = normalizeLiberianPhone(phone)
    if (!destination) {
      return { ok: false, httpStatus: null, error: 'invalid_phone' }
    }

    const timeoutMs = this.config.timeoutMs ?? DEFAULT_TIMEOUT_MS
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), timeoutMs)

    let res: Response
    try {
      res = await fetch(this.config.endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          sender_id: this.config.senderId,
          destination,
          message,
        }),
        signal: controller.signal,
      })
    } catch (e) {
      if (e instanceof Error && e.name === 'AbortError') {
        return { ok: false, httpStatus: null, error: 'timeout' }
      }
      return { ok: false, httpStatus: null, error: e instanceof Error ? e.message : 'network_error' }
    } finally {
      clearTimeout(timer)
    }

    const raw = await readRawResponse(res)

    if (!res.ok) {
      return { ok: false, httpStatus: res.status, error: `provider HTTP ${res.status}`, providerResponseRaw: raw }
    }

    return { ok: true, httpStatus: res.status, providerResponseRaw: raw }
  }
}
