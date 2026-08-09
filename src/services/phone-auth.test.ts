import { beforeEach, describe, expect, it, vi } from 'vitest'

const authState = vi.hoisted(() => ({
  signInWithOtp: vi.fn(),
  verifyOtp: vi.fn(),
}))

vi.mock('@/lib/supabase/client', () => ({
  supabase: { auth: authState },
}))

import { sendAuthSmsOtp, verifyAuthSmsOtp } from '@/services/auth-sms-provider'
import { friendlyAuthOtpError } from '@/lib/auth-otp-errors'

describe('auth SMS provider', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('requests OTP via Supabase signInWithOtp', async () => {
    authState.signInWithOtp.mockResolvedValue({ error: null })
    const result = await sendAuthSmsOtp('0881697769')
    expect(result.phoneE164).toBe('+231881697769')
    expect(authState.signInWithOtp).toHaveBeenCalledWith({
      phone: '+231881697769',
      options: { channel: 'sms' },
    })
  })

  it('verifies OTP via Supabase verifyOtp', async () => {
    authState.verifyOtp.mockResolvedValue({
      data: { session: { access_token: 't' } },
      error: null,
    })
    const { session } = await verifyAuthSmsOtp('+231881697769', '123456')
    expect(session).toBeTruthy()
    expect(authState.verifyOtp).toHaveBeenCalledWith({
      phone: '+231881697769',
      token: '123456',
      type: 'sms',
    })
  })

  it('maps invalid OTP to friendly message', () => {
    const msg = friendlyAuthOtpError(new Error('Token has expired or is invalid'))
    expect(msg.toLowerCase()).toMatch(/expired|incorrect/)
  })
})
