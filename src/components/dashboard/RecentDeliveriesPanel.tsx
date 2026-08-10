import { Link } from 'react-router-dom'
import { Package, Plus } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/Card'
import { StatusBadge } from '@/components/ui/StatusBadge'
import { WidgetError } from '@/components/dashboard/WidgetError'
import { formatElapsed, friendlyDashboardError, latestDeliveryTimestamp } from '@/lib/dashboard-metrics'
import type { DeliveryRow } from '@/types/supabase'

export function RecentDeliveriesPanel({
  deliveries,
  riderNameById,
  isLoading,
  error,
  onRetry,
}: {
  deliveries: DeliveryRow[]
  riderNameById: Map<string, string>
  isLoading: boolean
  error: unknown
  onRetry: () => void
}) {
  return (
    <Card>
      <CardHeader className="flex-row items-center justify-between pb-2">
        <div>
          <CardTitle className="text-base">Recent deliveries</CardTitle>
          <CardDescription>Latest activity across your workspace</CardDescription>
        </div>
        <Link to="/deliveries" className="shrink-0 text-xs font-medium text-[var(--color-primary)] hover:underline">
          View all
        </Link>
      </CardHeader>
      <CardContent className="space-y-1.5">
        {isLoading && <p className="py-6 text-center text-sm text-[var(--color-muted)]">Loading…</p>}
        {Boolean(error) && <WidgetError message={friendlyDashboardError(error)} onRetry={onRetry} />}
        {!isLoading &&
          !error &&
          deliveries.map((d) => (
            <Link
              key={d.id}
              to={`/deliveries?open=${d.id}`}
              className="flex items-center justify-between gap-3 rounded-lg border px-3 py-2.5 text-sm transition-colors hover:bg-zinc-50"
            >
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <span className="truncate font-medium text-[var(--color-foreground)]">{d.customer_name}</span>
                  <span className="shrink-0 font-mono text-[10px] text-[var(--color-muted)]">{d.tracking_code}</span>
                </div>
                <p className="mt-0.5 truncate text-xs text-[var(--color-muted)]">
                  → {d.destination_address}
                  {d.rider_id && riderNameById.get(d.rider_id) ? ` · ${riderNameById.get(d.rider_id)}` : ''}
                </p>
              </div>
              <div className="shrink-0 text-right">
                <StatusBadge status={d.status} />
                <p className="mt-1 text-[10px] text-[var(--color-muted)]">{formatElapsed(latestDeliveryTimestamp(d))}</p>
              </div>
            </Link>
          ))}
        {!isLoading && !error && deliveries.length === 0 && (
          <div className="flex flex-col items-center justify-center gap-2 py-6 text-center">
            <span className="flex h-9 w-9 items-center justify-center rounded-full bg-zinc-100 text-[var(--color-muted)]">
              <Package className="h-4 w-4" aria-hidden />
            </span>
            <p className="text-sm font-medium text-[var(--color-foreground)]">No deliveries yet</p>
            <p className="max-w-[220px] text-xs text-[var(--color-muted)]">
              Deliveries you create will show up here as they move.
            </p>
            <Link
              to="/deliveries"
              className="mt-0.5 inline-flex items-center gap-1 rounded-lg border px-3 py-1.5 text-xs font-medium text-[var(--color-foreground)] transition-colors hover:bg-zinc-50"
            >
              <Plus className="h-3.5 w-3.5" aria-hidden />
              Create delivery
            </Link>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
