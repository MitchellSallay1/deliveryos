import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { AdminHealthBadge } from '@/components/admin/AdminHealthBadge'
import { useExtendedHealth } from '@/hooks/use-admin-platform'

const MTN_SERVICES = ['mtn_sms', 'mtn_ussd', 'mtn_momo'] as const

export function AdminMtnIntegrationsPage() {
  const { data } = useExtendedHealth(true)

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle>MTN integration center</CardTitle>
          <CardDescription>
            Readiness surface only. Status reflects configuration evidence in the database — not live MTN API
            calls from this UI.
          </CardDescription>
        </CardHeader>
        <CardContent className="grid gap-4 sm:grid-cols-3">
          {MTN_SERVICES.map((key) => {
            const block = (data?.[key] ?? { status: 'not_configured' }) as { status: string }
            return (
              <div key={key} className="rounded-xl border p-4">
                <p className="text-sm font-medium uppercase">{key.replace(/_/g, ' ')}</p>
                <div className="mt-2">
                  <AdminHealthBadge level={block.status === 'healthy' ? 'healthy' : 'not_configured'} />
                </div>
                <p className="mt-2 text-xs text-[var(--color-muted)]">Credentials are never shown here.</p>
              </div>
            )
          })}
        </CardContent>
      </Card>
    </div>
  )
}
