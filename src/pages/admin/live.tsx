import { Link } from 'react-router-dom'
import {
  AlertTriangle,
  ArrowRight,
  Bike,
  CheckCircle2,
  Mail,
  MessageSquare,
  Package,
  Store,
  Webhook,
  XCircle,
} from 'lucide-react'
import {
  CommandCard,
  CommandCardBody,
  CommandCardHeader,
  CommandEmptyState,
  CommandTable,
  CommandTableHead,
  CommandTd,
  CommandTh,
  CommandTr,
  SectionHeader,
  StatusChip,
} from '@/components/admin/control-tower'
import { useAdminDeliveriesPage, useLiveSnapshot, useNetworkMetrics, usePlatformAlerts } from '@/hooks/use-admin-platform'
import type { PlatformAlert } from '@/lib/admin-control-tower'

const DELIVERY_STAGES: Array<{ key: string; label: string }> = [
  { key: 'assigned', label: 'Assigned' },
  { key: 'picked_up', label: 'Picked up' },
  { key: 'in_transit', label: 'In transit' },
]

export function AdminLivePage() {
  const { data, isLoading } = useLiveSnapshot(true)
  const { data: alertData } = usePlatformAlerts(true)
  const { data: network } = useNetworkMetrics(7, true)
  const { data: recentFailures } = useAdminDeliveriesPage({ status: 'failed', limit: 6 }, true)

  const deliveries = (data?.deliveries ?? {}) as Record<string, number>
  const riders = (data?.riders ?? {}) as Record<string, number>
  const marketplace = (data?.marketplace ?? {}) as Record<string, number>
  const comms = (data?.communications ?? {}) as Record<string, number>
  const alerts = (alertData?.alerts ?? []) as PlatformAlert[]
  const topCompanies = (network?.top_companies ?? []) as Array<{ id: string; name: string; deliveries: number }>
  const failedRows = (recentFailures?.rows ?? []) as Array<{
    id: string
    tracking_code: string
    company_name: string
    created_at: string
  }>

  const maxStage = Math.max(1, ...DELIVERY_STAGES.map((s) => deliveries[s.key] ?? 0))

  return (
    <div className="space-y-8">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <SectionHeader eyebrow="Live operations" title="Network operations center" className="mb-0" />
        <p className="text-xs text-zinc-500">
          {isLoading ? 'Refreshing…' : data ? `As of ${new Date(String(data.checked_at)).toLocaleTimeString()}` : ''}
          {' · '}auto-refresh every 15s
        </p>
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <CommandCard className="lg:col-span-2">
          <CommandCardHeader
            title="Deliveries moving through the network"
            description={`${deliveries.active ?? 0} active · ${deliveries.failed ?? 0} failed`}
          />
          <CommandCardBody>
            <div className="space-y-3">
              {DELIVERY_STAGES.map((s) => {
                const v = deliveries[s.key] ?? 0
                return (
                  <div key={s.key}>
                    <div className="flex items-center justify-between text-xs">
                      <span className="text-zinc-400">{s.label}</span>
                      <span className="font-medium tabular-nums text-zinc-200">{v}</span>
                    </div>
                    <div className="mt-1 h-2 overflow-hidden rounded-full bg-white/[0.05]">
                      <div
                        className="h-full rounded-full bg-[#FFCB05]"
                        style={{ width: `${Math.max(4, (v / maxStage) * 100)}%` }}
                      />
                    </div>
                  </div>
                )
              })}
            </div>
            <div className="mt-4 flex items-center justify-between rounded-lg border border-red-400/20 bg-red-400/[0.06] px-3 py-2">
              <span className="flex items-center gap-2 text-sm text-red-300">
                <XCircle className="h-4 w-4" /> Failed
              </span>
              <span className="text-sm font-semibold tabular-nums text-red-300">{deliveries.failed ?? 0}</span>
            </div>
          </CommandCardBody>
        </CommandCard>

        <CommandCard>
          <CommandCardHeader title="Active riders" description="Live status split" />
          <CommandCardBody className="space-y-2">
            <RiderRow label="Available" value={riders.available ?? 0} color="green" />
            <RiderRow label="Busy" value={riders.busy ?? 0} color="amber" />
            <RiderRow label="Offline" value={riders.offline ?? 0} color="gray" />
          </CommandCardBody>
        </CommandCard>
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <CommandCard>
          <CommandCardHeader title="Marketplace" description="Open network requests" />
          <CommandCardBody className="space-y-2 text-sm">
            <MetricLine icon={Store} label="Open requests" value={marketplace.open_requests ?? 0} />
            <MetricLine icon={Store} label="Pending offers" value={marketplace.pending_offers ?? 0} />
            <MetricLine icon={CheckCircle2} label="Accepted" value={marketplace.accepted ?? 0} />
          </CommandCardBody>
        </CommandCard>

        <CommandCard>
          <CommandCardHeader title="Communications queues" />
          <CommandCardBody className="space-y-2 text-sm">
            <MetricLine icon={MessageSquare} label="SMS pending" value={comms.sms_pending ?? 0} />
            <MetricLine icon={MessageSquare} label="SMS failed" value={comms.sms_failed ?? 0} warn={comms.sms_failed > 0} />
            <MetricLine icon={Webhook} label="Webhook failed" value={comms.webhook_failed ?? 0} warn={comms.webhook_failed > 0} />
            <MetricLine icon={Mail} label="Email pending" value={comms.email_pending ?? 0} />
          </CommandCardBody>
        </CommandCard>

        <CommandCard>
          <CommandCardHeader
            title="Operational alerts"
            action={
              <Link to="/admin/alerts" className="text-xs font-medium text-[#FFCB05] hover:underline">
                Alert center →
              </Link>
            }
          />
          <CommandCardBody>
            {alerts.length === 0 && <p className="text-sm text-zinc-500">No active alerts.</p>}
            <ul className="space-y-2">
              {alerts.slice(0, 4).map((a) => (
                <li key={a.title} className="flex items-start gap-2 text-sm">
                  <AlertTriangle
                    className={`mt-0.5 h-3.5 w-3.5 shrink-0 ${a.severity === 'critical' ? 'text-red-400' : 'text-amber-400'}`}
                  />
                  <span className="text-zinc-300">{a.title}</span>
                </li>
              ))}
            </ul>
          </CommandCardBody>
        </CommandCard>
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <CommandCard>
          <CommandCardHeader
            title="High-volume companies"
            description={network ? `Last ${String(network.period_days)} days` : undefined}
          />
          {topCompanies.length === 0 ? (
            <CommandEmptyState label="No delivery activity in this window." />
          ) : (
            <CommandTable>
              <CommandTableHead>
                <CommandTh>Company</CommandTh>
                <CommandTh className="text-right">Deliveries</CommandTh>
              </CommandTableHead>
              <tbody>
                {topCompanies.slice(0, 8).map((c) => (
                  <CommandTr key={c.id}>
                    <CommandTd>
                      <Link to={`/admin/companies/${c.id}`} className="hover:text-white hover:underline">
                        {c.name}
                      </Link>
                    </CommandTd>
                    <CommandTd className="text-right font-medium tabular-nums text-zinc-100">{c.deliveries}</CommandTd>
                  </CommandTr>
                ))}
              </tbody>
            </CommandTable>
          )}
        </CommandCard>

        <CommandCard>
          <CommandCardHeader
            title="Recent failures"
            description="Most recent failed deliveries platform-wide"
            action={
              <Link to="/admin/deliveries?status=failed" className="text-xs font-medium text-[#FFCB05] hover:underline">
                View all →
              </Link>
            }
          />
          {failedRows.length === 0 ? (
            <CommandEmptyState label="No failed deliveries." />
          ) : (
            <CommandTable>
              <CommandTableHead>
                <CommandTh>Tracking code</CommandTh>
                <CommandTh>Company</CommandTh>
                <CommandTh className="text-right">When</CommandTh>
              </CommandTableHead>
              <tbody>
                {failedRows.map((d) => (
                  <CommandTr key={d.id}>
                    <CommandTd className="font-mono text-xs text-zinc-300">{d.tracking_code}</CommandTd>
                    <CommandTd className="truncate">{d.company_name}</CommandTd>
                    <CommandTd className="text-right text-xs text-zinc-500">
                      {new Date(d.created_at).toLocaleString()}
                    </CommandTd>
                  </CommandTr>
                ))}
              </tbody>
            </CommandTable>
          )}
        </CommandCard>
      </div>

      <p className="text-xs text-zinc-600">
        <Package className="mr-1 inline h-3 w-3" />
        Aggregates only — no customer PII rendered on this page.
      </p>
    </div>
  )
}

function RiderRow({ label, value, color }: { label: string; value: number; color: 'green' | 'amber' | 'gray' }) {
  return (
    <div className="flex items-center justify-between rounded-lg border border-white/[0.06] px-3 py-2">
      <span className="flex items-center gap-2 text-sm text-zinc-300">
        <Bike className="h-4 w-4 text-zinc-500" /> {label}
      </span>
      <StatusChip color={color} label={String(value)} />
    </div>
  )
}

function MetricLine({
  icon: Icon,
  label,
  value,
  warn,
}: {
  icon: typeof Store
  label: string
  value: number
  warn?: boolean
}) {
  return (
    <div className="flex items-center justify-between">
      <span className="flex items-center gap-2 text-zinc-400">
        <Icon className="h-3.5 w-3.5" /> {label}
      </span>
      <span className={`font-medium tabular-nums ${warn ? 'text-red-400' : 'text-zinc-100'}`}>
        {value}
        {warn && <ArrowRight className="ml-1 inline h-3 w-3 rotate-45" />}
      </span>
    </div>
  )
}
