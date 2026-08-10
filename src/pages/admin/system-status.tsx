import { Activity, Database, HardDrive, KeyRound, Mail, MessageSquare, Server, Webhook } from 'lucide-react'
import { CommandCard, SectionHeader, StatusChip } from '@/components/admin/control-tower'
import { healthStateColor, healthStateFrom, HEALTH_STATE_LABEL, type HealthState } from '@/lib/admin-control-tower'
import { useExtendedHealth } from '@/hooks/use-admin-platform'

export function AdminSystemStatusPage() {
  const { data, isLoading, error } = useExtendedHealth(true)

  const dbStatus = healthStateFrom((data?.database as { status?: string } | undefined)?.status)
  const authStatus = healthStateFrom((data?.auth as { status?: string } | undefined)?.status)
  const smsStatus = healthStateFrom((data?.sms_worker as { status?: string } | undefined)?.status)
  const webhookStatus = healthStateFrom((data?.webhook_dispatcher as { status?: string } | undefined)?.status)
  const emailStatus = healthStateFrom((data?.email_worker as { status?: string } | undefined)?.status)
  const apiFailures = Number(data?.api_auth_failures_24h ?? 0)
  const apiStatus: HealthState = apiFailures >= 20 ? 'degraded' : data ? 'operational' : 'not_configured'

  return (
    <div className="space-y-8">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <SectionHeader eyebrow="Platform health" title="System status" className="mb-0" />
        <p className="text-xs text-zinc-500">Refreshed every 60s</p>
      </div>

      {error && <p className="text-sm text-red-400">{error instanceof Error ? error.message : 'Failed to load'}</p>}

      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <HealthTile label="Database" icon={Database} state={dbStatus} loading={isLoading} note={(data?.database as { note?: string } | undefined)?.note} />
        <HealthTile label="Auth" icon={KeyRound} state={authStatus} loading={isLoading} />
        <HealthTile label="Storage" icon={HardDrive} state="not_configured" loading={false} note="Not instrumented — no storage health probe wired up yet" />
        <HealthTile label="Edge Functions" icon={Server} state="operational" loading={false} note="jobs-scheduler, sms-dispatch, webhooks-dispatch, email-dispatch deployed" />
        <HealthTile
          label="Webhooks"
          icon={Webhook}
          state={webhookStatus}
          loading={isLoading}
          note={`${(data?.webhook_dispatcher as Record<string, number> | undefined)?.pending ?? 0} pending, ${(data?.webhook_dispatcher as Record<string, number> | undefined)?.dead ?? 0} dead-letter`}
        />
        <HealthTile
          label="SMS queue"
          icon={MessageSquare}
          state={smsStatus}
          loading={isLoading}
          note={`${(data?.sms_worker as Record<string, number> | undefined)?.pending ?? 0} pending/failed`}
        />
        <HealthTile label="Email worker" icon={Mail} state={emailStatus} loading={isLoading} note={`${(data?.email_worker as Record<string, number> | undefined)?.pending ?? 0} pending`} />
        <HealthTile label="Jobs" icon={Server} state="operational" loading={false} note="jobs-scheduler cron (trial expiry, subscription upkeep)" />
        <HealthTile label="API error rate" icon={Activity} state={apiStatus} loading={isLoading} note={`${apiFailures} auth failures (24h)`} />
      </div>

      <section>
        <SectionHeader eyebrow="MTN carrier channels" />
        <div className="grid gap-3 sm:grid-cols-3">
          <HealthTile label="MTN SMS" icon={MessageSquare} state="not_configured" loading={false} note="Awaiting integration" />
          <HealthTile label="MTN USSD" icon={MessageSquare} state="not_configured" loading={false} note="Awaiting integration" />
          <HealthTile label="MTN MoMo" icon={MessageSquare} state="not_configured" loading={false} note="Awaiting integration" />
        </div>
      </section>

      <p className="text-xs text-zinc-600">
        Queue depth reflects internal worker backlog, not an external SLA. Integrations left "Not configured" are not
        yet wired to a live provider — this is expected pre-launch state, not a fault.
      </p>
    </div>
  )
}

function HealthTile({
  label,
  icon: Icon,
  state,
  loading,
  note,
}: {
  label: string
  icon: typeof Database
  state: HealthState
  loading?: boolean
  note?: string
}) {
  return (
    <CommandCard className="p-4">
      <div className="flex items-center gap-2">
        <Icon className="h-4 w-4 text-zinc-500" aria-hidden />
        <p className="text-sm font-medium text-zinc-200">{label}</p>
      </div>
      <div className="mt-3">
        {loading ? (
          <div className="h-5 w-24 animate-pulse rounded bg-white/5" />
        ) : (
          <StatusChip color={healthStateColor(state)} label={HEALTH_STATE_LABEL[state]} />
        )}
      </div>
      {note && <p className="mt-2 text-xs text-zinc-500">{note}</p>}
    </CommandCard>
  )
}
