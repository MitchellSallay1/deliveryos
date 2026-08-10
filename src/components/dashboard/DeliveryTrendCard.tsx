import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/Card'
import { Skeleton } from '@/components/ui/Skeleton'
import { WidgetError } from '@/components/dashboard/WidgetError'
import { friendlyDashboardError } from '@/lib/dashboard-metrics'
import { useCompanyDeliveryTrend } from '@/hooks/use-reports'

const DAY_LABELS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']

export function DeliveryTrendCard({ companyId }: { companyId: string }) {
  const { data: days, isLoading, error, refetch } = useCompanyDeliveryTrend(companyId, 7)

  const max = Math.max(1, ...((days ?? []).map((d) => d.total)))
  const totalThisWeek = (days ?? []).reduce((sum, d) => sum + d.total, 0)

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base">Delivery volume — last 7 days</CardTitle>
        {!isLoading && !error && <CardDescription>{totalThisWeek} deliveries this week</CardDescription>}
      </CardHeader>
      <CardContent>
        {isLoading && <Skeleton className="h-32 w-full" />}
        {error && <WidgetError message={friendlyDashboardError(error)} onRetry={() => void refetch()} />}
        {!isLoading && !error && (
          <div className="flex h-32 items-end gap-2">
            {(days ?? []).map((d) => {
              const heightPct = Math.max(4, (d.total / max) * 100)
              const dow = new Date(`${d.date}T00:00:00Z`).getUTCDay()
              return (
                <div key={d.date} className="flex flex-1 flex-col items-center gap-1.5">
                  <div className="flex h-24 w-full items-end overflow-hidden rounded-t-md bg-zinc-100">
                    <div
                      className="w-full rounded-t-md bg-[var(--color-accent)] transition-all"
                      style={{ height: `${heightPct}%` }}
                      title={`${d.total} deliveries, ${d.completed} completed, ${d.failed} failed`}
                    />
                  </div>
                  <span className="text-[10px] font-medium text-[var(--color-muted)]">{DAY_LABELS[dow]}</span>
                </div>
              )
            })}
          </div>
        )}
      </CardContent>
    </Card>
  )
}
