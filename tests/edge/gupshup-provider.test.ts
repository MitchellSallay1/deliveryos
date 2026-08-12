import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { GupshupProvider, classifyGupshupFailure } from '../../supabase/functions/_shared/gupshup-provider.ts'
import { normalizeLiberianPhone } from '../../supabase/functions/_shared/sms-provider.ts'

const CONFIG = { apiKey: 'test-key', appName: 'DeliveryOS', sourceNumber: '231770000000' }

describe('GupshupProvider.sendText', () => {
  const originalFetch = globalThis.fetch

  beforeEach(() => {
    globalThis.fetch = vi.fn()
  })

  afterEach(() => {
    globalThis.fetch = originalFetch
    vi.restoreAllMocks()
  })

  it('POSTs form-encoded to the confirmed session-message endpoint with apikey header', async () => {
    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>
    fetchMock.mockResolvedValue(new Response(JSON.stringify({ status: 'submitted', messageId: 'msg-1' }), { status: 202 }))

    const provider = new GupshupProvider(CONFIG)
    const result = await provider.sendText({ destination: '231770229690', text: 'Hello' })

    expect(fetchMock).toHaveBeenCalledTimes(1)
    const [url, init] = fetchMock.mock.calls[0]
    expect(url).toBe('https://api.gupshup.io/wa/api/v1/msg')
    expect(init.method).toBe('POST')
    expect(init.headers.apikey).toBe('test-key')
    expect(init.headers['Content-Type']).toBe('application/x-www-form-urlencoded')

    const params = new URLSearchParams(init.body)
    expect(params.get('channel')).toBe('whatsapp')
    expect(params.get('source')).toBe('231770000000')
    expect(params.get('destination')).toBe('231770229690')
    expect(params.get('src.name')).toBe('DeliveryOS')
    expect(JSON.parse(params.get('message')!)).toEqual({ type: 'text', text: 'Hello' })

    expect(result).toEqual({ ok: true, httpStatus: 202, providerMessageId: 'msg-1', providerResponseRaw: expect.any(String) })
  })

  it('never sends the api key anywhere but the apikey header (not in the body, not as a query param)', async () => {
    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>
    fetchMock.mockResolvedValue(new Response(JSON.stringify({ status: 'submitted', messageId: 'm' }), { status: 200 }))

    const provider = new GupshupProvider(CONFIG)
    await provider.sendText({ destination: '231770229690', text: 'Hi' })

    const [url, init] = fetchMock.mock.calls[0]
    expect(url).not.toContain('test-key')
    expect(init.body).not.toContain('test-key')
  })
})

describe('GupshupProvider.sendTemplate', () => {
  const originalFetch = globalThis.fetch

  beforeEach(() => {
    globalThis.fetch = vi.fn()
  })

  afterEach(() => {
    globalThis.fetch = originalFetch
    vi.restoreAllMocks()
  })

  it('POSTs to the confirmed template endpoint with id + ordered params', async () => {
    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>
    fetchMock.mockResolvedValue(new Response(JSON.stringify({ status: 'success', messageId: 'tmpl-1' }), { status: 202 }))

    const provider = new GupshupProvider(CONFIG)
    const result = await provider.sendTemplate({
      destination: '231770229690',
      templateId: 'gs-template-abc',
      params: ['ORD-202608-00001', 'Jane Doe', '1200.00'],
    })

    const [url, init] = fetchMock.mock.calls[0]
    expect(url).toBe('https://api.gupshup.io/wa/api/v1/template/msg')
    const params = new URLSearchParams(init.body)
    expect(JSON.parse(params.get('template')!)).toEqual({
      id: 'gs-template-abc',
      params: ['ORD-202608-00001', 'Jane Doe', '1200.00'],
    })
    expect(result.ok).toBe(true)
  })
})

describe('GupshupProvider failure handling', () => {
  const originalFetch = globalThis.fetch

  beforeEach(() => {
    globalThis.fetch = vi.fn()
  })

  afterEach(() => {
    globalThis.fetch = originalFetch
    vi.restoreAllMocks()
  })

  it('surfaces a non-2xx response as a structured failure, not a thrown error', async () => {
    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>
    fetchMock.mockResolvedValue(new Response(JSON.stringify({ status: 'error', message: 'invalid destination' }), { status: 400 }))

    const provider = new GupshupProvider(CONFIG)
    const result = await provider.sendText({ destination: '231770229690', text: 'Hi' })

    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.httpStatus).toBe(400)
    }
  })

  it('treats a network failure as a transient error, not a crash', async () => {
    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>
    fetchMock.mockRejectedValue(new Error('network down'))

    const provider = new GupshupProvider(CONFIG)
    const result = await provider.sendText({ destination: '231770229690', text: 'Hi' })

    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.httpStatus).toBeNull()
    }
  })

  it('does not assume a JSON body — a non-JSON success response still resolves ok with a null providerMessageId', async () => {
    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>
    fetchMock.mockResolvedValue(new Response('not json', { status: 200 }))

    const provider = new GupshupProvider(CONFIG)
    const result = await provider.sendText({ destination: '231770229690', text: 'Hi' })

    expect(result.ok).toBe(true)
    if (result.ok) {
      expect(result.providerMessageId).toBeNull()
    }
  })
})

describe('classifyGupshupFailure', () => {
  it('classifies HTTP 429 as rate_limited', () => {
    expect(classifyGupshupFailure({ ok: false, httpStatus: 429, error: 'x' })).toBe('rate_limited')
  })

  it('classifies other 4xx as permanent (validation/recipient/template problems a retry cannot fix)', () => {
    expect(classifyGupshupFailure({ ok: false, httpStatus: 400, error: 'x' })).toBe('permanent')
    expect(classifyGupshupFailure({ ok: false, httpStatus: 401, error: 'x' })).toBe('permanent')
    expect(classifyGupshupFailure({ ok: false, httpStatus: 404, error: 'x' })).toBe('permanent')
  })

  it('classifies 5xx and network/timeout failures (null status) as transient', () => {
    expect(classifyGupshupFailure({ ok: false, httpStatus: 500, error: 'x' })).toBe('transient')
    expect(classifyGupshupFailure({ ok: false, httpStatus: 503, error: 'x' })).toBe('transient')
    expect(classifyGupshupFailure({ ok: false, httpStatus: null, error: 'timeout' })).toBe('transient')
  })
})

describe('Gupshup destination phone reuses the shared Liberia normalizer', () => {
  it('produces the exact same digits-only-with-231-prefix shape Gupshup expects (no reinvented formatter)', () => {
    expect(normalizeLiberianPhone('0770229690')).toBe('231770229690')
    expect(normalizeLiberianPhone('+231770229690')).toBe('231770229690')
    expect(normalizeLiberianPhone('+231 88 123 4567')).toBe('231881234567')
  })
})
