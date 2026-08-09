import { PageHeader } from '@/components/ui/PageHeader'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { useAuth } from '@/hooks/use-auth'
import { useCompanyPlanUsage } from '@/hooks/use-riders'
import { useNotificationLogs, useSmsLogs } from '@/hooks/use-notifications'

export function NotificationsPage() {
  const { context } = useAuth()
  const companyId = context?.activeCompanyId ?? null

  const { data: plan } = useCompanyPlanUsage(companyId)
  const { data: smsLogs = [], isLoading: smsLoading, error: smsError } = useSmsLogs(companyId)
  const {
    data: notifLogs = [],
    isLoading: notifLoading,
    error: notifError,
  } = useNotificationLogs(companyId)

  if (!companyId) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Notifications</CardTitle>
          <CardDescription>Join a workspace to view SMS activity.</CardDescription>
        </CardHeader>
      </Card>
    )
  }

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader
        title="Notification center"
        description={`Outbound SMS uses 1 credit each · balance ${plan?.sms_credits ?? '—'}`}
      />

      <Card>
        <CardHeader>
          <CardTitle>How SMS works</CardTitle>
          <CardDescription>
            Assigning a delivery texts the rider. Status updates text the customer. Credits deduct
            in <code className="text-xs">queue_outbound_sms</code> (Postgres, not the browser).
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-2 text-sm text-[var(--color-muted)]">
          <p>
            Inbound rider replies: POST to Edge Function{' '}
            <code className="text-xs">/functions/v1/sms-inbound</code> with header{' '}
            <code className="text-xs">x-sms-secret</code> and JSON{' '}
            <code className="text-xs">{`{"from":"077…","text":"A"}`}</code>
          </p>
          <p>Keywords: A accept · P picked up · D delivered · F failed</p>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>SMS log</CardTitle>
        </CardHeader>
        <CardContent className="overflow-x-auto">
          {smsError && (
            <p className="text-sm text-red-600">
              {smsError instanceof Error ? smsError.message : 'Failed to load SMS log'}
            </p>
          )}
          {smsLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
          <LogTable
            rows={smsLogs.map((r) => ({
              id: r.id,
              when: r.created_at,
              dir: r.direction,
              to: r.phone,
              body: r.body,
              extra: r.credits_used ? `${r.credits_used} credit` : '',
            }))}
          />
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Notification log</CardTitle>
        </CardHeader>
        <CardContent className="overflow-x-auto">
          {notifError && (
            <p className="text-sm text-red-600">
              {notifError instanceof Error ? notifError.message : 'Failed to load'}
            </p>
          )}
          {notifLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
          <LogTable
            rows={notifLogs.map((r) => ({
              id: r.id,
              when: r.created_at,
              dir: r.channel,
              to: r.recipient,
              body: r.body,
              extra: r.status,
            }))}
          />
        </CardContent>
      </Card>
    </div>
  )
}

function LogTable({
  rows,
}: {
  rows: {
    id: string
    when: string
    dir: string
    to: string
    body: string
    extra: string
  }[]
}) {
  if (rows.length === 0) {
    return (
      <p className="py-4 text-center text-sm text-[var(--color-muted)]">
        No messages yet. Top up credits and assign a delivery.
      </p>
    )
  }

  return (
    <table className="w-full min-w-[640px] text-left text-sm">
      <thead>
        <tr className="border-b text-xs uppercase text-[var(--color-muted)]">
          <th className="py-2">When</th>
          <th className="py-2">Type</th>
          <th className="py-2">To</th>
          <th className="py-2">Meta</th>
          <th className="py-2">Body</th>
        </tr>
      </thead>
      <tbody>
        {rows.map((r) => (
          <tr key={r.id} className="border-b align-top">
            <td className="py-2 text-xs text-[var(--color-muted)]">{r.when}</td>
            <td className="py-2 capitalize">{r.dir}</td>
            <td className="py-2">{r.to}</td>
            <td className="py-2 text-xs">{r.extra}</td>
            <td className="max-w-md py-2 whitespace-pre-wrap text-xs">{r.body}</td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}
