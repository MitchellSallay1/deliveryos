import { AdminBillingOverview } from '@/pages/admin/billing-overview'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { useTrialFunnel } from '@/hooks/use-admin-platform'
import { usePlatformBillingMetrics } from '@/hooks/use-billing'
import { formatLrd } from '@/components/admin/AdminHealthBadge'

export function AdminRevenuePage() {
  const { data } = usePlatformBillingMetrics(true)
  const billing = data as Record<string, number> | undefined
  const { data: funnel } = useTrialFunnel(true)

  const mrrNote =
    'Monthly revenue below is cash collected this calendar month (MTD), not annualized MRR. Subscription MRR estimate is on the command center.'

  return (
    <div className="space-y-6">
      <AdminBillingOverview />
      <Card>
        <CardHeader>
          <CardTitle>Revenue notes</CardTitle>
          <CardDescription>{mrrNote}</CardDescription>
        </CardHeader>
        <CardContent className="text-sm">
          {billing && (
            <p>
              MTD collected:{' '}
              <strong>{formatLrd(Number(billing.monthly_revenue_cents ?? 0))}</strong> · Unpaid invoices:{' '}
              {billing.unpaid_invoices}
            </p>
          )}
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>Trial conversion (derived)</CardTitle>
        </CardHeader>
        <CardContent>
          <pre className="text-xs">{JSON.stringify(funnel, null, 2)}</pre>
        </CardContent>
      </Card>
    </div>
  )
}
