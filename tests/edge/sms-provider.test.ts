import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { normalizeLiberianPhone, WinAggregatorSmsProvider } from '../../supabase/functions/_shared/sms-provider.ts'

describe('normalizeLiberianPhone', () => {
  it('prepends 231 to a 9-digit local number', () => {
    expect(normalizeLiberianPhone('770229690')).toBe('231770229690')
  })

  it('strips a leading 0 from a 10-digit local number before prepending 231', () => {
    expect(normalizeLiberianPhone('0770229690')).toBe('231770229690')
  })

  it('leaves an already-231-prefixed number as bare digits, no plus', () => {
    expect(normalizeLiberianPhone('+231770229690')).toBe('231770229690')
    expect(normalizeLiberianPhone('231770229690')).toBe('231770229690')
    expect(normalizeLiberianPhone('+231770229690')).not.toMatch(/^\+/)
  })

  it('strips non-digit characters (spaces, dashes, parens)', () => {
    expect(normalizeLiberianPhone('+231 770-229-690')).toBe('231770229690')
  })

  it('returns empty string for empty/garbage input rather than throwing', () => {
    expect(normalizeLiberianPhone('')).toBe('')
    expect(normalizeLiberianPhone('abc')).toBe('')
  })
})

describe('WinAggregatorSmsProvider', () => {
  const originalFetch = globalThis.fetch

  beforeEach(() => {
    globalThis.fetch = vi.fn()
  })

  afterEach(() => {
    globalThis.fetch = originalFetch
    vi.restoreAllMocks()
  })

  it('POSTs the exact confirmed production payload shape to the configured endpoint', async () => {
    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>
    fetchMock.mockResolvedValue(new Response('ok', { status: 200 }))

    const provider = new WinAggregatorSmsProvider({
      endpoint: 'https://winaggregator-mtn.com/request/sms-service/1',
      senderId: 'DelivOS',
    })

    await provider.send({ phone: '0770229690', message: 'Hello' })

    expect(fetchMock).toHaveBeenCalledTimes(1)
    const [url, init] = fetchMock.mock.calls[0]
    expect(url).toBe('https://winaggregator-mtn.com/request/sms-service/1')
    expect(init.method).toBe('POST')
    expect(JSON.parse(init.body)).toEqual({
      sender_id: 'DelivOS',
      destination: '231770229690',
      message: 'Hello',
    })
  })

  it('never sends destination with a leading plus', async () => {
    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>
    fetchMock.mockResolvedValue(new Response('ok', { status: 200 }))

    const provider = new WinAggregatorSmsProvider({
      endpoint: 'https://winaggregator-mtn.com/request/sms-service/1',
      senderId: 'DelivOS',
    })
    await provider.send({ phone: '+231770229690', message: 'Hi' })

    const [, init] = fetchMock.mock.calls[0]
    const body = JSON.parse(init.body)
    expect(body.destination).toBe('231770229690')
    expect(body.destination).not.toMatch(/^\+/)
  })

  it('never sends an Authorization header — no auth is required or invented for this provider', async () => {
    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>
    fetchMock.mockResolvedValue(new Response('ok', { status: 200 }))

    const provider = new WinAggregatorSmsProvider({
      endpoint: 'https://winaggregator-mtn.com/request/sms-service/1',
      senderId: 'DelivOS',
    })
    await provider.send({ phone: '231770229690', message: 'Hi' })

    const [, init] = fetchMock.mock.calls[0]
    expect(init.headers).toEqual({ 'Content-Type': 'application/json' })
  })

  it('treats any 2xx response as provider acceptance without assuming a JSON body shape', async () => {
    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>
    fetchMock.mockResolvedValue(new Response('not json at all', { status: 200 }))

    const provider = new WinAggregatorSmsProvider({
      endpoint: 'https://winaggregator-mtn.com/request/sms-service/1',
      senderId: 'DelivOS',
    })
    const result = await provider.send({ phone: '231770229690', message: 'Hi' })

    expect(result.ok).toBe(true)
    if (result.ok) {
      expect(result.httpStatus).toBe(200)
      expect(result.providerResponseRaw).toBe('not json at all')
    }
  })

  it('treats a non-2xx response as failure and surfaces the raw body for diagnostics', async () => {
    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>
    fetchMock.mockResolvedValue(new Response('insufficient balance', { status: 402 }))

    const provider = new WinAggregatorSmsProvider({
      endpoint: 'https://winaggregator-mtn.com/request/sms-service/1',
      senderId: 'DelivOS',
    })
    const result = await provider.send({ phone: '231770229690', message: 'Hi' })

    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.httpStatus).toBe(402)
      expect(result.providerResponseRaw).toBe('insufficient balance')
    }
  })

  it('fails closed on an invalid/unnormalizable phone number instead of sending garbage', async () => {
    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>
    const provider = new WinAggregatorSmsProvider({
      endpoint: 'https://winaggregator-mtn.com/request/sms-service/1',
      senderId: 'DelivOS',
    })
    const result = await provider.send({ phone: '', message: 'Hi' })

    expect(result.ok).toBe(false)
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('handles a network-level failure without throwing', async () => {
    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>
    fetchMock.mockRejectedValue(new Error('network down'))

    const provider = new WinAggregatorSmsProvider({
      endpoint: 'https://winaggregator-mtn.com/request/sms-service/1',
      senderId: 'DelivOS',
    })
    const result = await provider.send({ phone: '231770229690', message: 'Hi' })

    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.error).toBe('network down')
    }
  })

  it('aborts and returns a timeout result if the provider does not respond in time', async () => {
    vi.useFakeTimers()
    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>
    fetchMock.mockImplementation(
      (_url: string, init: RequestInit) =>
        new Promise((_resolve, reject) => {
          init.signal?.addEventListener('abort', () => {
            reject(Object.assign(new Error('The operation was aborted.'), { name: 'AbortError' }))
          })
        }),
    )

    const provider = new WinAggregatorSmsProvider({
      endpoint: 'https://winaggregator-mtn.com/request/sms-service/1',
      senderId: 'DelivOS',
      timeoutMs: 1000,
    })
    const resultPromise = provider.send({ phone: '231770229690', message: 'Hi' })
    await vi.advanceTimersByTimeAsync(1000)
    const result = await resultPromise

    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.error).toBe('timeout')
    }
    vi.useRealTimers()
  })

  it('defaults to a 4-second timeout when none is configured', async () => {
    vi.useFakeTimers()
    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>
    fetchMock.mockImplementation(
      (_url: string, init: RequestInit) =>
        new Promise((_resolve, reject) => {
          init.signal?.addEventListener('abort', () => {
            reject(Object.assign(new Error('The operation was aborted.'), { name: 'AbortError' }))
          })
        }),
    )

    const provider = new WinAggregatorSmsProvider({
      endpoint: 'https://winaggregator-mtn.com/request/sms-service/1',
      senderId: 'DelivOS',
    })
    const resultPromise = provider.send({ phone: '231770229690', message: 'Hi' })
    await vi.advanceTimersByTimeAsync(3999)
    await vi.advanceTimersByTimeAsync(1)
    const result = await resultPromise

    expect(result.ok).toBe(false)
    vi.useRealTimers()
  })

  it('sends an identical request shape regardless of which Liberian network the number belongs to (no MTN/Orange routing split)', async () => {
    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>
    fetchMock.mockResolvedValue(new Response('ok', { status: 200 }))

    const provider = new WinAggregatorSmsProvider({
      endpoint: 'https://winaggregator-mtn.com/request/sms-service/1',
      senderId: 'DelivOS',
    })

    // Two distinct real-format Liberian mobile numbers, representative of
    // the two GSM networks this endpoint is confirmed to serve.
    await provider.send({ phone: '0881697769', message: 'Hi' })
    await provider.send({ phone: '0770229690', message: 'Hi' })

    expect(fetchMock).toHaveBeenCalledTimes(2)
    const [urlA, initA] = fetchMock.mock.calls[0]
    const [urlB, initB] = fetchMock.mock.calls[1]
    expect(urlA).toBe(urlB)
    expect(JSON.parse(initA.body).sender_id).toBe(JSON.parse(initB.body).sender_id)
    expect(JSON.parse(initA.body).destination).toBe('231881697769')
    expect(JSON.parse(initB.body).destination).toBe('231770229690')
  })
})
