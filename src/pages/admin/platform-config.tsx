import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'

const JOBS = [
  { name: 'SMS dispatch', edge: 'sms-dispatch', note: 'Processes sms_outbox' },
  { name: 'Email dispatch', edge: 'email-dispatch', note: 'Processes email_outbox' },
  { name: 'Webhook dispatch', edge: 'webhooks-dispatch', note: 'Retries webhook_deliveries' },
  { name: 'Scheduler', edge: 'jobs-scheduler', note: 'Trial expiry, offer expiry, GPS purge' },
]

export function AdminJobsPage() {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Scheduled jobs</CardTitle>
        <CardDescription>
          Operational visibility is limited to queue counts until Edge Function telemetry is wired. Use System
          Health for pending/failed counts.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <ul className="space-y-3">
          {JOBS.map((j) => (
            <li key={j.name} className="rounded-lg border p-3 text-sm">
              <p className="font-medium">{j.name}</p>
              <p className="text-xs text-[var(--color-muted)]">{j.edge} — {j.note}</p>
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  )
}

export function AdminConfigurationPage() {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Platform configuration</CardTitle>
        <CardDescription>
          Safe display settings only. Trial duration and feature gates remain database-driven via plans. Secrets
          are not editable here.
        </CardDescription>
      </CardHeader>
      <CardContent className="text-sm text-[var(--color-muted)]">
        <p>Support contact and maintenance banner hooks can be added via platform_settings table in a future migration.</p>
      </CardContent>
    </Card>
  )
}
