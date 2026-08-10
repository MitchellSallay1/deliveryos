/**
 * Pure, unit-testable logic for the Super Admin Control Tower.
 * No fetching here — these functions only shape data already returned by
 * existing RPCs (get_platform_alerts, get_platform_health_snapshot, etc.)
 * for presentation. Keeping this pure makes severity grouping, status
 * mapping, and MTN readiness labeling independently testable without
 * mocking Supabase.
 */

export type PlatformAlert = {
  severity: string
  title: string
  detail: string
  href: string
  entity?: string
  suggested_action?: string
}

export type AlertGroupKey = 'critical' | 'warning' | 'informational'

const SEVERITY_TO_GROUP: Record<string, AlertGroupKey> = {
  critical: 'critical',
  high: 'warning',
  medium: 'warning',
  low: 'informational',
  info: 'informational',
}

export const ALERT_GROUP_LABELS: Record<AlertGroupKey, string> = {
  critical: 'Critical',
  warning: 'Warning',
  informational: 'Informational',
}

export const ALERT_GROUP_ORDER: AlertGroupKey[] = ['critical', 'warning', 'informational']

/** Maps a backend alert severity string to one of the three UI groups. Unknown severities default to informational rather than being silently dropped. */
export function alertGroupKey(severity: string): AlertGroupKey {
  return SEVERITY_TO_GROUP[severity] ?? 'informational'
}

export function groupAlertsBySeverity(alerts: PlatformAlert[]): Record<AlertGroupKey, PlatformAlert[]> {
  const groups: Record<AlertGroupKey, PlatformAlert[]> = { critical: [], warning: [], informational: [] }
  for (const a of alerts) {
    groups[alertGroupKey(a.severity)].push(a)
  }
  return groups
}

/** Explicit green/amber/red/gray semantics — the only four states the UI ever renders. */
export type StatusColor = 'green' | 'amber' | 'red' | 'gray'

const GREEN = new Set(['healthy', 'operational', 'active', 'available', 'online', 'ok'])
const AMBER = new Set(['degraded', 'needs_attention', 'past_due', 'pending', 'trialing'])
const RED = new Set(['down', 'at_risk', 'unavailable', 'failed', 'suspended', 'dead', 'offline'])

export function statusColorFor(status: string | null | undefined): StatusColor {
  const s = (status ?? '').toLowerCase()
  if (GREEN.has(s)) return 'green'
  if (AMBER.has(s)) return 'amber'
  if (RED.has(s)) return 'red'
  return 'gray'
}

export const STATUS_COLOR_CLASSES: Record<StatusColor, { dot: string; text: string; bg: string; ring: string }> = {
  green: { dot: 'bg-emerald-400', text: 'text-emerald-300', bg: 'bg-emerald-400/10', ring: 'ring-emerald-400/20' },
  amber: { dot: 'bg-amber-400', text: 'text-amber-300', bg: 'bg-amber-400/10', ring: 'ring-amber-400/20' },
  red: { dot: 'bg-red-400', text: 'text-red-300', bg: 'bg-red-400/10', ring: 'ring-red-400/20' },
  gray: { dot: 'bg-zinc-500', text: 'text-zinc-400', bg: 'bg-zinc-500/10', ring: 'ring-zinc-500/20' },
}

/**
 * Platform health only ever reports one of these four words, never an
 * invented SLA/uptime number. "not_configured" is a distinct, non-alarming
 * state from "down" — an integration nobody has wired up yet is not an
 * outage.
 */
export type HealthState = 'operational' | 'degraded' | 'down' | 'not_configured'

export function healthStateFrom(rawStatus: string | null | undefined): HealthState {
  switch (rawStatus) {
    case 'healthy':
    case 'operational':
      return 'operational'
    case 'degraded':
      return 'degraded'
    case 'down':
    case 'unavailable':
      return 'down'
    default:
      return 'not_configured'
  }
}

export const HEALTH_STATE_LABEL: Record<HealthState, string> = {
  operational: 'Operational',
  degraded: 'Degraded',
  down: 'Down',
  not_configured: 'Not configured',
}

export function healthStateColor(state: HealthState): StatusColor {
  switch (state) {
    case 'operational':
      return 'green'
    case 'degraded':
      return 'amber'
    case 'down':
      return 'red'
    case 'not_configured':
      return 'gray'
  }
}

/**
 * MTN readiness is always a static, honest label — never a live probe of a
 * secret or credential. These strings are the entire contract; there is no
 * data path that could leak a secret value through this surface.
 */
export type MtnReadinessKey = 'sms_api' | 'otp' | 'ussd' | 'momo'

export const MTN_READINESS_ITEMS: Array<{ key: MtnReadinessKey; label: string; status: string }> = [
  { key: 'sms_api', label: 'SMS API', status: 'Awaiting credentials' },
  { key: 'otp', label: 'OTP', status: 'Awaiting provider setup' },
  { key: 'ussd', label: 'USSD', status: 'Awaiting integration' },
  { key: 'momo', label: 'MoMo', status: 'Awaiting API details' },
]

/** Derived trial-to-paid conversion — null (not 0%) when there is no denominator, so the UI can render "—" instead of a misleading number. */
export function trialConversionRate(trialing: number, activatedActive: number): number | null {
  const denom = trialing + activatedActive
  if (denom <= 0) return null
  return activatedActive / denom
}

export function formatPercent(rate: number | null): string {
  if (rate === null) return '—'
  return `${Math.round(rate * 1000) / 10}%`
}

/** Bounded day-over-day comparison — never fabricates a trend when there's no prior-day baseline. */
export function compareHint(today: number, yesterday: number): string | undefined {
  if (yesterday === 0) return today > 0 ? 'New activity today' : undefined
  const pct = Math.round(((today - yesterday) / yesterday) * 100)
  if (pct === 0) return 'Same as yesterday'
  return `${pct > 0 ? '+' : ''}${pct}% vs yesterday`
}

export function formatLrd(cents: number | null | undefined): string {
  if (!cents) return 'LRD 0'
  return `LRD ${(cents / 100).toLocaleString(undefined, { maximumFractionDigits: 0 })}`
}

/** Clamped arrow-key navigation index for the global search command palette — never goes out of bounds, even for an empty result set. */
export function clampSearchIndex(current: number, direction: 'up' | 'down', resultCount: number): number {
  if (resultCount <= 0) return 0
  if (direction === 'down') return Math.min(current + 1, resultCount - 1)
  return Math.max(current - 1, 0)
}

export type SuperAdminRouteDecision = 'loading' | 'redirect-login' | 'redirect-dashboard' | 'allow'

/** Pure routing decision for SuperAdminRoute — kept separate from the component so the guard logic is unit-testable without rendering. */
export function superAdminRouteDecision(params: {
  loading: boolean
  contextLoading: boolean
  isAuthenticated: boolean
  activeRole: string | null | undefined
}): SuperAdminRouteDecision {
  if (params.loading || params.contextLoading) return 'loading'
  if (!params.isAuthenticated) return 'redirect-login'
  if (params.activeRole !== 'super_admin') return 'redirect-dashboard'
  return 'allow'
}

/**
 * Single overall platform status rollup for the top of the command center:
 * any critical alert makes the whole platform red; any warning-tier alert
 * makes it amber; otherwise green. This intentionally only looks at real
 * alert evidence — it never averages/guesses a score.
 */
export function overallPlatformStatus(alerts: PlatformAlert[]): { color: StatusColor; label: string } {
  const groups = groupAlertsBySeverity(alerts)
  if (groups.critical.length > 0) return { color: 'red', label: 'Critical issues detected' }
  if (groups.warning.length > 0) return { color: 'amber', label: 'Needs attention' }
  return { color: 'green', label: 'All systems normal' }
}

/**
 * Canonical platform user lifecycle states, matching
 * admin_list_platform_users/admin_platform_user_funnel's server-side
 * derivation exactly (unverified / verified_incomplete / active /
 * super_admin) — the frontend never re-derives this from raw fields, only
 * labels the status the RPC already computed.
 */
export type PlatformUserLifecycleStatus = 'unverified' | 'verified_incomplete' | 'active' | 'super_admin'

export const PLATFORM_USER_LIFECYCLE_OPTIONS: Array<{ value: PlatformUserLifecycleStatus; label: string }> = [
  { value: 'unverified', label: 'Unverified' },
  { value: 'verified_incomplete', label: 'Verified — Setup incomplete' },
  { value: 'active', label: 'Active' },
  { value: 'super_admin', label: 'Super Admin' },
]

/** Badge color/label for a platform user's lifecycle status. Unrecognized values fall back to a neutral gray "Unknown" rather than throwing. */
export function platformUserLifecycleBadge(status: string): { label: string; color: StatusColor } {
  switch (status) {
    case 'unverified':
      return { label: 'Unverified', color: 'gray' }
    case 'verified_incomplete':
      return { label: 'Verified — Setup incomplete', color: 'amber' }
    case 'active':
      return { label: 'Active', color: 'green' }
    case 'super_admin':
      return { label: 'Super Admin', color: 'amber' }
    default:
      return { label: 'Unknown', color: 'gray' }
  }
}
