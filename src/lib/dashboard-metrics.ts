/**
 * Pure, testable presentation/transformation logic for the tenant Operations
 * Dashboard. No fetching here — these functions only shape data already
 * returned by existing hooks/RPCs. Keeping this pure means the dashboard's
 * derived KPIs (pending pickups, attention items, elapsed time, etc.) are
 * unit-testable without mocking Supabase, and — critically — never invent a
 * number that isn't backed by a real field passed in.
 */

export function greetingForHour(hour: number): 'Good morning' | 'Good afternoon' | 'Good evening' {
  if (hour < 12) return 'Good morning'
  if (hour < 18) return 'Good afternoon'
  return 'Good evening'
}

export function onboardingProgressLabel(completed: number, total: number): string {
  return `Set up DeliveryOS · ${completed} of ${total} complete`
}

export type RiderAvailability = { available: number; busy: number; offline: number; suspended: number }

/** Buckets riders by real `status` only — never infers availability from anything else. */
export function riderAvailabilityBreakdown(riders: Array<{ status: string }>): RiderAvailability {
  const out: RiderAvailability = { available: 0, busy: 0, offline: 0, suspended: 0 }
  for (const r of riders) {
    if (r.status === 'available') out.available += 1
    else if (r.status === 'busy') out.busy += 1
    else if (r.status === 'suspended') out.suspended += 1
    else out.offline += 1
  }
  return out
}

/** Minutes an unassigned pending delivery must be waiting before it's flagged as overdue. Disclosed in the UI copy, not a hidden magic number. */
export const OVERDUE_PICKUP_MINUTES = 45

export type AttentionSeverity = 'critical' | 'warning'

export type AttentionItem = {
  key: string
  severity: AttentionSeverity
  label: string
  detail: string
  href: string
}

type AttentionDeliveryInput = {
  status: string
  rider_id: string | null
  created_at: string
}

/**
 * Builds the dashboard's "needs attention" list from real, already-fetched
 * data only. Returns [] (rendered as "Everything looks good") when nothing
 * qualifies — never pads the list to look busier than the workspace is.
 */
export function buildAttentionItems(input: {
  deliveries: AttentionDeliveryInput[]
  now: Date
  codAwaitingReconciliation: number
  smsCreditsRemaining: number | null
  riders: RiderAvailability
  totalRiders: number
}): AttentionItem[] {
  const items: AttentionItem[] = []

  const unassigned = input.deliveries.filter((d) => d.status === 'pending' && !d.rider_id)
  if (unassigned.length > 0) {
    items.push({
      key: 'unassigned',
      severity: 'warning',
      label: `${unassigned.length} unassigned ${unassigned.length === 1 ? 'delivery' : 'deliveries'}`,
      detail: 'Waiting for a rider to be assigned.',
      href: '/deliveries',
    })
  }

  const overdue = unassigned.filter(
    (d) => input.now.getTime() - new Date(d.created_at).getTime() > OVERDUE_PICKUP_MINUTES * 60_000,
  )
  if (overdue.length > 0) {
    items.push({
      key: 'overdue',
      severity: 'critical',
      label: `${overdue.length} overdue ${overdue.length === 1 ? 'pickup' : 'pickups'}`,
      detail: `Pending assignment for over ${OVERDUE_PICKUP_MINUTES} minutes.`,
      href: '/deliveries',
    })
  }

  const failed = input.deliveries.filter((d) => d.status === 'failed')
  if (failed.length > 0) {
    items.push({
      key: 'failed',
      severity: 'critical',
      label: `${failed.length} failed ${failed.length === 1 ? 'delivery' : 'deliveries'}`,
      detail: 'Review the failure reason and decide next steps.',
      href: '/deliveries',
    })
  }

  if (input.codAwaitingReconciliation > 0) {
    items.push({
      key: 'cod',
      severity: 'warning',
      label: `${input.codAwaitingReconciliation} COD ${input.codAwaitingReconciliation === 1 ? 'payment' : 'payments'} awaiting reconciliation`,
      detail: 'Collected from customers, not yet deposited.',
      href: '/settings',
    })
  }

  if (input.smsCreditsRemaining !== null && input.smsCreditsRemaining <= 0) {
    items.push({
      key: 'sms-out',
      severity: 'critical',
      label: 'Out of SMS credits',
      detail: 'Rider job notifications may not be delivered.',
      href: '/billing',
    })
  } else if (input.smsCreditsRemaining !== null && input.smsCreditsRemaining < 10) {
    items.push({
      key: 'sms-low',
      severity: 'warning',
      label: 'SMS credits running low',
      detail: `${input.smsCreditsRemaining} credits remaining.`,
      href: '/billing',
    })
  }

  if (input.totalRiders > 0 && input.riders.available === 0 && input.riders.busy === 0) {
    items.push({
      key: 'riders-offline',
      severity: 'warning',
      label: 'No riders currently available',
      detail: 'All riders are offline or suspended.',
      href: '/riders',
    })
  }

  const rank: Record<AttentionSeverity, number> = { critical: 0, warning: 1 }
  return [...items].sort((a, b) => rank[a.severity] - rank[b.severity])
}

type ElapsedTimestamps = {
  delivered_at?: string | null
  failed_at?: string | null
  cancelled_at?: string | null
  in_transit_at?: string | null
  picked_up_at?: string | null
  accepted_at?: string | null
  assigned_at?: string | null
  created_at: string
}

/** The most recent real state-change timestamp for a delivery — never fabricated, just the latest non-null one available. */
export function latestDeliveryTimestamp(d: ElapsedTimestamps): string {
  return (
    d.delivered_at ??
    d.failed_at ??
    d.cancelled_at ??
    d.in_transit_at ??
    d.picked_up_at ??
    d.accepted_at ??
    d.assigned_at ??
    d.created_at
  )
}

export function formatElapsed(isoDate: string, now: Date = new Date()): string {
  const diffMs = now.getTime() - new Date(isoDate).getTime()
  if (diffMs < 60_000) return 'just now'
  const minutes = Math.floor(diffMs / 60_000)
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h ago`
  const days = Math.floor(hours / 24)
  return `${days}d ago`
}

/**
 * Extracts a plain-text message from whatever shape an error actually
 * arrives in. This matters because the two RPC call sites feeding this
 * module (`fetchWorkspaceReport`, `fetchCompanyRiderLocations`, etc.) do
 * `const { data, error } = await supabase.rpc(...); if (error) throw error`
 * — the default (non-`throwOnError`) supabase-js/postgrest-js path, which
 * resolves `error` as a **plain JSON-parsed object**
 * (`{ code, details, hint, message }`, from `PostgrestBuilder.processResponse`
 * — `error = JSON.parse(body)`), not a `PostgrestError`/`Error` instance.
 * `PostgrestError` (which does extend `Error`) is only constructed on the
 * `throwOnError()` builder path, which this codebase doesn't use. A check
 * that only handled `instanceof Error` therefore silently matched nothing
 * for every real RPC failure and always fell through to the generic
 * message — this was the actual bug, not the detector strings themselves.
 */
function errorMessage(error: unknown): string {
  if (error instanceof Error) return error.message
  if (typeof error === 'string') {
    const trimmed = error.trim()
    if (trimmed.startsWith('{')) {
      // Defensive: a caller may have JSON.stringified a PostgrestError-shaped
      // object into a plain string instead of throwing the object itself.
      try {
        const parsed: unknown = JSON.parse(trimmed)
        if (parsed && typeof parsed === 'object' && typeof (parsed as { message?: unknown }).message === 'string') {
          return (parsed as { message: string }).message
        }
      } catch {
        // Not JSON — fall through and treat the raw string as the message.
      }
    }
    return error
  }
  if (error && typeof error === 'object' && 'message' in error) {
    const message = (error as { message?: unknown }).message
    if (typeof message === 'string') return message
  }
  return ''
}

/**
 * Detects the specific Postgres RAISE EXCEPTION used by report RPCs to
 * signal a plan-tier gate. Exact match, not a substring check — RAISE
 * EXCEPTION 'feature_not_available' sets the message to exactly that
 * literal with no prefix/suffix, and exact matching avoids ever
 * overmatching an unrelated error that merely mentions the phrase.
 */
export function isFeatureGatedError(error: unknown): boolean {
  return errorMessage(error).trim() === 'feature_not_available'
}

/** Detects the specific `gps_not_enabled` exception `list_company_rider_locations` raises when the company's plan doesn't include GPS tracking (Enterprise-only today) — a known, predictable state, not an unexpected failure. Exact match for the same overmatching-avoidance reason as isFeatureGatedError. */
export function isGpsNotEnabledError(error: unknown): boolean {
  return errorMessage(error).trim() === 'gps_not_enabled'
}

/** User-safe message for any dashboard widget failure — never surfaces raw Postgres/network error text. */
export function friendlyDashboardError(error: unknown): string {
  if (isFeatureGatedError(error)) return 'This requires a plan upgrade.'
  if (isGpsNotEnabledError(error)) return 'Live GPS tracking is not included in your current plan.'
  return 'Could not load this right now.'
}
