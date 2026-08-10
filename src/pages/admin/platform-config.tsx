import { CommandCard, CommandCardBody, CommandCardHeader, SectionHeader } from '@/components/admin/control-tower'

const JOBS = [
  { name: 'SMS dispatch', edge: 'sms-dispatch', note: 'Processes sms_outbox' },
  { name: 'Email dispatch', edge: 'email-dispatch', note: 'Processes email_outbox' },
  { name: 'Webhook dispatch', edge: 'webhooks-dispatch', note: 'Retries webhook_deliveries' },
  { name: 'Scheduler', edge: 'jobs-scheduler', note: 'Trial expiry, offer expiry, GPS purge' },
]

export function AdminJobsPage() {
  return (
    <div className="space-y-4">
      <SectionHeader eyebrow="Platform configuration" title="Scheduled jobs" className="mb-0" />
      <CommandCard>
        <CommandCardHeader description="Operational visibility is limited to queue counts until Edge Function telemetry is wired. Use System Health for pending/failed counts." />
        <CommandCardBody>
          <ul className="space-y-2">
            {JOBS.map((j) => (
              <li key={j.name} className="rounded-lg border border-white/[0.06] p-3 text-sm">
                <p className="font-medium text-zinc-100">{j.name}</p>
                <p className="text-xs text-zinc-500">
                  <span className="font-mono">{j.edge}</span> — {j.note}
                </p>
              </li>
            ))}
          </ul>
        </CommandCardBody>
      </CommandCard>
    </div>
  )
}

export function AdminConfigurationPage() {
  return (
    <div className="space-y-4">
      <SectionHeader eyebrow="Platform configuration" title="Configuration" className="mb-0" />
      <CommandCard>
        <CommandCardHeader description="Safe display settings only. Trial duration and feature gates remain database-driven via plans. Secrets are not editable here." />
        <CommandCardBody className="text-sm text-zinc-400">
          <p>Support contact and maintenance banner hooks can be added via the platform_settings table in a future migration.</p>
        </CommandCardBody>
      </CommandCard>
    </div>
  )
}
