import { describe, expect, it } from 'vitest'
import {
  buildAuthOtpMessage,
  buildHookHttpResponse,
  buildHookRejectedResponse,
} from '../../supabase/functions/_shared/auth-sms-hook-support.ts'

describe('buildAuthOtpMessage', () => {
  it('embeds the real OTP digits Supabase generated, not a template placeholder', () => {
    const msg = buildAuthOtpMessage('482913')
    expect(msg).toContain('482913')
    expect(msg).not.toContain('{{')
    expect(msg).not.toContain('.Code')
  })

  it('is short enough for a single SMS segment', () => {
    const msg = buildAuthOtpMessage('482913')
    expect(msg.length).toBeLessThanOrEqual(160)
  })

  it('never fabricates a different OTP than the one passed in', () => {
    const a = buildAuthOtpMessage('111111')
    const b = buildAuthOtpMessage('222222')
    expect(a).not.toBe(b)
    expect(a).toContain('111111')
    expect(b).toContain('222222')
  })
})

describe('buildHookHttpResponse', () => {
  it('returns 200 with an empty body on success — the documented Send SMS Hook success contract', () => {
    const res = buildHookHttpResponse({ ok: true })
    expect(res.status).toBe(200)
    expect(res.body).toEqual({})
  })

  it('returns a non-200 status with a short generic reason on failure', () => {
    const res = buildHookHttpResponse({ ok: false, reason: 'sms_send_failed' })
    expect(res.status).not.toBe(200)
    expect(res.body).toEqual({ error: 'sms_send_failed' })
  })

  it('never includes an OTP-shaped value in any response body, success or failure', () => {
    const success = buildHookHttpResponse({ ok: true })
    const failure = buildHookHttpResponse({ ok: false, reason: 'sms_send_failed' })
    expect(JSON.stringify(success.body)).not.toMatch(/\d{4,8}/)
    expect(JSON.stringify(failure.body)).not.toMatch(/\d{4,8}/)
  })
})

describe('buildHookRejectedResponse', () => {
  it('fails closed with 503 when the hook secret is not configured', () => {
    const res = buildHookRejectedResponse('not_configured')
    expect(res.status).toBe(503)
  })

  it('rejects an invalid signature with 401, not a soft/ambiguous status', () => {
    const res = buildHookRejectedResponse('invalid_signature')
    expect(res.status).toBe(401)
  })

  it('rejects a payload missing phone/otp with 401', () => {
    const res = buildHookRejectedResponse('invalid_payload')
    expect(res.status).toBe(401)
  })

  it('never leaks the raw request payload or headers in any rejection body', () => {
    const res = buildHookRejectedResponse('invalid_signature')
    expect(Object.keys(res.body)).toEqual(['error'])
  })
})
