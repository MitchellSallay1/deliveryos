import { Mail, MessageSquare, Radio, Send } from 'lucide-react'
import {
  CommandCard,
  CommandCardBody,
  CommandCardHeader,
  CommandKpi,
  MetricList,
  MetricRow,
  SectionHeader,
  StatusChip,
} from '@/components/admin/control-tower'
import { useCommunicationsSummary } from '@/hooks/use-admin-platform'

export function AdminCommunicationsPage() {
  const days = 7
  const { data, isLoading } = useCommunicationsSummary(days, true)
  const sms = (data?.sms ?? {}) as Record<string, number>
  const email = (data?.email ?? {}) as Record<string, number>
  const notifByChannel = (data?.notifications_by_channel ?? {}) as Record<string, number>

  return (
    <div className="space-y-8">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <SectionHeader eyebrow="Communications" title="Messaging & notifications" className="mb-0" />
        <p className="text-xs text-zinc-500">Window: last {days} days</p>
      </div>

      <CommandCard className="border-amber-400/20">
        <CommandCardBody className="flex flex-wrap items-center gap-3">
          <StatusChip color="gray" label="Awaiting MTN integration" />
          <p className="text-sm text-zinc-400">
            SMS delivery, USSD sessions, and phone OTP are not yet connected to a live carrier. Figures below reflect the
            provider-neutral outbox/log tables and will be zero or near-zero in production until MTN is integrated.
          </p>
        </CommandCardBody>
      </CommandCard>

      {isLoading && <p className="text-sm text-zinc-500">Loading…</p>}

      <div className="grid gap-4 lg:grid-cols-3">
        <CommandCard>
          <CommandCardHeader
            title={
              <span className="inline-flex items-center gap-1.5">
                <MessageSquare className="h-3.5 w-3.5 text-zinc-500" /> SMS
              </span>
            }
          />
          <CommandCardBody>
            <MetricList>
              <MetricRow label="Queued" value={sms.queued ?? 0} />
              <MetricRow label="Sent" value={sms.sent ?? 0} />
              <MetricRow label="Failed" value={sms.failed ?? 0} hint={Number(sms.failed) > 0 ? 'Needs attention' : undefined} />
              <MetricRow label="Inbound commands" value={sms.inbound_commands ?? 0} hint="USSD/SMS keyword replies" />
            </MetricList>
          </CommandCardBody>
        </CommandCard>

        <CommandCard>
          <CommandCardHeader
            title={
              <span className="inline-flex items-center gap-1.5">
                <Mail className="h-3.5 w-3.5 text-zinc-500" /> Email
              </span>
            }
          />
          <CommandCardBody>
            <MetricList>
              <MetricRow label="Pending" value={email.pending ?? 0} />
              <MetricRow label="Sent" value={email.sent ?? 0} />
            </MetricList>
          </CommandCardBody>
        </CommandCard>

        <CommandCard>
          <CommandCardHeader
            title={
              <span className="inline-flex items-center gap-1.5">
                <Send className="h-3.5 w-3.5 text-zinc-500" /> Delivery notifications
              </span>
            }
            description="By channel"
          />
          <CommandCardBody>
            {Object.keys(notifByChannel).length === 0 ? (
              <p className="text-sm text-zinc-500">No notifications sent in this window.</p>
            ) : (
              <MetricList>
                {Object.entries(notifByChannel).map(([channel, count]) => (
                  <MetricRow key={channel} label={channel} value={count} />
                ))}
              </MetricList>
            )}
          </CommandCardBody>
        </CommandCard>
      </div>

      <div className="grid gap-3 sm:grid-cols-2">
        <CommandKpi label="USSD sessions" value="Awaiting integration" icon={Radio} color="gray" />
        <CommandKpi label="Phone OTP delivery" value="Awaiting integration" icon={Radio} color="gray" />
      </div>
    </div>
  )
}
