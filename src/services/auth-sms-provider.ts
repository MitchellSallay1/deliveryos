/**
 * Authentication SMS boundary (provider-neutral).
 *
 * DeliveryOS does not send auth OTP from the browser with third-party credentials.
 * Supabase Auth invokes the configured SMS provider (e.g. MTN via Auth Hook / Twilio template in Dashboard).
 *
 * This module is the single client entry for auth OTP requests; swap or extend server-side
 * integration without changing UI call sites.
 */

import { supabase } from '@/lib/supabase/client'
import { normalizePhoneE164 } from '@/lib/phone'
import { friendlyAuthOtpError } from '@/lib/auth-otp-errors'
import type { Session } from '@supabase/supabase-js'

export type SendAuthOtpResult = { phoneE164: string }

export async function sendAuthSmsOtp(rawPhone: string): Promise<SendAuthOtpResult> {
  const phoneE164 = normalizePhoneE164(rawPhone)
  const { error } = await supabase.auth.signInWithOtp({
    phone: phoneE164,
    options: { channel: 'sms' },
  })
  if (error) throw new Error(friendlyAuthOtpError(error))
  return { phoneE164 }
}

export async function verifyAuthSmsOtp(
  rawPhone: string,
  token: string,
): Promise<{ session: Session | null }> {
  const phoneE164 = normalizePhoneE164(rawPhone)
  const { data, error } = await supabase.auth.verifyOtp({
    phone: phoneE164,
    token: token.trim(),
    type: 'sms',
  })
  if (error) throw new Error(friendlyAuthOtpError(error))
  return { session: data.session }
}
