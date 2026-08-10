import { Link } from 'react-router-dom'
import { UserPlus, Users } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import type { RiderAvailability } from '@/lib/dashboard-metrics'

const ROWS: Array<{ key: keyof RiderAvailability; label: string; dot: string }> = [
  { key: 'available', label: 'Available', dot: 'bg-emerald-500' },
  { key: 'busy', label: 'Busy', dot: 'bg-amber-500' },
  { key: 'offline', label: 'Offline', dot: 'bg-zinc-400' },
]

export function RiderAvailabilityCard({ breakdown, total }: { breakdown: RiderAvailability; total: number }) {
  return (
    <Card>
      <CardHeader className="flex-row items-center justify-between pb-2">
        <CardTitle className="text-base">Rider availability</CardTitle>
        <Link to="/riders" className="text-xs font-medium text-[var(--color-primary)] hover:underline">
          Manage riders
        </Link>
      </CardHeader>
      <CardContent>
        {total === 0 ? (
          <div className="flex flex-col items-center justify-center gap-2 py-4 text-center">
            <span className="flex h-9 w-9 items-center justify-center rounded-full bg-zinc-100 text-[var(--color-muted)]">
              <Users className="h-4 w-4" aria-hidden />
            </span>
            <p className="text-sm font-medium text-[var(--color-foreground)]">No riders added yet</p>
            <Link
              to="/riders"
              className="mt-0.5 inline-flex items-center gap-1 rounded-lg border px-3 py-1.5 text-xs font-medium text-[var(--color-foreground)] transition-colors hover:bg-zinc-50"
            >
              <UserPlus className="h-3.5 w-3.5" aria-hidden />
              Add a rider
            </Link>
          </div>
        ) : (
          <div className="space-y-2.5">
            {ROWS.map((row) => {
              const value = breakdown[row.key]
              const pct = total > 0 ? Math.round((value / total) * 100) : 0
              return (
                <div key={row.key}>
                  <div className="flex items-center justify-between text-sm">
                    <span className="flex items-center gap-2 text-[var(--color-foreground)]">
                      <span className={`h-2 w-2 rounded-full ${row.dot}`} aria-hidden />
                      {row.label}
                    </span>
                    <span className="font-medium tabular-nums">{value}</span>
                  </div>
                  <div className="mt-1 h-1.5 w-full overflow-hidden rounded-full bg-zinc-100">
                    <div className={`h-full rounded-full ${row.dot}`} style={{ width: `${pct}%` }} />
                  </div>
                </div>
              )
            })}
            <p className="pt-1 text-xs text-[var(--color-muted)]">{total} riders total</p>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
