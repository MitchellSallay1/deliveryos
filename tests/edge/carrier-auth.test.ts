import { afterEach, describe, expect, it, vi } from 'vitest'
import { verifySharedSecretQueryParam } from '../../supabase/functions/_shared/carrier-auth.ts'

function req(url: string): Request {
  return new Request(url, { method: 'POST' })
}

describe('verifySharedSecretQueryParam', () => {
  afterEach(() => {
    vi.unstubAllEnvs()
  })

  it('fails closed (503) when the env var is not configured', () => {
    vi.stubGlobal('Deno', { env: { get: () => undefined } })
    const result = verifySharedSecretQueryParam(req('https://x.test/whatsapp-webhook?token=anything'), 'GUPSHUP_WEBHOOK_SECRET', 'token')
    expect(result).toEqual({
      ok: false,
      status: 503,
      code: 'not_configured',
      message: expect.stringContaining('GUPSHUP_WEBHOOK_SECRET'),
    })
  })

  it('rejects (401) a request with no token when a secret is configured', () => {
    vi.stubGlobal('Deno', { env: { get: () => 'real-secret' } })
    const result = verifySharedSecretQueryParam(req('https://x.test/whatsapp-webhook'), 'GUPSHUP_WEBHOOK_SECRET', 'token')
    expect(result.ok).toBe(false)
    if (!result.ok) expect(result.status).toBe(401)
  })

  it('rejects (401) a request with the wrong token', () => {
    vi.stubGlobal('Deno', { env: { get: () => 'real-secret' } })
    const result = verifySharedSecretQueryParam(req('https://x.test/whatsapp-webhook?token=wrong'), 'GUPSHUP_WEBHOOK_SECRET', 'token')
    expect(result.ok).toBe(false)
    if (!result.ok) expect(result.status).toBe(401)
  })

  it('accepts a request with the correct token', () => {
    vi.stubGlobal('Deno', { env: { get: () => 'real-secret' } })
    const result = verifySharedSecretQueryParam(req('https://x.test/whatsapp-webhook?token=real-secret'), 'GUPSHUP_WEBHOOK_SECRET', 'token')
    expect(result).toEqual({ ok: true })
  })
})
