import type { AuthError } from '@supabase/supabase-js'

/** User-safe messages for phone OTP (never expose raw Postgres/Auth internals). */
export function friendlyAuthOtpError(error: AuthError | Error | null | undefined): string {
  if (!error) return 'Something went wrong. Please try again.'
  const msg = error.message.toLowerCase()

  if (msg.includes('otp') && msg.includes('expired')) {
    return 'That code has expired. Request a new verification code.'
  }
  if (msg.includes('invalid') && (msg.includes('otp') || msg.includes('token'))) {
    return 'That code is incorrect. Check the SMS and try again.'
  }
  if (msg.includes('rate') || msg.includes('too many')) {
    return 'Too many attempts. Wait a moment before trying again.'
  }
  if (msg.includes('sms') || msg.includes('provider')) {
    return 'We could not send a text message right now. Try again later.'
  }
  if (msg.includes('phone') && msg.includes('invalid')) {
    return 'Enter a valid mobile number including country code (e.g. +231…).'
  }
  if (msg.includes('signup') && msg.includes('disabled')) {
    return 'New sign-ups are temporarily unavailable.'
  }

  return 'Could not verify your phone. Try again or contact support.'
}
