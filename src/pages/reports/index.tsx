import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { useAuth } from '@/hooks/use-auth'
import { useOperationalAnalytics, useRiderPerformance } from '@/hooks/use-field-ops'
import { getProfitability } from '@/services/operations-service'
import { useWorkspaceReport } from '@/hooks/use-reports'
import type { ReportPeriod } from '@/types/reports'
import { formatLrdFromCents } from '@/utils/delivery-schemas'
import { parseSupabaseError } from '@/lib/supabase-errors'

const PERIOD_LABELS: Record<ReportPeriod, string> = {
  day: 'Today',
  week: 'This week',
  month: 'This month',
}

export function ReportsPage() {
  const { context } = useAuth()
  const companyId = context?.activeCompanyId ?? null
  const [period, setPeriod] = useState<ReportPeriod>('day')

  const { data, isLoading, error, isFetching } = useWorkspaceReport(companyId, period)
  const { data: ops } = useOperationalAnalytics(companyId, period === 'day' ? 7 : period === 'week' ? 30 : 90)
  const { data: riderPerf } = useRiderPerformance(companyId, 30)
  const { data: profitability } = useQuery({
    queryKey: ['profitability', companyId],
    queryFn: () => getProfitability(companyId!, null, 30),
    enabled: !!companyId,
  })
  const summary = data?.summary
  const opsSummary = (ops as { summary?: Record<string, unknown> })?.summary

  if (!companyId) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Reports</CardTitle>
          <CardDescription>Join a company workspace to view analytics.</CardDescription>
        </CardHeader>
      </Card>
    )
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="text-xl font-semibold">Reports</h2>
          <p className="text-sm text-[var(--color-muted)]">
            Africa/Monrovia · aggregated via <code className="text-xs">get_workspace_report</code>
          </p>
        </div>
        <div className="flex gap-1">
          {(Object.keys(PERIOD_LABELS) as ReportPeriod[]).map((p) => (
            <Button
              key={p}
              type="button"
              size="sm"
              variant={period === p ? 'default' : 'outline'}
              onClick={() => setPeriod(p)}
            >
              {PERIOD_LABELS[p]}
            </Button>
          ))}
        </div>
      </div>

      {error && <p className="text-sm text-red-600">{parseSupabaseError(error)}</p>}

      {(isLoading || isFetching) && !summary && (
        <p className="text-sm text-[var(--color-muted)]">Loading…</p>
      )}

      {summary && (
        <>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
            <Metric label="Deliveries" value={String(summary.total)} />
            <Metric label="Completed" value={String(summary.completed)} accent="ok" />
            <Metric label="In progress" value={String(summary.in_progress)} accent="warn" />
            <Metric label="Failed" value={String(summary.failed)} accent="bad" />
            <Metric label="Cancelled" value={String(summary.cancelled)} />
          </div>
          <div className="grid gap-4 sm:grid-cols-3">
            <Metric
              label="COD collected (delivered)"
              value={formatLrdFromCents(summary.cod_collected_lrd_cents)}
            />
            <Metric
              label="Delivery fees (delivered)"
              value={formatLrdFromCents(summary.delivery_fees_lrd_cents)}
            />
            <Metric
              label="Avg delivery time"
              value={
                summary.avg_delivery_minutes != null
                  ? `${summary.avg_delivery_minutes} min`
                  : '—'
              }
            />
          </div>
          {opsSummary && (
            <Card>
              <CardHeader>
                <CardTitle>Operational analytics</CardTitle>
                <CardDescription>SQL aggregates via get_operational_analytics</CardDescription>
              </CardHeader>
              <CardContent className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4 text-sm">
                <Metric label="Completion rate" value={`${opsSummary.completion_rate ?? 0}%`} />
                <Metric label="Failed rate" value={`${opsSummary.failed_rate ?? 0}%`} />
                <Metric
                  label="Avg minutes"
                  value={String(opsSummary.avg_delivery_minutes ?? '—')}
                />
                <Metric
                  label="COD outstanding"
                  value={formatLrdFromCents(Number(opsSummary.cod_outstanding_cents ?? 0))}
                />
              </CardContent>
            </Card>
          )}
          {Array.isArray(riderPerf) && riderPerf.length > 0 && (
            <Card>
              <CardHeader>
                <CardTitle>Rider performance (30d)</CardTitle>
              </CardHeader>
              <CardContent className="text-sm">
                <ul>
                  {(riderPerf as { rider_name: string; completed: number; failed: number }[])
                    .slice(0, 8)
                    .map((r) => (
                      <li key={r.rider_name} className="border-b py-1">
                        {r.rider_name}: {r.completed} completed · {r.failed} failed
                      </li>
                    ))}
                </ul>
              </CardContent>
            </Card>
          )}
          {profitability && (
            <Card>
              <CardHeader>
                <CardTitle>Profitability (30d)</CardTitle>
              </CardHeader>
              <CardContent className="grid gap-2 sm:grid-cols-3 text-sm">
                <Metric
                  label="Gross margin"
                  value={formatLrdFromCents(Number((profitability as { gross_margin_cents?: number }).gross_margin_cents ?? 0))}
                />
                <Metric
                  label="Revenue"
                  value={formatLrdFromCents(Number((profitability as { revenue_cents?: number }).revenue_cents ?? 0))}
                />
                <Metric
                  label="Total cost"
                  value={formatLrdFromCents(Number((profitability as { total_cost_cents?: number }).total_cost_cents ?? 0))}
                />
              </CardContent>
            </Card>
          )}
        </>
      )}

      <Card>
        <CardHeader>
          <CardTitle>Top riders</CardTitle>
          <CardDescription>Completed deliveries in selected period</CardDescription>
        </CardHeader>
        <CardContent className="overflow-x-auto">
          <table className="w-full min-w-[480px] text-left text-sm">
            <thead>
              <tr className="border-b text-xs uppercase text-[var(--color-muted)]">
                <th className="py-2">ID</th>
                <th className="py-2">Name</th>
                <th className="py-2">Period</th>
                <th className="py-2">All-time</th>
                <th className="py-2">Rating</th>
              </tr>
            </thead>
            <tbody>
              {(data?.top_riders ?? []).map((r) => (
                <tr key={r.rider_code} className="border-b">
                  <td className="py-2 font-medium">{r.rider_code}</td>
                  <td className="py-2">{r.full_name}</td>
                  <td className="py-2">{r.period_completed}</td>
                  <td className="py-2">{r.completed_deliveries}</td>
                  <td className="py-2">{Number(r.rating).toFixed(1)}</td>
                </tr>
              ))}
              {!isLoading && (data?.top_riders.length ?? 0) === 0 && (
                <tr>
                  <td colSpan={5} className="py-6 text-center text-[var(--color-muted)]">
                    No completed deliveries in this period.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </CardContent>
      </Card>
    </div>
  )
}

function Metric({
  label,
  value,
  accent,
}: {
  label: string
  value: string
  accent?: 'ok' | 'warn' | 'bad'
}) {
  const accentClass =
    accent === 'ok'
      ? 'text-emerald-700'
      : accent === 'warn'
        ? 'text-amber-700'
        : accent === 'bad'
          ? 'text-red-700'
          : ''

  return (
    <Card>
      <CardContent className="pt-6">
        <p className="text-sm text-[var(--color-muted)]">{label}</p>
        <p className={`mt-1 text-2xl font-semibold ${accentClass}`}>{value}</p>
      </CardContent>
    </Card>
  )
}
