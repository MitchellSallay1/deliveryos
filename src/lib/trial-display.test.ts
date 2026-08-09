import { describe, expect, it } from 'vitest'
import { trialBannerMessage } from '@/lib/trial-display'

describe('trialBannerMessage', () => {
  it('shows free trial with days remaining', () => {
    const msg = trialBannerMessage({
      is_free_trial: true,
      status: 'trialing',
      trial_ends_at: new Date(Date.now() + 5 * 86400000).toISOString(),
      days_remaining: 5,
      expired: false,
    })
    expect(msg?.headline).toBe('Free trial')
    expect(msg?.detail).toMatch(/5 days remaining/)
  })

  it('warns at 3 days remaining', () => {
    const msg = trialBannerMessage({
      is_free_trial: true,
      days_remaining: 3,
      trial_ends_at: new Date().toISOString(),
    })
    expect(msg?.headline).toBe('3 days remaining on your free trial')
    expect(msg?.tone).toBe('warning')
  })

  it('warns at 1 day remaining', () => {
    const msg = trialBannerMessage({
      is_free_trial: true,
      days_remaining: 1,
      trial_ends_at: new Date().toISOString(),
    })
    expect(msg?.headline).toBe('1 day remaining on your free trial')
  })

  it('shows expired trial message', () => {
    const msg = trialBannerMessage({
      is_free_trial: true,
      expired: true,
      status: 'expired',
    })
    expect(msg?.headline).toBe('Trial expired — choose a plan')
    expect(msg?.detail).toMatch(/7-day free trial has ended/)
  })
})
