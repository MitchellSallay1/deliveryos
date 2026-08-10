import { describe, expect, it } from 'vitest'
import {
  ALERT_GROUP_LABELS,
  MTN_READINESS_ITEMS,
  alertGroupKey,
  clampSearchIndex,
  compareHint,
  formatLrd,
  formatPercent,
  groupAlertsBySeverity,
  healthStateColor,
  healthStateFrom,
  overallPlatformStatus,
  statusColorFor,
  superAdminRouteDecision,
  trialConversionRate,
  type PlatformAlert,
} from '@/lib/admin-control-tower'

describe('alertGroupKey', () => {
  it('maps backend severities to the three UI groups', () => {
    expect(alertGroupKey('critical')).toBe('critical')
    expect(alertGroupKey('high')).toBe('warning')
    expect(alertGroupKey('medium')).toBe('warning')
    expect(alertGroupKey('low')).toBe('informational')
  })

  it('defaults unknown severities to informational instead of dropping them', () => {
    expect(alertGroupKey('whatever')).toBe('informational')
  })
})

describe('groupAlertsBySeverity', () => {
  it('buckets alerts and preserves every entry', () => {
    const alerts: PlatformAlert[] = [
      { severity: 'critical', title: 'a', detail: '', href: '' },
      { severity: 'high', title: 'b', detail: '', href: '' },
      { severity: 'low', title: 'c', detail: '', href: '' },
    ]
    const grouped = groupAlertsBySeverity(alerts)
    expect(grouped.critical).toHaveLength(1)
    expect(grouped.warning).toHaveLength(1)
    expect(grouped.informational).toHaveLength(1)
    expect(Object.keys(ALERT_GROUP_LABELS)).toEqual(['critical', 'warning', 'informational'])
  })

  it('returns empty groups (not undefined) when there are no alerts', () => {
    const grouped = groupAlertsBySeverity([])
    expect(grouped.critical).toEqual([])
    expect(grouped.warning).toEqual([])
    expect(grouped.informational).toEqual([])
  })
})

describe('statusColorFor', () => {
  it('maps known-good states to green', () => {
    expect(statusColorFor('healthy')).toBe('green')
    expect(statusColorFor('active')).toBe('green')
  })

  it('maps known-bad states to red', () => {
    expect(statusColorFor('down')).toBe('red')
    expect(statusColorFor('suspended')).toBe('red')
  })

  it('maps caution states to amber', () => {
    expect(statusColorFor('degraded')).toBe('amber')
    expect(statusColorFor('past_due')).toBe('amber')
  })

  it('never invents a color for unrecognized/missing status — falls back to gray', () => {
    expect(statusColorFor('not_configured')).toBe('gray')
    expect(statusColorFor(undefined)).toBe('gray')
    expect(statusColorFor(null)).toBe('gray')
  })
})

describe('healthStateFrom / healthStateColor', () => {
  it('treats not-configured as distinct from down', () => {
    expect(healthStateFrom(undefined)).toBe('not_configured')
    expect(healthStateFrom('down')).toBe('down')
    expect(healthStateColor('not_configured')).toBe('gray')
    expect(healthStateColor('down')).toBe('red')
  })

  it('maps healthy/operational to green and degraded to amber', () => {
    expect(healthStateFrom('healthy')).toBe('operational')
    expect(healthStateColor('operational')).toBe('green')
    expect(healthStateFrom('degraded')).toBe('degraded')
    expect(healthStateColor('degraded')).toBe('amber')
  })
})

describe('MTN readiness — no secret exposure', () => {
  it('exposes only static "awaiting" language, never a credential-shaped value', () => {
    expect(MTN_READINESS_ITEMS).toHaveLength(4)
    for (const item of MTN_READINESS_ITEMS) {
      expect(item.status).toMatch(/^Awaiting/)
      // Guard against ever wiring a real secret/token into this list: no
      // long opaque alphanumeric runs, which is what API keys look like.
      expect(item.status).not.toMatch(/[A-Za-z0-9]{20,}/)
      expect(item.label).not.toMatch(/[A-Za-z0-9]{20,}/)
    }
  })

  it('never claims MTN integrations are live', () => {
    const joined = MTN_READINESS_ITEMS.map((i) => i.status).join(' ').toLowerCase()
    expect(joined).not.toContain('live')
    expect(joined).not.toContain('connected')
    expect(joined).not.toContain('active')
  })
})

describe('trialConversionRate', () => {
  it('computes a rate when there is a denominator', () => {
    expect(trialConversionRate(5, 5)).toBe(0.5)
  })

  it('returns null (not 0) when there is no data — avoids a misleading 0%', () => {
    expect(trialConversionRate(0, 0)).toBeNull()
  })
})

describe('formatPercent', () => {
  it('renders an em dash for null instead of fabricating a number', () => {
    expect(formatPercent(null)).toBe('—')
  })

  it('formats a rate to one decimal percent', () => {
    expect(formatPercent(0.5)).toBe('50%')
    expect(formatPercent(0.333)).toBe('33.3%')
  })
})

describe('compareHint', () => {
  it('does not fabricate a trend with no prior-day baseline', () => {
    expect(compareHint(0, 0)).toBeUndefined()
    expect(compareHint(5, 0)).toBe('New activity today')
  })

  it('computes a real day-over-day percentage', () => {
    expect(compareHint(10, 5)).toMatch(/\+100%/)
  })
})

describe('overallPlatformStatus', () => {
  it('is green with no alerts', () => {
    expect(overallPlatformStatus([]).color).toBe('green')
  })

  it('is amber when only warning-tier alerts exist', () => {
    const alerts: PlatformAlert[] = [{ severity: 'high', title: 'x', detail: '', href: '' }]
    expect(overallPlatformStatus(alerts).color).toBe('amber')
  })

  it('is red when any critical alert exists, even alongside others', () => {
    const alerts: PlatformAlert[] = [
      { severity: 'low', title: 'a', detail: '', href: '' },
      { severity: 'critical', title: 'b', detail: '', href: '' },
    ]
    expect(overallPlatformStatus(alerts).color).toBe('red')
  })
})

describe('clampSearchIndex', () => {
  it('never goes negative or past the last result', () => {
    expect(clampSearchIndex(0, 'up', 5)).toBe(0)
    expect(clampSearchIndex(4, 'down', 5)).toBe(4)
  })

  it('moves by one within bounds', () => {
    expect(clampSearchIndex(1, 'down', 5)).toBe(2)
    expect(clampSearchIndex(1, 'up', 5)).toBe(0)
  })

  it('is always 0 for an empty result set', () => {
    expect(clampSearchIndex(3, 'down', 0)).toBe(0)
    expect(clampSearchIndex(3, 'up', 0)).toBe(0)
  })
})

describe('superAdminRouteDecision', () => {
  it('shows loading while auth or context is resolving', () => {
    expect(
      superAdminRouteDecision({ loading: true, contextLoading: false, isAuthenticated: false, activeRole: null }),
    ).toBe('loading')
    expect(
      superAdminRouteDecision({ loading: false, contextLoading: true, isAuthenticated: true, activeRole: 'super_admin' }),
    ).toBe('loading')
  })

  it('redirects unauthenticated users to login', () => {
    expect(
      superAdminRouteDecision({ loading: false, contextLoading: false, isAuthenticated: false, activeRole: null }),
    ).toBe('redirect-login')
  })

  it('redirects authenticated non-super-admins to the tenant dashboard, never allowing through', () => {
    expect(
      superAdminRouteDecision({
        loading: false,
        contextLoading: false,
        isAuthenticated: true,
        activeRole: 'company_owner',
      }),
    ).toBe('redirect-dashboard')
  })

  it('allows only authenticated super_admin through', () => {
    expect(
      superAdminRouteDecision({
        loading: false,
        contextLoading: false,
        isAuthenticated: true,
        activeRole: 'super_admin',
      }),
    ).toBe('allow')
  })
})

describe('formatLrd', () => {
  it('formats cents to LRD with thousands separators', () => {
    expect(formatLrd(250000)).toContain('2,500')
  })

  it('handles zero/undefined without throwing', () => {
    expect(formatLrd(0)).toBe('LRD 0')
    expect(formatLrd(undefined)).toBe('LRD 0')
  })
})
