import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { usePlatformBillingMetrics } from '@/hooks/use-billing'
import { formatLrdFromCents } from '@/utils/delivery-schemas'

export function AdminBillingOverview() {
  const { data, isLoading } = usePlatformBillingMetrics(true)
  const m = data as Record<string, number | Record<string, number>> | undefined

  return (
    <Card>
      <CardHeader>
        <CardTitle>Billing metrics</CardTitle>
        <CardDescription>Platform subscription & invoice KPIs</CardDescription>
      </CardHeader>
      <CardContent>
        {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
        {m && (
          <dl className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3 text-sm">
            <Metric label="Active subscriptions" value={Number(m.active_subscriptions ?? 0)} />
            <Metric label="Trialing" value={Number(m.trialing ?? 0)} />
            <Metric label="Past due" value={Number(m.past_due ?? 0)} />
            <Metric label="Suspended subs" value={Number(m.suspended_subscriptions ?? 0)} />
            <Metric label="Unpaid invoices" value={Number(m.unpaid_invoices ?? 0)} />
            <Metric
              label="MTD revenue"
              value={formatLrdFromCents(Number(m.monthly_revenue_cents ?? 0))}
            />
          </dl>
        )}
      </CardContent>
    </Card>
  )
}

function Metric({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="rounded-lg border p-3">
      <dt className="text-xs uppercase text-[var(--color-muted)]">{label}</dt>
      <dd className="mt-1 text-lg font-semibold">{value}</dd>
    </div>
  )
}
