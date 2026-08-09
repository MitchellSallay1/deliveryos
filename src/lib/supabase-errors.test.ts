import { describe, expect, it } from 'vitest'
import { parseSupabaseError } from '@/lib/supabase-errors'

describe('parseSupabaseError', () => {
  it('maps company_suspended to friendly copy', () => {
    expect(parseSupabaseError({ message: 'company_suspended' })).toMatch(/suspended/i)
  })

  it('maps delivery_monthly_limit_reached', () => {
    expect(parseSupabaseError({ message: 'delivery_monthly_limit_reached' })).toMatch(
      /monthly delivery limit/i,
    )
  })

  it('maps trial_expired to friendly copy', () => {
    expect(parseSupabaseError({ message: 'trial_expired' })).toMatch(/7-day free trial has ended/i)
  })

  it('maps invitation_phone_mismatch', () => {
    expect(parseSupabaseError({ message: 'invitation_phone_mismatch' })).toMatch(/phone number/i)
  })
})
