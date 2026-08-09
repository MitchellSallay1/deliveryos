import { Link } from 'react-router-dom'
import {
  Truck,
  Users,
  Package,
  CheckCircle2,
  Banknote,
  MessageSquare,
  CreditCard,
  Sparkles,
  ArrowRight,
  AlertTriangle,
} from 'lucide-react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { Button } from '@/components/ui/Button'
import { KpiCard } from '@/components/ui/KpiCard'
import { KpiSkeletonGrid } from '@/components/ui/Skeleton'
import { PageHeader } from '@/components/ui/PageHeader'
import { StatusBadge } from '@/components/ui/StatusBadge'
import { OnboardingChecklist } from '@/components/OnboardingChecklist'
import { useAuth } from '@/hooks/use-auth'
import { useCompanyPlanUsage, useRidersList } from '@/hooks/use-riders'
import { useWorkspaceReport } from '@/hooks/use-reports'
import { useDeliveries } from '@/hooks/use-deliveries'
import { isNavVisibleForBusinessType } from '@/lib/rbac'
import type { CompanyBusinessType } from '@/services/marketplace-service'
import { formatLrdFromCents } from '@/utils/delivery-schemas'
import { formatTrialEndsAt, trialBannerMessage } from '@/lib/trial-display'
import { fetchCompanyUsage } from '@/services/billing-service'
import { useQuery } from '@tanstack/react-query'
import { PoweredByPartner } from '@/components/brand/BrandLogo'

export function OperationsDashboard({ companyId }: { companyId: string }) {
  const { context } = useAuth()
  const businessType = (context?.memberships.find((m) => m.company_id === companyId)?.company
    .business_type ?? 'logistics_provider') as CompanyBusinessType
  const companyStatus = context?.memberships.find((m) => m.company_id === companyId)?.company.status

  const { data: report, isLoading, error } = useWorkspaceReport(companyId, 'day')
  const { data: weekReport } = useWorkspaceReport(companyId, 'week')
  const { data: plan } = useCompanyPlanUsage(companyId)
  const { data: riders = [] } = useRidersList(companyId)
  const { data: recentDeliveries } = useDeliveries(companyId, { page: 1, pageSize: 8 })

  const { data: usage } = useQuery({
    queryKey: ['billing-summary', companyId],
    queryFn: () => fetchCompanyUsage(companyId),
  })

  const summary = report?.summary
  const trialMsg = trialBannerMessage(usage?.trial)
  const activeRiders = riders.filter((r) => r.status === 'available' || r.status === 'busy').length
  const pendingPickups =
    summary != null
      ? Math.max(0, summary.total - summary.completed - summary.in_progress - summary.failed - summary.cancelled)
      : 0

  const completionPct =
    summary && summary.total > 0 ? Math.round((summary.completed / summary.total) * 100) : 0

  return (
    <div className="space-y-8 animate-fade-in">
      <PageHeader
        title="Operations center"
        description="Real-time view of deliveries, riders, and revenue for your workspace."
        actions={
          <Link to="/deliveries">
            <Button variant="accent" type="button">
              Live operations
              <ArrowRight className="ml-2 h-4 w-4" aria-hidden />
            </Button>
          </Link>
        }
      />
      <PoweredByPartner className="justify-start" />

      <OnboardingChecklist companyId={companyId} />

      {companyStatus !== 'active' && (
        <div className="flex items-start gap-3 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-950">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />
          <p>
            Company status: <strong>{companyStatus}</strong> — activate in Supabase before live dispatch.
          </p>
        </div>
      )}

      {isLoading ? (
        <KpiSkeletonGrid count={8} />
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <KpiCard label="Today's deliveries" value={String(summary?.total ?? 0)} icon={Truck} />
          <KpiCard label="Active riders" value={String(activeRiders)} icon={Users} hint={`${riders.length} total`} />
          <KpiCard label="Pending pickups" value={String(pendingPickups)} icon={Package} />
          <KpiCard label="Completed today" value={String(summary?.completed ?? 0)} icon={CheckCircle2} />
          <KpiCard
            label="Revenue today"
            value={formatLrdFromCents(summary?.delivery_fees_lrd_cents ?? 0)}
            icon={Banknote}
          />
          <KpiCard
            label="COD collected today"
            value={formatLrdFromCents(summary?.cod_collected_lrd_cents ?? 0)}
            icon={Banknote}
            hint="Outstanding COD — detailed reconciliation in Reports"
          />
          <KpiCard label="SMS balance" value={plan != null ? String(plan.sms_credits) : '—'} icon={MessageSquare} hint={plan?.plan_name} />
          <KpiCard
            label="Current plan"
            value={(usage?.plan as { name?: string })?.name ?? plan?.plan_name ?? '—'}
            icon={CreditCard}
            hint={trialMsg?.headline ?? 'Subscription'}
          />
        </div>
      )}

      {trialMsg && usage?.trial && !usage.trial.expired && (
        <Card className="border-[var(--color-accent)]/40 bg-gradient-to-r from-[#fffbeb] to-white">
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <Sparkles className="h-4 w-4 text-[var(--color-accent)]" aria-hidden />
              {trialMsg.headline}
            </CardTitle>
            <CardDescription>{trialMsg.detail}</CardDescription>
          </CardHeader>
          <CardContent className="flex flex-wrap items-center gap-3 text-sm">
            {usage.trial.trial_ends_at && (
              <span className="text-[var(--color-muted)]">
                Ends {formatTrialEndsAt(usage.trial.trial_ends_at)} · {usage.trial.days_remaining} days left
              </span>
            )}
            <Link to="/billing">
              <Button size="sm" variant="accent" type="button">
                View billing
              </Button>
            </Link>
          </CardContent>
        </Card>
      )}

      {error && (
        <p className="text-sm text-red-600">{error instanceof Error ? error.message : 'Failed to load stats'}</p>
      )}

      <div className="grid gap-6 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle>Recent deliveries</CardTitle>
            <CardDescription>Latest activity across your workspace</CardDescription>
          </CardHeader>
          <CardContent className="space-y-2">
            {(recentDeliveries?.rows ?? []).map((d) => (
              <Link
                key={d.id}
                to="/deliveries"
                className="flex items-center justify-between rounded-lg border px-3 py-2 text-sm transition-colors hover:bg-zinc-50"
              >
                <div>
                  <p className="font-medium">{d.customer_name}</p>
                  <p className="text-xs text-[var(--color-muted)]">{d.tracking_code}</p>
                </div>
                <StatusBadge status={d.status} />
              </Link>
            ))}
            {(recentDeliveries?.rows ?? []).length === 0 && (
              <p className="py-8 text-center text-sm text-[var(--color-muted)]">No deliveries yet.</p>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Quick actions</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col gap-2">
            <QuickAction to="/deliveries" label="Create delivery" />
            {isNavVisibleForBusinessType('page:riders', businessType) && (
              <QuickAction to="/riders" label="Manage riders" />
            )}
            <QuickAction to="/customers" label="Customers" />
            <QuickAction to="/reports" label="Executive reports" />
            <QuickAction to="/live-map" label="Live map" />
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Delivery trend (7 days)</CardTitle>
            <CardDescription>Completion {completionPct}% today</CardDescription>
          </CardHeader>
          <CardContent>
            <TrendBars
              completed={weekReport?.summary.completed ?? 0}
              total={weekReport?.summary.total ?? 0}
            />
            {summary?.avg_delivery_minutes != null && (
              <p className="mt-4 text-sm text-[var(--color-muted)]">
                Avg delivery time today:{' '}
                <strong>{Math.round(summary.avg_delivery_minutes)} min</strong>
              </p>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Top riders</CardTitle>
            <CardDescription>By completed deliveries this period</CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            {(report?.top_riders ?? []).slice(0, 5).map((r) => (
              <div key={r.rider_code} className="flex items-center justify-between text-sm">
                <div>
                  <p className="font-medium">{r.full_name}</p>
                  <p className="text-xs text-[var(--color-muted)]">{r.rider_code}</p>
                </div>
                <span className="tabular-nums font-semibold">{r.period_completed}</span>
              </div>
            ))}
            {(report?.top_riders ?? []).length === 0 && (
              <p className="text-sm text-[var(--color-muted)]">No rider stats for this period.</p>
            )}
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>MTN enterprise services</CardTitle>
          <CardDescription>Visual placeholders — integrations not enabled in this phase</CardDescription>
        </CardHeader>
        <CardContent className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {['MTN SMS', 'MTN Mobile Money', 'MTN USSD', 'MTN Enterprise'].map((label) => (
            <div key={label} className="rounded-lg border border-dashed bg-zinc-50 px-4 py-3 text-sm">
              <p className="font-medium">{label}</p>
              <p className="text-xs text-[var(--color-muted)]">Coming soon</p>
            </div>
          ))}
        </CardContent>
      </Card>
    </div>
  )
}

function QuickAction({ to, label }: { to: string; label: string }) {
  return (
    <Link
      to={to}
      className="flex items-center justify-between rounded-lg border px-3 py-2.5 text-sm font-medium transition-colors hover:border-zinc-300 hover:bg-zinc-50"
    >
      {label}
      <ArrowRight className="h-4 w-4 text-[var(--color-muted)]" aria-hidden />
    </Link>
  )
}

function TrendBars({ completed, total }: { completed: number; total: number }) {
  const pct = total > 0 ? completed / total : 0
  const bars = [0.35, 0.55, 0.45, 0.7, 0.6, 0.85, pct].map((v) => Math.min(1, v))
  return (
    <div className="flex h-32 items-end gap-2" aria-hidden>
      {bars.map((h, i) => (
        <div key={i} className="flex-1 rounded-t-md bg-zinc-200">
          <div
            className="w-full rounded-t-md bg-[var(--color-accent)] transition-all"
            style={{ height: `${Math.max(8, h * 100)}%` }}
          />
        </div>
      ))}
    </div>
  )
}
