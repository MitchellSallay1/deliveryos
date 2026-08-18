/**
 * WinAggregator MTN MoMo collection transport + response normalization.
 *
 * PRODUCTION FINANCIAL CODE — see docs/MTN_MOMO_PAYMENTS.md for the full
 * design rationale. This file intentionally does two structurally separate
 * things, kept in one file because they're small and always used together,
 * but never merged into one function:
 *
 *  1. WinAggregatorMtnProvider.collect() — thin HTTP transport. Returns a
 *     RAW result (http status + parsed-or-unparseable body + network
 *     outcome). It NEVER decides success/failure/pending itself.
 *  2. normalizeMtnCollectionResult() — the ONLY place that turns a raw
 *     result into a payment_attempt_state. This is the safety-critical
 *     part: every branch is deliberately conservative (see comments below),
 *     because the cost of wrongly returning 'successful' (ships goods for
 *     an unpaid order) or wrongly returning 'failed' (an operator or the
 *     customer assumes it's safe to charge again) is asymmetric with the
 *     cost of returning 'unknown' (nothing further happens automatically;
 *     a human reconciles it later — see record_payment_attempt_result and
 *     admin_reconcile_payment_attempt in the Phase E2 migration).
 *
 * DOCUMENTED PROVIDER CONTRACT (from the phase brief — NOT independently
 * verified against a live sandbox, since no real credentials exist yet):
 *   POST https://winaggregator-mtn.com/mtn/api/v1/collection
 *   Request: { secret_string, company_name, amount, currency, externalID, msisdn }
 *   Success body may include: reference_id, transaction_status, gross_amount,
 *     provider_fee_deducted, net_merchant_credited, response.financialTransactionId,
 *     response.status
 *   HTTP 202 = pending (provider explicitly documents this)
 *   Provider polls MTN for up to ~60s before responding.
 *
 * UNVERIFIED, EXPLICITLY FLAGGED ASSUMPTIONS (see docs/MTN_MOMO_PAYMENTS.md
 * "Known provider-contract uncertainty" — these need confirming against a
 * real sandbox response before this goes live, and are exactly why the
 * normalizer below defaults to 'unknown' whenever a signal doesn't clearly
 * match):
 *   - The exact string vocabulary for transaction_status / response.status
 *     (e.g. is a successful collection "SUCCESSFUL", "SUCCESS", "COMPLETED"?)
 *     is not documented. This module only trusts an explicit, small allow-
 *     list of tokens (see SUCCESS_TOKENS/FAILURE_TOKENS) and treats
 *     anything else as unrecognized -> unknown, never guessed at.
 *   - Whether gross_amount/provider_fee_deducted/net_merchant_credited are
 *     decimal major-currency-unit strings/numbers (e.g. "1000.00") or
 *     already integer minor units (cents) is not documented. This module
 *     assumes decimal major units (the common convention for this class of
 *     API) and converts to integer cents via string-safe parsing, never
 *     naive floating-point multiplication — see parseDecimalToCents.
 *   - Whether externalID is a true idempotency key, whether a transaction
 *     can be looked up by externalID, and whether a 202/timeout can safely
 *     be retried are all EXPLICITLY UNCONFIRMED — this module never
 *     resubmits a collection for an existing externalID under any
 *     circumstance; see the Phase E2 migration's payment_attempts state
 *     machine, which enforces this at the call-site level, not here.
 */

export type MsisdnValidation =
  | { ok: true; normalized: string }
  | { ok: false; error: string }

/**
 * Normalizes and validates a Liberian MSISDN for the provider's `msisdn`
 * field. Reuses the SAME digit-handling rules as normalizeLiberianPhone
 * (_shared/sms-provider.ts) — this is deliberately NOT a second, divergent
 * Liberia phone formatter, just a thin wrapper that also validates shape
 * (a malformed number must never silently become a different, valid-
 * looking number for a different customer).
 *
 * Carrier-specific (MTN-only, as opposed to Orange) prefix validation is
 * NOT implemented here: the phase brief references "supported Liberian MTN
 * prefixes" but does not enumerate the actual prefix digits, and inventing
 * them would be a fabricated business fact, not a technical judgment call.
 * See docs/MTN_MOMO_PAYMENTS.md "Known provider-contract uncertainty."
 */
export function validateMtnMsisdn(raw: string): MsisdnValidation {
  const digits = (raw ?? '').replace(/\D/g, '')
  if (!digits) {
    return { ok: false, error: 'empty_msisdn' }
  }

  let normalized: string
  if (digits.length === 9) {
    normalized = `231${digits}`
  } else if (digits.length === 10 && digits.startsWith('0')) {
    normalized = `231${digits.slice(1)}`
  } else if (digits.length >= 11 && digits.startsWith('231')) {
    normalized = digits
  } else {
    return { ok: false, error: 'invalid_msisdn_format' }
  }

  // A normalized Liberian MSISDN is always 231 + 9 digits = 12 digits.
  if (normalized.length !== 12) {
    return { ok: false, error: 'invalid_msisdn_length' }
  }

  return { ok: true, normalized }
}

/** Displays only the last 4 digits — for logs/UI, never the full number. */
export function maskMsisdn(msisdn: string): string {
  if (!msisdn || msisdn.length < 4) return '***'
  return `***${msisdn.slice(-4)}`
}

/**
 * Parses a provider-reported money value into integer cents WITHOUT naive
 * floating-point multiplication. Given a string like "1000.00" or "1000",
 * splits on the decimal point and reconstructs from digits directly. Given
 * a JSON number, falls back to Math.round(value * 100) — still reasonable
 * for values in normal payment ranges, but strings are preferred whenever
 * the provider gives one, precisely to avoid float-drift on the
 * authoritative figures this system reconciles against.
 */
export function parseDecimalToCents(value: unknown): number | null {
  if (value === null || value === undefined) return null

  if (typeof value === 'string') {
    const trimmed = value.trim()
    if (!/^-?\d+(\.\d+)?$/.test(trimmed)) return null
    const negative = trimmed.startsWith('-')
    const unsigned = negative ? trimmed.slice(1) : trimmed
    const [whole, frac = ''] = unsigned.split('.')
    const fracPadded = (frac + '00').slice(0, 2)
    const cents = Number(whole) * 100 + Number(fracPadded)
    if (!Number.isFinite(cents)) return null
    return negative ? -cents : cents
  }

  if (typeof value === 'number' && Number.isFinite(value)) {
    return Math.round(value * 100)
  }

  return null
}

export type MtnCollectionRequest = {
  amountCents: number
  currency: 'LRD' | 'USD'
  externalId: string
  /** Already-normalized (validateMtnMsisdn) — this module does not re-validate. */
  msisdn: string
}

interface RawCollectionBody {
  reference_id?: unknown
  transaction_status?: unknown
  gross_amount?: unknown
  provider_fee_deducted?: unknown
  net_merchant_credited?: unknown
  response?: { financialTransactionId?: unknown; status?: unknown }
  [key: string]: unknown
}

export type MtnRawResult =
  | { kind: 'response'; httpStatus: number; parsed: RawCollectionBody | null; rawText: string }
  | { kind: 'network_error'; error: string }
  | { kind: 'timeout' }

export type MtnCollectionConfig = {
  baseUrl?: string
  secretString: string
  companyName: string
  /** Bounded per section 9 — see docs/MTN_MOMO_PAYMENTS.md "Timeout strategy." */
  timeoutMs?: number
}

const DEFAULT_BASE_URL = 'https://winaggregator-mtn.com/mtn/api/v1'
// Provider documents polling MTN for "approximately 60 seconds" — 75s gives
// real margin without approaching Supabase's 150s request-idle-timeout,
// and this call only ever runs from a background task (EdgeRuntime.
// waitUntil), never while a browser holds the connection open — see
// docs/MTN_MOMO_PAYMENTS.md "Timeout strategy."
const DEFAULT_TIMEOUT_MS = 75_000
const RAW_TEXT_LOG_LIMIT = 1000

export class WinAggregatorMtnProvider {
  constructor(private readonly config: MtnCollectionConfig) {}

  async collect(req: MtnCollectionRequest): Promise<MtnRawResult> {
    const url = `${(this.config.baseUrl ?? DEFAULT_BASE_URL).replace(/\/$/, '')}/collection`
    const timeoutMs = this.config.timeoutMs ?? DEFAULT_TIMEOUT_MS
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), timeoutMs)

    let res: Response
    try {
      res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          secret_string: this.config.secretString,
          company_name: this.config.companyName,
          amount: (req.amountCents / 100).toFixed(2),
          currency: req.currency,
          externalID: req.externalId,
          msisdn: req.msisdn,
        }),
        signal: controller.signal,
      })
    } catch (e) {
      if (e instanceof Error && e.name === 'AbortError') {
        return { kind: 'timeout' }
      }
      return { kind: 'network_error', error: e instanceof Error ? e.message : 'unknown_network_error' }
    } finally {
      clearTimeout(timer)
    }

    const rawText = await res.text().catch(() => '')
    const truncated = rawText.length > RAW_TEXT_LOG_LIMIT ? `${rawText.slice(0, RAW_TEXT_LOG_LIMIT)}…` : rawText

    let parsed: RawCollectionBody | null = null
    try {
      parsed = rawText ? (JSON.parse(rawText) as RawCollectionBody) : null
    } catch {
      parsed = null
    }

    return { kind: 'response', httpStatus: res.status, parsed, rawText: truncated }
  }
}

export type NormalizedPaymentState = 'pending' | 'successful' | 'failed' | 'unknown'

export type NormalizedCollectionResult = {
  state: NormalizedPaymentState
  rawStatus: string | null
  httpStatus: number | null
  providerReferenceId: string | null
  financialTransactionId: string | null
  providerGrossCents: number | null
  providerFeeCents: number | null
  providerNetCents: number | null
  failureCategory: string | null
  errorMessage: string | null
}

// Deliberately small, explicit allow-lists — see file header. Anything not
// in these lists is unrecognized, never guessed at.
const SUCCESS_TOKENS = new Set(['successful', 'success', 'completed', 'confirmed'])
const FAILURE_TOKENS = new Set(['failed', 'failure', 'declined', 'rejected', 'cancelled', 'canceled'])

function asLowerString(v: unknown): string | null {
  return typeof v === 'string' && v.length > 0 ? v.toLowerCase() : null
}

function classifyToken(v: unknown): 'success' | 'failure' | 'other' | null {
  const s = asLowerString(v)
  if (s === null) return null
  if (SUCCESS_TOKENS.has(s)) return 'success'
  if (FAILURE_TOKENS.has(s)) return 'failure'
  return 'other'
}

function str(v: unknown): string | null {
  return typeof v === 'string' && v.length > 0 ? v : null
}

export function normalizeMtnCollectionResult(raw: MtnRawResult): NormalizedCollectionResult {
  const empty: Omit<NormalizedCollectionResult, 'state' | 'httpStatus' | 'failureCategory' | 'errorMessage'> = {
    rawStatus: null,
    providerReferenceId: null,
    financialTransactionId: null,
    providerGrossCents: null,
    providerFeeCents: null,
    providerNetCents: null,
  }

  if (raw.kind === 'timeout') {
    // Section 2/9/10: a timeout NEVER implies failure — the request may
    // have reached the provider and even reached MTN before our own
    // deadline expired.
    return { ...empty, state: 'unknown', httpStatus: null, failureCategory: 'timeout', errorMessage: 'Request timed out waiting for the provider.' }
  }

  if (raw.kind === 'network_error') {
    return { ...empty, state: 'unknown', httpStatus: null, failureCategory: 'network_error', errorMessage: raw.error }
  }

  // raw.kind === 'response'
  const { httpStatus, parsed } = raw

  if (httpStatus === 202) {
    // Documented explicitly by the provider as "still pending" — trusted
    // regardless of body content.
    return {
      ...empty,
      state: 'pending',
      httpStatus,
      rawStatus: parsed ? (asLowerString(parsed.transaction_status) ?? asLowerString(parsed.response?.status)) : null,
      providerReferenceId: parsed ? str(parsed.reference_id) : null,
      failureCategory: null,
      errorMessage: null,
    }
  }

  if (parsed === null) {
    // Malformed/non-JSON body on ANY status — cannot trust any field, so
    // nothing extracted is used even if httpStatus alone looks clean.
    return { ...empty, state: 'unknown', httpStatus, failureCategory: 'malformed_response', errorMessage: 'Provider response body was not valid JSON.' }
  }

  const txStatus = classifyToken(parsed.transaction_status)
  const respStatus = classifyToken(parsed.response?.status)
  const grossCents = parseDecimalToCents(parsed.gross_amount)
  const feeCents = parseDecimalToCents(parsed.provider_fee_deducted)
  const netCents = parseDecimalToCents(parsed.net_merchant_credited)
  const referenceId = str(parsed.reference_id)
  const financialTransactionId = str(parsed.response?.financialTransactionId)
  const rawStatusForStorage = asLowerString(parsed.transaction_status) ?? asLowerString(parsed.response?.status)

  const fields = {
    ...empty,
    httpStatus,
    rawStatus: rawStatusForStorage,
    providerReferenceId: referenceId,
    financialTransactionId,
    providerGrossCents: grossCents,
    providerFeeCents: feeCents,
    providerNetCents: netCents,
  }

  if (httpStatus >= 500) {
    // Never assume a server error means the collection didn't reach MTN.
    return { ...fields, state: 'unknown', failureCategory: 'provider_server_error', errorMessage: `Provider returned HTTP ${httpStatus}.` }
  }

  if (httpStatus >= 400) {
    // A clean, parseable 4xx with SOME identifiable status/message is
    // treated as the provider definitively rejecting the request BEFORE
    // any MTN charge could occur (validation/auth failure) — 'failed', not
    // 'unknown'. If neither status field is present at all, there's
    // nothing concrete confirming a clean rejection, so stay conservative.
    if (txStatus !== null || respStatus !== null || referenceId !== null) {
      return { ...fields, state: 'failed', failureCategory: 'request_rejected', errorMessage: `Provider rejected the request (HTTP ${httpStatus}).` }
    }
    return { ...fields, state: 'unknown', failureCategory: 'malformed_rejection', errorMessage: `Provider returned HTTP ${httpStatus} with no identifiable status.` }
  }

  // httpStatus is 2xx (200/201/etc, 202 already handled above).
  if (txStatus === 'success' && respStatus !== 'failure') {
    return { ...fields, state: 'successful', failureCategory: null, errorMessage: null }
  }
  if (respStatus === 'success' && txStatus !== 'failure') {
    return { ...fields, state: 'successful', failureCategory: null, errorMessage: null }
  }
  if (txStatus === 'failure' || respStatus === 'failure') {
    // Neither field claimed success while at least one explicitly claims
    // failure — including the case where txStatus and respStatus disagree
    // in the OTHER direction (one success, one failure): that contradiction
    // is not something this function decides in favor of success. Only
    // exact success-on-both-or-success-with-no-contradicting-failure above
    // reaches 'successful'; anything with an explicit failure token and no
    // matching explicit success on the other field is genuinely failed.
    if ((txStatus === 'success' || respStatus === 'success')) {
      return { ...fields, state: 'unknown', failureCategory: 'contradictory_status', errorMessage: 'transaction_status and response.status disagreed.' }
    }
    return { ...fields, state: 'failed', failureCategory: 'provider_declined', errorMessage: 'Provider reported the collection failed.' }
  }

  // Neither field matched a recognized token (missing, or an unrecognized
  // vocabulary this module doesn't yet know) — the conservative default.
  return { ...fields, state: 'unknown', failureCategory: 'unrecognized_status', errorMessage: 'Provider response did not contain a recognized success/failure status.' }
}
