import { Building2, Package, Radio, Smartphone, TrendingUp, Wallet } from 'lucide-react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { KpiCard } from '@/components/ui/KpiCard'
import { AdminBillingOverview } from '@/pages/admin/billing-overview'
import { AdminHealthBadge } from '@/components/admin/AdminHealthBadge'
import { compareHint, formatLrd } from '@/components/admin/AdminHealthBadge'
import { useCommandCenter, usePlatformAlerts, useTrialFunnel } from '@/hooks/use-admin-platform'
import { Link } from 'react-router-dom'
import { Button } from '@/components/ui/Button'

export function AdminOverviewPage() {
  const { data, isLoading, error } = useCommandCenter(true)
  const { data: alerts } = usePlatformAlerts(true)
  const { data: funnel } = useTrialFunnel(true)

  const alertList = alerts?.alerts ?? []

  return (
    <div className="space-y-6">
      {alertList.length > 0 && (
        <Card className="border-amber-200 bg-amber-50/50">
          <CardHeader className="pb-2">
            <CardTitle className="text-base">Active alerts</CardTitle>
            <CardDescription>Prioritized from live platform signals</CardDescription>
          </CardHeader>
          <CardContent className="space-y-2">
            {alertList.map((a) => (
              <div
                key={a.title}
                className="flex flex-wrap items-center justify-between gap-2 rounded-lg border bg-white px-3 py-2"
              >
                <div>
                  <AdminHealthBadge level={a.severity === 'critical' ? 'at_risk' : 'needs_attention'} />
                  <p className="mt-1 text-sm font-medium">{a.title}</p>
                  <p className="text-xs text-[var(--color-muted)]">{a.detail}</p>
                </div>
                <Link to={a.href}>
                  <Button size="sm" variant="outline">
                    Investigate
                  </Button>
                </Link>
              </div>
            ))}
          </CardContent>
        </Card>
      )}

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <KpiCard
          label="Active companies"
          value={data ? String(data.companies_active) : '—'}
          hint={`${data?.companies_total ?? 0} total`}
          icon={Building2}
          loading={isLoading}
          trend={data ? `${data.companies_pending} pending · ${data.companies_suspended} suspended` : undefined}
        />
        <KpiCard
          label="Deliveries today"
          value={data ? String(data.deliveries_today) : '—'}
          icon={Package}
          loading={isLoading}
          trend={data ? compareHint(data.deliveries_today, data.deliveries_yesterday) : undefined}
        />
        <KpiCard
          label="In transit"
          value={data ? String(data.deliveries_in_transit) : '—'}
          hint={
            data
              ? `${data.deliveries_completed_today} completed · ${data.deliveries_failed_today} failed today`
              : undefined
          }
          icon={TrendingUp}
          loading={isLoading}
        />
        <KpiCard
          label="Active riders"
          value={data ? String(data.riders_active) : '—'}
          hint={data ? `${data.riders_total} registered` : undefined}
          icon={Smartphone}
          loading={isLoading}
        />
      </div>

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <KpiCard
          label="Logistics providers"
          value={data ? String(data.logistics_providers) : '—'}
          icon={Building2}
          loading={isLoading}
        />
        <KpiCard
          label="Merchants"
          value={data ? String(data.merchants) : '—'}
          icon={Building2}
          loading={isLoading}
        />
        <KpiCard
          label="Marketplace GMV"
          value={data ? formatLrd(Number(data.marketplace_gmv_lrd_cents)) : '—'}
          hint={
            data ? `${data.marketplace_requests_today} requests today` : undefined
          }
          icon={Wallet}
          loading={isLoading}
        />
        <KpiCard
          label="Est. subscription MRR"
          value={data ? formatLrd(Number(data.subscription_mrr_estimate_cents)) : '—'}
          hint="Sum of active plan prices; not cash collected"
          icon={Wallet}
          loading={isLoading}
        />
      </div>

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <KpiCard
          label="COD outstanding"
          value={data ? formatLrd(Number(data.cod_outstanding_lrd_cents)) : '—'}
          icon={Wallet}
          loading={isLoading}
        />
        <KpiCard
          label="SMS sent today"
          value={data ? String(data.sms_sent_today) : '—'}
          icon={Radio}
          loading={isLoading}
          trend={data ? compareHint(data.sms_sent_today, data.sms_sent_yesterday) : undefined}
        />
        <KpiCard
          label="API requests today"
          value={data ? String(data.api_requests_today) : '—'}
          icon={Radio}
          loading={isLoading}
          trend={data ? compareHint(data.api_requests_today, data.api_requests_yesterday) : undefined}
        />
        <KpiCard
          label="Control tower"
          value="Live"
          hint="Refreshes every 60s"
          icon={Radio}
          loading={false}
        />
      </div>

      {error && (
        <p className="text-sm text-red-600">
          {error instanceof Error ? error.message : 'Failed to load command center'}
        </p>
      )}

      <Card>
        <CardHeader>
          <CardTitle>Trial funnel (schema-derived)</CardTitle>
          <CardDescription>
            {typeof funnel?.note === 'string' ? funnel.note : 'Counts from subscriptions and tenant activity'}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {funnel && (
            <dl className="grid gap-3 sm:grid-cols-3 lg:grid-cols-6">
              <FunnelStat label="Trialing" value={Number(funnel.trialing ?? 0)} />
              <FunnelStat label="Active paid" value={Number(funnel.activated_active ?? 0)} />
              <FunnelStat label="First rider" value={Number(funnel.with_first_rider ?? 0)} />
              <FunnelStat label="First delivery" value={Number(funnel.with_first_delivery ?? 0)} />
              <FunnelStat label="Day 3+" value={Number(funnel.trial_day_3_reached ?? 0)} />
              <FunnelStat label="Day 7+" value={Number(funnel.trial_day_7_reached ?? 0)} />
            </dl>
          )}
        </CardContent>
      </Card>

      <AdminBillingOverview />

      <div className="flex flex-wrap gap-2">
        <Link to="/admin/live">
          <Button variant="accent">Open live tower</Button>
        </Link>
        <Link to="/admin/deliveries">
          <Button variant="outline">Delivery explorer</Button>
        </Link>
        <Link to="/admin/map">
          <Button variant="outline">Network map</Button>
        </Link>
      </div>
    </div>
  )
}

function FunnelStat({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-lg border p-3">
      <dt className="text-xs uppercase text-[var(--color-muted)]">{label}</dt>
      <dd className="mt-1 text-xl font-semibold tabular-nums">{value}</dd>
    </div>
  )
}
