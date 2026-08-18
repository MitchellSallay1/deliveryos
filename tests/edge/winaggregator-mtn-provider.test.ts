import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import {
  WinAggregatorMtnProvider,
  maskMsisdn,
  normalizeMtnCollectionResult,
  parseDecimalToCents,
  validateMtnMsisdn,
  type MtnRawResult,
} from '../../supabase/functions/_shared/winaggregator-mtn-provider.ts'

describe('validateMtnMsisdn', () => {
  it('normalizes a 9-digit local number', () => {
    expect(validateMtnMsisdn('770229690')).toEqual({ ok: true, normalized: '231770229690' })
  })

  it('normalizes a 10-digit local number with a leading 0', () => {
    expect(validateMtnMsisdn('0770229690')).toEqual({ ok: true, normalized: '231770229690' })
  })

  it('accepts an already-231-prefixed number', () => {
    expect(validateMtnMsisdn('+231770229690')).toEqual({ ok: true, normalized: '231770229690' })
    expect(validateMtnMsisdn('231770229690')).toEqual({ ok: true, normalized: '231770229690' })
  })

  it('strips formatting characters (spaces, dashes, parens)', () => {
    expect(validateMtnMsisdn('+231 770-229-690')).toEqual({ ok: true, normalized: '231770229690' })
  })

  it('rejects empty input', () => {
    expect(validateMtnMsisdn('')).toEqual({ ok: false, error: 'empty_msisdn' })
  })

  it('rejects garbage / non-numeric input', () => {
    expect(validateMtnMsisdn('not-a-phone').ok).toBe(false)
  })

  it('rejects a number that is too short', () => {
    expect(validateMtnMsisdn('12345').ok).toBe(false)
  })

  it('rejects a number that is too long', () => {
    expect(validateMtnMsisdn('12345678901234').ok).toBe(false)
  })

  it('never silently produces a different valid-looking number for a malformed input', () => {
    // An 8-digit number is neither a valid 9-digit local number nor a
    // 10-digit-with-leading-zero number — it must be rejected, not coerced.
    const result = validateMtnMsisdn('77022969')
    expect(result.ok).toBe(false)
  })
})

describe('maskMsisdn', () => {
  it('shows only the last 4 digits', () => {
    expect(maskMsisdn('231770229690')).toBe('***9690')
  })

  it('never reveals more than 4 digits regardless of input length', () => {
    const masked = maskMsisdn('231770229690')
    expect(masked.replace('***', '')).toHaveLength(4)
  })
})

describe('parseDecimalToCents', () => {
  it('parses a decimal string via string-safe digit reconstruction, not float multiplication', () => {
    expect(parseDecimalToCents('1000.00')).toBe(100000)
    expect(parseDecimalToCents('19.99')).toBe(1999)
    expect(parseDecimalToCents('0.01')).toBe(1)
  })

  it('parses a whole-number string with no decimal point', () => {
    expect(parseDecimalToCents('1000')).toBe(100000)
  })

  it('parses a JSON number as a fallback', () => {
    expect(parseDecimalToCents(1000)).toBe(100000)
    expect(parseDecimalToCents(19.99)).toBe(1999)
  })

  it('handles a negative value', () => {
    expect(parseDecimalToCents('-50.00')).toBe(-5000)
  })

  it('returns null for null/undefined/non-numeric input rather than throwing', () => {
    expect(parseDecimalToCents(null)).toBeNull()
    expect(parseDecimalToCents(undefined)).toBeNull()
    expect(parseDecimalToCents('not a number')).toBeNull()
    expect(parseDecimalToCents({})).toBeNull()
  })

  it('pads a single decimal digit correctly (avoids the classic "1.5" -> 105 cents bug)', () => {
    expect(parseDecimalToCents('1.5')).toBe(150)
  })
})

describe('WinAggregatorMtnProvider.collect', () => {
  const originalFetch = globalThis.fetch

  beforeEach(() => {
    globalThis.fetch = vi.fn()
  })

  afterEach(() => {
    globalThis.fetch = originalFetch
    vi.restoreAllMocks()
  })

  it('POSTs the documented request shape to the /collection endpoint', async () => {
    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>
    fetchMock.mockResolvedValue(new Response(JSON.stringify({ transaction_status: 'SUCCESSFUL' }), { status: 200 }))

    const provider = new WinAggregatorMtnProvider({
      secretString: 'test-secret',
      companyName: 'DeliveryOS',
      baseUrl: 'https://winaggregator-mtn.com/mtn/api/v1',
    })

    await provider.collect({ amountCents: 100000, currency: 'LRD', externalId: 'PAY-ABC123', msisdn: '231770229690' })

    expect(fetchMock).toHaveBeenCalledTimes(1)
    const [url, init] = fetchMock.mock.calls[0]
    expect(url).toBe('https://winaggregator-mtn.com/mtn/api/v1/collection')
    expect(init.method).toBe('POST')
    const body = JSON.parse(init.body)
    expect(body).toEqual({
      secret_string: 'test-secret',
      company_name: 'DeliveryOS',
      amount: '1000.00',
      currency: 'LRD',
      externalID: 'PAY-ABC123',
      msisdn: '231770229690',
    })
  })

  it('never sends the secret anywhere but the JSON body (not the URL)', async () => {
    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>
    fetchMock.mockResolvedValue(new Response('{}', { status: 200 }))

    const provider = new WinAggregatorMtnProvider({ secretString: 'super-secret-value', companyName: 'DeliveryOS' })
    await provider.collect({ amountCents: 100000, currency: 'LRD', externalId: 'PAY-1', msisdn: '231770229690' })

    const [url] = fetchMock.mock.calls[0]
    expect(url).not.toContain('super-secret-value')
  })

  it('returns a timeout result, not a thrown error, when the request is aborted', async () => {
    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>
    fetchMock.mockImplementation(() => {
      const err = new Error('aborted')
      err.name = 'AbortError'
      return Promise.reject(err)
    })

    const provider = new WinAggregatorMtnProvider({ secretString: 'x', companyName: 'DeliveryOS' })
    const result = await provider.collect({ amountCents: 1000, currency: 'LRD', externalId: 'PAY-1', msisdn: '231770229690' })

    expect(result).toEqual({ kind: 'timeout' })
  })

  it('returns a network_error result, not a thrown error, on a connection failure', async () => {
    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>
    fetchMock.mockRejectedValue(new Error('connection reset'))

    const provider = new WinAggregatorMtnProvider({ secretString: 'x', companyName: 'DeliveryOS' })
    const result = await provider.collect({ amountCents: 1000, currency: 'LRD', externalId: 'PAY-1', msisdn: '231770229690' })

    expect(result).toEqual({ kind: 'network_error', error: 'connection reset' })
  })
})

describe('normalizeMtnCollectionResult — the money-failure matrix', () => {
  function response(httpStatus: number, body: unknown): MtnRawResult {
    return { kind: 'response', httpStatus, parsed: body as never, rawText: JSON.stringify(body) }
  }

  it('1) HTTP 200 + explicit success token -> successful, with parsed provider figures', () => {
    const result = normalizeMtnCollectionResult(
      response(200, {
        reference_id: 'ref-1',
        transaction_status: 'SUCCESSFUL',
        gross_amount: '1000.00',
        provider_fee_deducted: '40.00',
        net_merchant_credited: '960.00',
        response: { financialTransactionId: 'fin-1', status: 'SUCCESSFUL' },
      }),
    )
    expect(result.state).toBe('successful')
    expect(result.providerGrossCents).toBe(100000)
    expect(result.providerFeeCents).toBe(4000)
    expect(result.providerNetCents).toBe(96000)
    expect(result.financialTransactionId).toBe('fin-1')
  })

  it('2) HTTP 200 + explicit failure token -> failed', () => {
    const result = normalizeMtnCollectionResult(response(200, { transaction_status: 'FAILED', response: { status: 'FAILED' } }))
    expect(result.state).toBe('failed')
    expect(result.failureCategory).toBe('provider_declined')
  })

  it('3) HTTP 202 -> pending regardless of body content', () => {
    const result = normalizeMtnCollectionResult(response(202, { transaction_status: 'anything' }))
    expect(result.state).toBe('pending')
    expect(result.httpStatus).toBe(202)
  })

  it('4) timeout -> unknown, never failed', () => {
    const result = normalizeMtnCollectionResult({ kind: 'timeout' })
    expect(result.state).toBe('unknown')
    expect(result.failureCategory).toBe('timeout')
  })

  it('5) network reset -> unknown, never failed', () => {
    const result = normalizeMtnCollectionResult({ kind: 'network_error', error: 'ECONNRESET' })
    expect(result.state).toBe('unknown')
    expect(result.failureCategory).toBe('network_error')
  })

  it('6) HTTP 500 -> unknown, never assumed failed (the request may have reached MTN)', () => {
    const result = normalizeMtnCollectionResult(response(500, { transaction_status: 'SUCCESSFUL' }))
    expect(result.state).toBe('unknown')
    expect(result.failureCategory).toBe('provider_server_error')
  })

  it('7) malformed (non-JSON) body -> unknown, even on HTTP 200', () => {
    const result = normalizeMtnCollectionResult({ kind: 'response', httpStatus: 200, parsed: null, rawText: 'not json' })
    expect(result.state).toBe('unknown')
    expect(result.failureCategory).toBe('malformed_response')
  })

  it('8) HTTP 200 with no status field at all -> unknown, never assumed successful', () => {
    const result = normalizeMtnCollectionResult(response(200, { reference_id: 'ref-1' }))
    expect(result.state).toBe('unknown')
    expect(result.failureCategory).toBe('unrecognized_status')
  })

  it('9) unrecognized status vocabulary -> unknown, never guessed at', () => {
    const result = normalizeMtnCollectionResult(response(200, { transaction_status: 'SOME_NEW_STATUS_WE_DONT_KNOW' }))
    expect(result.state).toBe('unknown')
    expect(result.failureCategory).toBe('unrecognized_status')
  })

  it('10) contradictory status (one field success, the other failure) -> unknown, never resolved in favor of success', () => {
    const result = normalizeMtnCollectionResult(
      response(200, { transaction_status: 'SUCCESSFUL', response: { status: 'FAILED' } }),
    )
    expect(result.state).toBe('unknown')
    expect(result.failureCategory).toBe('contradictory_status')
  })

  it('11) HTTP 4xx with an identifiable status -> failed (provider explicitly rejected before any charge could occur)', () => {
    const result = normalizeMtnCollectionResult(response(400, { transaction_status: 'FAILED', reference_id: 'ref-1' }))
    expect(result.state).toBe('failed')
    expect(result.failureCategory).toBe('request_rejected')
  })

  it('12) HTTP 4xx with NO identifiable status/body content -> unknown, not assumed failed', () => {
    const result = normalizeMtnCollectionResult(response(422, {}))
    expect(result.state).toBe('unknown')
    expect(result.failureCategory).toBe('malformed_rejection')
  })

  it('13) never trusts a raw amount as authoritative without going through parseDecimalToCents (string-safe)', () => {
    const result = normalizeMtnCollectionResult(
      response(200, { transaction_status: 'SUCCESSFUL', gross_amount: '1000.00', provider_fee_deducted: '40.00', net_merchant_credited: '960.00' }),
    )
    // Exact integer cents, not a float-drifted value.
    expect(result.providerGrossCents).toBe(100000)
    expect(Number.isInteger(result.providerGrossCents)).toBe(true)
  })

  it('14) case-insensitive status token matching', () => {
    const result = normalizeMtnCollectionResult(response(200, { transaction_status: 'successful' }))
    expect(result.state).toBe('successful')
  })
})
