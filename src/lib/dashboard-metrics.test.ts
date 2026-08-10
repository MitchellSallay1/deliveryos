import { describe, expect, it } from 'vitest'
import {
  buildAttentionItems,
  formatElapsed,
  friendlyDashboardError,
  greetingForHour,
  isFeatureGatedError,
  isGpsNotEnabledError,
  latestDeliveryTimestamp,
  onboardingProgressLabel,
  riderAvailabilityBreakdown,
  OVERDUE_PICKUP_MINUTES,
} from './dashboard-metrics'

describe('greetingForHour', () => {
  it('greets morning before noon', () => {
    expect(greetingForHour(9)).toBe('Good morning')
  })
  it('greets afternoon before 6pm', () => {
    expect(greetingForHour(14)).toBe('Good afternoon')
  })
  it('greets evening after 6pm', () => {
    expect(greetingForHour(20)).toBe('Good evening')
  })
  it('boundary: exactly noon is afternoon, exactly 18 is evening', () => {
    expect(greetingForHour(12)).toBe('Good afternoon')
    expect(greetingForHour(18)).toBe('Good evening')
  })
})

describe('onboardingProgressLabel', () => {
  it('formats the compact progress string', () => {
    expect(onboardingProgressLabel(1, 3)).toBe('Set up DeliveryOS · 1 of 3 complete')
  })
})

describe('riderAvailabilityBreakdown', () => {
  it('buckets riders by real status only', () => {
    const riders = [
      { status: 'available' },
      { status: 'available' },
      { status: 'busy' },
      { status: 'offline' },
      { status: 'suspended' },
    ]
    expect(riderAvailabilityBreakdown(riders)).toEqual({ available: 2, busy: 1, offline: 1, suspended: 1 })
  })

  it('treats any unrecognized status as offline rather than dropping it', () => {
    expect(riderAvailabilityBreakdown([{ status: 'unknown' }])).toEqual({
      available: 0,
      busy: 0,
      offline: 1,
      suspended: 0,
    })
  })

  it('returns all-zero for an empty roster, not undefined', () => {
    expect(riderAvailabilityBreakdown([])).toEqual({ available: 0, busy: 0, offline: 0, suspended: 0 })
  })
})

describe('buildAttentionItems', () => {
  const now = new Date('2026-08-09T12:00:00Z')
  const baseInput = {
    deliveries: [],
    now,
    codAwaitingReconciliation: 0,
    smsCreditsRemaining: 100,
    riders: { available: 2, busy: 1, offline: 0, suspended: 0 },
    totalRiders: 3,
  }

  it('returns an empty list when everything is healthy — no padding to look busier', () => {
    expect(buildAttentionItems(baseInput)).toEqual([])
  })

  it('flags unassigned pending deliveries', () => {
    const items = buildAttentionItems({
      ...baseInput,
      deliveries: [{ status: 'pending', rider_id: null, created_at: now.toISOString() }],
    })
    expect(items.find((i) => i.key === 'unassigned')?.label).toContain('1 unassigned')
  })

  it('does not flag a pending delivery that already has a rider assigned', () => {
    const items = buildAttentionItems({
      ...baseInput,
      deliveries: [{ status: 'pending', rider_id: 'r1', created_at: now.toISOString() }],
    })
    expect(items.find((i) => i.key === 'unassigned')).toBeUndefined()
  })

  it('flags overdue pickups only past the disclosed threshold, not merely unassigned', () => {
    const justUnderThreshold = new Date(now.getTime() - (OVERDUE_PICKUP_MINUTES - 1) * 60_000).toISOString()
    const overThreshold = new Date(now.getTime() - (OVERDUE_PICKUP_MINUTES + 1) * 60_000).toISOString()

    const notOverdue = buildAttentionItems({
      ...baseInput,
      deliveries: [{ status: 'pending', rider_id: null, created_at: justUnderThreshold }],
    })
    expect(notOverdue.find((i) => i.key === 'overdue')).toBeUndefined()

    const overdue = buildAttentionItems({
      ...baseInput,
      deliveries: [{ status: 'pending', rider_id: null, created_at: overThreshold }],
    })
    expect(overdue.find((i) => i.key === 'overdue')?.label).toContain('1 overdue')
  })

  it('flags failed deliveries', () => {
    const items = buildAttentionItems({
      ...baseInput,
      deliveries: [{ status: 'failed', rider_id: 'r1', created_at: now.toISOString() }],
    })
    expect(items.find((i) => i.key === 'failed')).toBeDefined()
  })

  it('flags COD awaiting reconciliation using the real count passed in', () => {
    const items = buildAttentionItems({ ...baseInput, codAwaitingReconciliation: 4 })
    expect(items.find((i) => i.key === 'cod')?.label).toContain('4 COD')
  })

  it('flags out-of-credits as critical and low-credits as warning, never both at once', () => {
    const out = buildAttentionItems({ ...baseInput, smsCreditsRemaining: 0 })
    expect(out.find((i) => i.key === 'sms-out')?.severity).toBe('critical')
    expect(out.find((i) => i.key === 'sms-low')).toBeUndefined()

    const low = buildAttentionItems({ ...baseInput, smsCreditsRemaining: 5 })
    expect(low.find((i) => i.key === 'sms-low')?.severity).toBe('warning')
    expect(low.find((i) => i.key === 'sms-out')).toBeUndefined()
  })

  it('never flags SMS credits when the plan usage query has not resolved (null, not 0)', () => {
    const items = buildAttentionItems({ ...baseInput, smsCreditsRemaining: null })
    expect(items.find((i) => i.key.startsWith('sms'))).toBeUndefined()
  })

  it('flags no riders available only when the company actually has riders', () => {
    const noRidersAtAll = buildAttentionItems({
      ...baseInput,
      riders: { available: 0, busy: 0, offline: 0, suspended: 0 },
      totalRiders: 0,
    })
    expect(noRidersAtAll.find((i) => i.key === 'riders-offline')).toBeUndefined()

    const allOffline = buildAttentionItems({
      ...baseInput,
      riders: { available: 0, busy: 0, offline: 3, suspended: 0 },
      totalRiders: 3,
    })
    expect(allOffline.find((i) => i.key === 'riders-offline')).toBeDefined()
  })

  it('sorts critical items before warnings', () => {
    const items = buildAttentionItems({
      ...baseInput,
      deliveries: [
        { status: 'pending', rider_id: null, created_at: now.toISOString() }, // warning: unassigned
        { status: 'failed', rider_id: 'r1', created_at: now.toISOString() }, // critical: failed
      ],
    })
    expect(items[0].severity).toBe('critical')
  })
})

describe('latestDeliveryTimestamp', () => {
  it('prefers the most advanced real state-change timestamp', () => {
    expect(
      latestDeliveryTimestamp({
        created_at: '2026-08-01T00:00:00Z',
        assigned_at: '2026-08-01T01:00:00Z',
        picked_up_at: '2026-08-01T02:00:00Z',
        delivered_at: null,
      }),
    ).toBe('2026-08-01T02:00:00Z')
  })

  it('falls back to created_at when nothing else is set', () => {
    expect(latestDeliveryTimestamp({ created_at: '2026-08-01T00:00:00Z' })).toBe('2026-08-01T00:00:00Z')
  })
})

describe('formatElapsed', () => {
  const now = new Date('2026-08-09T12:00:00Z')

  it('shows "just now" under a minute', () => {
    expect(formatElapsed(new Date(now.getTime() - 30_000).toISOString(), now)).toBe('just now')
  })
  it('shows minutes under an hour', () => {
    expect(formatElapsed(new Date(now.getTime() - 5 * 60_000).toISOString(), now)).toBe('5m ago')
  })
  it('shows hours under a day', () => {
    expect(formatElapsed(new Date(now.getTime() - 3 * 3_600_000).toISOString(), now)).toBe('3h ago')
  })
  it('shows days beyond that', () => {
    expect(formatElapsed(new Date(now.getTime() - 2 * 86_400_000).toISOString(), now)).toBe('2d ago')
  })
})

describe('isFeatureGatedError / friendlyDashboardError', () => {
  it('detects the plan-tier gate error and gives an upgrade message, not a raw Postgres error', () => {
    const err = new Error('feature_not_available')
    expect(isFeatureGatedError(err)).toBe(true)
    expect(friendlyDashboardError(err)).toBe('This requires a plan upgrade.')
  })

  it('gives a generic safe message for any other error, never the raw text', () => {
    const err = new Error('relation "deliveries" does not exist')
    expect(isFeatureGatedError(err)).toBe(false)
    expect(friendlyDashboardError(err)).toBe('Could not load this right now.')
  })

  it('detects the gps_not_enabled plan-gate error distinctly from a generic feature gate', () => {
    const err = new Error('gps_not_enabled')
    expect(isGpsNotEnabledError(err)).toBe(true)
    expect(isFeatureGatedError(err)).toBe(false)
    expect(friendlyDashboardError(err)).toBe('Live GPS tracking is not included in your current plan.')
  })

  // Regression: this is the ACTUAL shape supabase.rpc(...) resolves `error`
  // as in this codebase's call convention (`const { data, error } = await
  // supabase.rpc(...); if (error) throw error`) — a plain JSON-parsed
  // object, not a PostgrestError/Error instance. Confirmed against the real
  // production response from list_company_rider_locations on Starter:
  // { code: 'P0001', details: null, hint: null, message: 'gps_not_enabled' }.
  it('detects gps_not_enabled from the real plain-object shape supabase-js actually throws, not just an Error instance', () => {
    const err = { code: 'P0001', details: null, hint: null, message: 'gps_not_enabled' }
    expect(isGpsNotEnabledError(err)).toBe(true)
    expect(friendlyDashboardError(err)).toBe('Live GPS tracking is not included in your current plan.')
  })

  it('detects feature_not_available from the same real plain-object shape', () => {
    const err = { code: 'P0001', details: null, hint: null, message: 'feature_not_available' }
    expect(isFeatureGatedError(err)).toBe(true)
    expect(friendlyDashboardError(err)).toBe('This requires a plan upgrade.')
  })

  it('does not overmatch a plain-object error whose message merely mentions the phrase', () => {
    const err = { code: 'P0001', details: null, hint: null, message: 'gps_not_enabled_for_reasons' }
    expect(isGpsNotEnabledError(err)).toBe(false)
  })

  it('recovers the message from a JSON-stringified PostgrestError-shaped string', () => {
    const err = JSON.stringify({ code: 'P0001', details: null, hint: null, message: 'gps_not_enabled' })
    expect(isGpsNotEnabledError(err)).toBe(true)
  })

  it('ignores an object with no string message rather than throwing', () => {
    expect(isGpsNotEnabledError({ code: 'P0001' })).toBe(false)
    expect(isGpsNotEnabledError(null)).toBe(false)
    expect(isGpsNotEnabledError(undefined)).toBe(false)
    expect(isGpsNotEnabledError(42)).toBe(false)
  })
})
