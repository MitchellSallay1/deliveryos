import { Link } from 'react-router-dom'
import { AlertOctagon, ArrowRight } from 'lucide-react'
import { CommandCard, CommandCardBody, CommandCardHeader, SectionHeader, StatusChip } from '@/components/admin/control-tower'
import {
  ALERT_GROUP_LABELS,
  ALERT_GROUP_ORDER,
  groupAlertsBySeverity,
  type AlertGroupKey,
  type PlatformAlert,
} from '@/lib/admin-control-tower'
import { usePlatformAlerts } from '@/hooks/use-admin-platform'

const GROUP_COLOR: Record<AlertGroupKey, 'red' | 'amber' | 'gray'> = {
  critical: 'red',
  warning: 'amber',
  informational: 'gray',
}

export function AdminAlertsPage() {
  const { data, isLoading } = usePlatformAlerts(true)
  const alerts = (data?.alerts ?? []) as PlatformAlert[]
  const groups = groupAlertsBySeverity(alerts)

  return (
    <div className="space-y-8">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <SectionHeader
          eyebrow="Alert center"
          title="Platform alerts"
          className="mb-0"
        />
        <p className="text-xs text-zinc-500">Conservative thresholds — only signals with database evidence, refreshed every 60s.</p>
      </div>

      {isLoading && <p className="text-sm text-zinc-500">Loading…</p>}

      {!isLoading && alerts.length === 0 && (
        <CommandCard>
          <CommandCardBody className="flex items-center gap-3 py-8 text-center">
            <p className="w-full text-sm text-zinc-500">No active alerts. All monitored signals are within normal thresholds.</p>
          </CommandCardBody>
        </CommandCard>
      )}

      {ALERT_GROUP_ORDER.map((key) => {
        const items = groups[key]
        if (items.length === 0) return null
        return (
          <section key={key}>
            <SectionHeader
              eyebrow={`${ALERT_GROUP_LABELS[key]} (${items.length})`}
            />
            <div className="space-y-3">
              {items.map((a) => (
                <CommandCard key={a.title}>
                  <CommandCardHeader
                    title={
                      <span className="flex items-center gap-2">
                        <StatusChip color={GROUP_COLOR[key]} label={a.severity} />
                        {a.title}
                      </span>
                    }
                    action={
                      <Link
                        to={a.href}
                        className="inline-flex items-center gap-1 text-xs font-medium text-[#FFCB05] hover:underline"
                      >
                        Investigate <ArrowRight className="h-3 w-3" />
                      </Link>
                    }
                  />
                  <CommandCardBody className="space-y-2 text-sm">
                    <p className="text-zinc-300">{a.detail}</p>
                    <div className="flex flex-wrap gap-x-6 gap-y-1 text-xs text-zinc-500">
                      {a.entity && (
                        <span>
                          <span className="text-zinc-600">Affected: </span>
                          {a.entity}
                        </span>
                      )}
                      {a.suggested_action && (
                        <span className="flex items-center gap-1">
                          <AlertOctagon className="h-3 w-3" />
                          {a.suggested_action}
                        </span>
                      )}
                    </div>
                  </CommandCardBody>
                </CommandCard>
              ))}
            </div>
          </section>
        )
      })}
    </div>
  )
}
