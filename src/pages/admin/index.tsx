import { Link } from 'react-router-dom'
import {
  Activity,
  AlertTriangle,
  Ban,
  Building2,
  CheckCircle2,
  Clock,
  CreditCard,
  Database,
  Gauge,
  KeyRound,
  Package,
  Radio,
  Server,
  ShieldCheck,
  Smartphone,
  Truck,
  Wallet,
  Webhook,
  XCircle,
} from 'lucide-react'
import { CommandCard, CommandCardHeader, CommandKpi, SectionHeader, StatusChip } from '@/components/admin/control-tower'
import {
  formatLrd,
  formatPercent,
  healthStateColor,
  healthStateFrom,
  HEALTH_STATE_LABEL,
  overallPlatformStatus,
  trialConversionRate,
  type PlatformAlert,
} from '@/lib/admin-control-tower'
import {
  useCommandCenter,
  useExtendedHealth,
  useLiveSnapshot,
  usePlatformAlerts,
  useTrialFunnel,
} from '@/hooks/use-admin-platform'
import { usePlatformBillingMetrics } from '@/hooks/use-billing'

export function AdminOverviewPage() {
  const { data, isLoading, error } = useCommandCenter(true)
  const { data: alertData } = usePlatformAlerts(true)
  const { data: funnel } = useTrialFunnel(true)
  const { data: billing } = usePlatformBillingMetrics(true)
  const { data: health } = useExtendedHealth(true)
  const { data: live } = useLiveSnapshot(true)
  const liveRiders = live?.riders as Record<string, number> | undefined

  const alerts = (alertData?.alerts ?? []) as PlatformAlert[]
  const overall = overallPlatformStatus(alerts)
  const trialing = Number(funnel?.trialing ?? 0)
  const activatedActive = Number(funnel?.activated_active ?? 0)
  const conversion = trialConversionRate(trialing, activatedActive)

  return (
    <div className="space-y-8">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <StatusChip color={overall.color} label={overall.label} className="text-sm" />
          {data && <p className="text-xs text-zinc-500">Refreshed {new Date(data.checked_at).toLocaleTimeString()}</p>}
        </div>
        <div className="flex flex-wrap gap-2">
          <Link
            to="/admin/live"
            className="rounded-lg bg-[#FFCB05] px-3.5 py-2 text-xs font-semibold text-black hover:brightness-95"
          >
            Open live operations
          </Link>
          <Link
            to="/admin/map"
            className="rounded-lg border border-white/10 bg-white/[0.03] px-3.5 py-2 text-xs font-medium text-zinc-300 hover:bg-white/[0.06]"
          >
            Network map
          </Link>
        </div>
      </div>

      {alerts.length > 0 && (
        <CommandCard className="border-amber-400/20">
          <CommandCardHeader
            title="Active alerts"
            description="Prioritized from live platform signals — see Alert Center for full detail."
            action={
              <Link to="/admin/alerts" className="text-xs font-medium text-[#FFCB05] hover:underline">
                View all →
              </Link>
            }
          />
          <div className="divide-y divide-white/[0.05]">
            {alerts.slice(0, 4).map((a) => (
              <div key={a.title} className="flex flex-wrap items-center justify-between gap-2 px-4 py-3">
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <StatusChip
                      color={a.severity === 'critical' ? 'red' : a.severity === 'low' ? 'gray' : 'amber'}
                      label={a.severity}
                    />
                    <p className="truncate text-sm font-medium text-zinc-100">{a.title}</p>
                  </div>
                  <p className="mt-0.5 text-xs text-zinc-500">{a.detail}</p>
                </div>
                <Link
                  to={a.href}
                  className="shrink-0 rounded-lg border border-white/10 px-2.5 py-1 text-xs text-zinc-300 hover:bg-white/5"
                >
                  Investigate
                </Link>
              </div>
            ))}
          </div>
        </CommandCard>
      )}

      <section>
        <SectionHeader eyebrow="Platform status" />
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
          <CommandKpi
            label="Overall health"
            value={overall.label}
            icon={ShieldCheck}
            color={overall.color}
            loading={isLoading}
          />
          <CommandKpi
            label="Active companies"
            value={data ? String(data.companies_active) : '—'}
            hint={data ? `${data.companies_total} total` : undefined}
            icon={Building2}
            loading={isLoading}
          />
          <CommandKpi
            label="On trial"
            value={String(trialing)}
            icon={Clock}
            loading={!funnel}
          />
          <CommandKpi
            label="Paying companies"
            value={billing ? String((billing as Record<string, number>).active_subscriptions ?? 0) : '—'}
            icon={CheckCircle2}
            color="green"
            loading={!billing}
          />
          <CommandKpi
            label="Suspended"
            value={data ? String(data.companies_suspended) : '—'}
            icon={Ban}
            color={data && data.companies_suspended > 0 ? 'amber' : undefined}
            loading={isLoading}
          />
        </div>
      </section>

      <section>
        <SectionHeader eyebrow="Network activity" />
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-6">
          <CommandKpi
            label="Deliveries today"
            value={data ? String(data.deliveries_today) : '—'}
            icon={Package}
            loading={isLoading}
          />
          <CommandKpi
            label="Active deliveries"
            value={data ? String(data.deliveries_in_transit) : '—'}
            icon={Truck}
            loading={isLoading}
          />
          <CommandKpi
            label="Completed today"
            value={data ? String(data.deliveries_completed_today) : '—'}
            icon={CheckCircle2}
            color="green"
            loading={isLoading}
          />
          <CommandKpi
            label="Failed today"
            value={data ? String(data.deliveries_failed_today) : '—'}
            icon={XCircle}
            color={data && data.deliveries_failed_today > 0 ? 'red' : undefined}
            loading={isLoading}
          />
          <CommandKpi
            label="Active riders"
            value={data ? String(data.riders_active) : '—'}
            hint={data ? `${data.riders_total} registered` : undefined}
            icon={Smartphone}
            loading={isLoading}
          />
          <CommandKpi
            label="Available now"
            value={liveRiders ? String(liveRiders.available ?? 0) : '—'}
            hint={liveRiders ? `${liveRiders.busy ?? 0} busy, ${liveRiders.offline ?? 0} offline` : undefined}
            icon={Radio}
            loading={!live}
          />
        </div>
      </section>

      <section>
        <SectionHeader eyebrow="Commercial" />
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
          <CommandKpi
            label="Est. subscription MRR"
            value={data ? formatLrd(Number(data.subscription_mrr_estimate_cents)) : '—'}
            hint="Sum of active plan prices"
            icon={Wallet}
            loading={isLoading}
          />
          <CommandKpi
            label="MTD revenue"
            value={billing ? formatLrd(Number((billing as Record<string, number>).monthly_revenue_cents ?? 0)) : '—'}
            hint="Cash collected this month"
            icon={CreditCard}
            loading={!billing}
          />
          <CommandKpi
            label="Trial → paid conversion"
            value={formatPercent(conversion)}
            hint={conversion === null ? 'No trial data yet' : `${activatedActive} of ${trialing + activatedActive}`}
            icon={Gauge}
            loading={!funnel}
          />
          <CommandKpi
            label="Past due"
            value={billing ? String((billing as Record<string, number>).past_due ?? 0) : '—'}
            icon={AlertTriangle}
            color={billing && (billing as Record<string, number>).past_due > 0 ? 'amber' : undefined}
            loading={!billing}
          />
          <CommandKpi
            label="SMS credit usage"
            value={data ? String(data.sms_sent_today) : '—'}
            hint="Sent today, all companies"
            icon={Radio}
            loading={isLoading}
          />
        </div>
      </section>

      <section>
        <SectionHeader eyebrow="System" />
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <SystemTile label="Database" icon={Database} status={healthStateFrom((health?.database as { status?: string } | undefined)?.status)} />
          <SystemTile label="Auth" icon={KeyRound} status={healthStateFrom((health?.auth as { status?: string } | undefined)?.status)} />
          <SystemTile
            label="Webhook dispatch"
            icon={Webhook}
            status={healthStateFrom((health?.webhook_dispatcher as { status?: string } | undefined)?.status)}
            hint={
              health
                ? `${(health.webhook_dispatcher as Record<string, number>)?.dead ?? 0} dead-letter`
                : undefined
            }
          />
          <SystemTile
            label="SMS queue"
            icon={Radio}
            status={healthStateFrom((health?.sms_worker as { status?: string } | undefined)?.status)}
            hint={health ? `${(health.sms_worker as Record<string, number>)?.pending ?? 0} pending/failed` : undefined}
          />
          <SystemTile label="Background jobs" icon={Server} status="operational" hint="jobs-scheduler cron" />
          <SystemTile
            label="API error rate"
            icon={Activity}
            status={
              health && Number(health.api_auth_failures_24h ?? 0) >= 20 ? 'degraded' : 'operational'
            }
            hint={health ? `${health.api_auth_failures_24h ?? 0} auth failures (24h)` : undefined}
          />
          <SystemTile label="Edge Functions" icon={Server} status="operational" hint="jobs-scheduler, sms/webhooks/email-dispatch" />
          <SystemTile label="MTN carrier" icon={Radio} status="not_configured" hint="Awaiting integration" />
        </div>
      </section>

      {error && (
        <p className="text-sm text-red-400">
          {error instanceof Error ? error.message : 'Failed to load command center'}
        </p>
      )}
    </div>
  )
}

function SystemTile({
  label,
  icon: Icon,
  status,
  hint,
}: {
  label: string
  icon: typeof Database
  status: ReturnType<typeof healthStateFrom>
  hint?: string
}) {
  return (
    <CommandCard className="p-4">
      <div className="flex items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          <Icon className="h-4 w-4 text-zinc-500" aria-hidden />
          <p className="text-sm font-medium text-zinc-200">{label}</p>
        </div>
      </div>
      <div className="mt-3">
        <StatusChip color={healthStateColor(status)} label={HEALTH_STATE_LABEL[status]} />
      </div>
      {hint && <p className="mt-2 text-xs text-zinc-500">{hint}</p>}
    </CommandCard>
  )
}
