import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { AdminHealthBadge } from '@/components/admin/AdminHealthBadge'
import { useExtendedHealth } from '@/hooks/use-admin-platform'

function statusBlock(label: string, block: unknown) {
  const b = (block ?? { status: 'not_configured' }) as { status?: string; pending?: number; note?: string }
  const level = b.status ?? 'not_configured'
  return (
    <div className="rounded-xl border p-4">
      <p className="text-sm font-medium">{label}</p>
      <div className="mt-2">
        <AdminHealthBadge level={level === 'healthy' ? 'healthy' : level === 'degraded' ? 'degraded' : 'not_configured'} />
      </div>
      {b.pending != null && <p className="mt-2 text-xs text-[var(--color-muted)]">Pending/failed: {b.pending}</p>}
      {b.note && <p className="mt-1 text-xs text-[var(--color-muted)]">{b.note}</p>}
    </div>
  )
}

export function AdminSystemStatusPage() {
  const { data, isLoading, error } = useExtendedHealth(true)

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle>Platform health</CardTitle>
          <CardDescription>
            Unverified integrations stay not configured. Queue depth indicates worker backlog — not external SLA.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
          {error && (
            <p className="text-sm text-red-600">{error instanceof Error ? error.message : 'Failed'}</p>
          )}
          {data && (
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {statusBlock('Database', data.database)}
              {statusBlock('Auth', data.auth)}
              {statusBlock('SMS worker', data.sms_worker)}
              {statusBlock('Webhook dispatcher', data.webhook_dispatcher)}
              {statusBlock('Email worker', data.email_worker)}
              {statusBlock('MTN SMS', data.mtn_sms)}
              {statusBlock('MTN USSD', data.mtn_ussd)}
              {statusBlock('MTN MoMo', data.mtn_momo)}
            </div>
          )}
          <p className="mt-4 text-xs text-[var(--color-muted)]">
            Edge functions: jobs-scheduler, sms-dispatch, webhooks-dispatch, email-dispatch
          </p>
        </CardContent>
      </Card>
    </div>
  )
}
