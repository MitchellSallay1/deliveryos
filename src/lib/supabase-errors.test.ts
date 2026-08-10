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

  it('maps feature_not_available to a plan-upgrade message', () => {
    expect(parseSupabaseError({ message: 'feature_not_available' })).toMatch(/plan upgrade/i)
  })

  it('maps gps_not_enabled to a plan-specific message, distinct from the generic feature gate', () => {
    const msg = parseSupabaseError({ message: 'gps_not_enabled' })
    expect(msg).toMatch(/GPS/i)
    expect(msg).not.toBe(parseSupabaseError({ message: 'feature_not_available' }))
  })

  it('maps rider_plan_limit_reached', () => {
    expect(parseSupabaseError({ message: 'rider_plan_limit_reached' })).toMatch(/rider limit/i)
  })

  it('maps subscription_past_due', () => {
    expect(parseSupabaseError({ message: 'subscription_past_due' })).toMatch(/past due/i)
  })
})
