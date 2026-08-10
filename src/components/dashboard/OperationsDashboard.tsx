import { useMemo } from 'react'
import { AlertTriangle, Banknote, CheckCircle2, Package, Truck, Users } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/Card'
import { KpiCard } from '@/components/ui/KpiCard'
import { KpiSkeletonGrid } from '@/components/ui/Skeleton'
import { useAccess } from '@/hooks/use-access'
import { useAuth } from '@/hooks/use-auth'
import { setActiveCompanyId } from '@/hooks/use-auth-context'
import { useCompanyPlanUsage, useRidersList } from '@/hooks/use-riders'
import { useCompanyPayments } from '@/hooks/use-settings'
import { useWorkspaceReport } from '@/hooks/use-reports'
import { useDeliveries } from '@/hooks/use-deliveries'
import { buildAttentionItems, friendlyDashboardError, riderAvailabilityBreakdown } from '@/lib/dashboard-metrics'
import { formatLrdFromCents } from '@/utils/delivery-schemas'
import { WorkspaceHeader } from '@/components/dashboard/WorkspaceHeader'
import { OnboardingProgressStrip } from '@/components/dashboard/OnboardingProgressStrip'
import { AttentionCenter } from '@/components/dashboard/AttentionCenter'
import { RiderAvailabilityCard } from '@/components/dashboard/RiderAvailabilityCard'
import { DeliveryTrendCard } from '@/components/dashboard/DeliveryTrendCard'
import { RecentDeliveriesPanel } from '@/components/dashboard/RecentDeliveriesPanel'
import { DashboardLiveMapCard } from '@/components/dashboard/DashboardLiveMapCard'

export function OperationsDashboard({ companyId }: { companyId: string }) {
  const { context, refreshContext } = useAuth()
  const { can } = useAccess()
  const membership = context?.memberships.find((m) => m.company_id === companyId)
  const companyName = membership?.company.name ?? 'Workspace'
  const companyStatus = membership?.company.status

  const { data: report, isLoading: reportLoading, error: reportError, refetch: refetchReport } = useWorkspaceReport(
    companyId,
    'day',
  )
  const { data: plan } = useCompanyPlanUsage(companyId)
  const { data: riders = [] } = useRidersList(companyId)
  const {
    data: recentDeliveries,
    isLoading: deliveriesLoading,
    error: deliveriesError,
    refetch: refetchDeliveries,
  } = useDeliveries(companyId, { page: 1, pageSize: 100 })
  const { data: payments = [] } = useCompanyPayments(companyId)

  const allDeliveries = recentDeliveries?.rows ?? []
  const recentTen = allDeliveries.slice(0, 8)

  const riderNameById = useMemo(() => {
    const m = new Map<string, string>()
    for (const r of riders) m.set(r.id, r.rider_code)
    return m
  }, [riders])

  const riderBreakdown = useMemo(() => riderAvailabilityBreakdown(riders), [riders])

  const codAwaitingReconciliation = useMemo(
    () => payments.filter((p) => p.status === 'collected').length,
    [payments],
  )

  const attentionItems = useMemo(
    () =>
      buildAttentionItems({
        deliveries: allDeliveries,
        now: new Date(),
        codAwaitingReconciliation,
        smsCreditsRemaining: plan ? plan.sms_credits : null,
        riders: riderBreakdown,
        totalRiders: riders.length,
      }),
    [allDeliveries, codAwaitingReconciliation, plan, riderBreakdown, riders.length],
  )

  const summary = report?.summary
  const reportUnavailable = Boolean(reportError)
  // Independent of get_workspace_report — derived straight from the
  // deliveries list, so it stays accurate even when the report RPC fails.
  const pendingPickups = allDeliveries.filter((d) => d.status === 'pending').length

  function handleSwitchCompany(nextCompanyId: string) {
    setActiveCompanyId(nextCompanyId)
    refreshContext()
  }

  if (!context) return null

  return (
    <div className="space-y-6 animate-fade-in">
      <WorkspaceHeader
        context={context}
        companyId={companyId}
        companyName={companyName}
        planName={plan?.plan_name}
        companyStatus={companyStatus}
        canCreateDelivery={can('page:deliveries:write')}
        onSwitchCompany={handleSwitchCompany}
      />

      <OnboardingProgressStrip companyId={companyId} />

      {companyStatus !== 'active' && (
        <div className="flex items-start gap-3 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-950">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />
          <p>
            Company status: <strong>{companyStatus}</strong> — activate in Supabase before live dispatch.
          </p>
        </div>
      )}

      {reportLoading ? (
        <KpiSkeletonGrid count={6} />
      ) : (
        <div className="space-y-2">
          {reportUnavailable && (
            <div className="flex items-center justify-between gap-3 rounded-lg border border-amber-200 bg-amber-50 px-3 py-1.5 text-xs text-amber-900">
              <span>{friendlyDashboardError(reportError)}</span>
              <button
                type="button"
                onClick={() => void refetchReport()}
                className="shrink-0 font-medium underline underline-offset-2 hover:text-amber-950"
              >
                Retry
              </button>
            </div>
          )}
          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-6">
            <KpiCard label="Deliveries today" value={reportUnavailable ? '—' : String(summary?.total ?? 0)} icon={Truck} />
            <KpiCard label="In transit" value={reportUnavailable ? '—' : String(summary?.in_progress ?? 0)} icon={Package} />
            <KpiCard label="Pending pickup" value={String(pendingPickups)} icon={Package} />
            <KpiCard label="Completed" value={reportUnavailable ? '—' : String(summary?.completed ?? 0)} icon={CheckCircle2} />
            <KpiCard
              label="Active riders"
              value={String(riderBreakdown.available + riderBreakdown.busy)}
              icon={Users}
              hint={`${riders.length} total`}
            />
            <KpiCard
              label="COD collected today"
              value={reportUnavailable ? '—' : formatLrdFromCents(summary?.cod_collected_lrd_cents ?? 0)}
              icon={Banknote}
            />
          </div>
        </div>
      )}

      <div className="grid gap-6 lg:grid-cols-5">
        <div className="lg:col-span-3">
          <DashboardLiveMapCard companyId={companyId} />
        </div>
        <div className="lg:col-span-2">
          <RecentDeliveriesPanel
            deliveries={recentTen}
            riderNameById={riderNameById}
            isLoading={deliveriesLoading}
            error={deliveriesError}
            onRetry={() => void refetchDeliveries()}
          />
        </div>
      </div>

      <div className="grid gap-6 lg:grid-cols-3">
        <div className="lg:col-span-2">
          <DeliveryTrendCard companyId={companyId} />
        </div>
        <RiderAvailabilityCard breakdown={riderBreakdown} total={riders.length} />
      </div>

      <AttentionCenter items={attentionItems} />

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base">Top riders</CardTitle>
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
  )
}
