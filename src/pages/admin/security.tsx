import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { useExtendedHealth } from '@/hooks/use-admin-platform'

export function AdminSecurityPage() {
  const { data, isLoading } = useExtendedHealth(true)

  return (
    <Card>
      <CardHeader>
        <CardTitle>Security center</CardTitle>
        <CardDescription>Events recorded in the platform — no synthetic threat scores.</CardDescription>
      </CardHeader>
      <CardContent>
        {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
        {data && (
          <dl className="space-y-3 text-sm">
            <div>
              <dt className="font-medium">API auth failures (24h)</dt>
              <dd className="tabular-nums">{String(data.api_auth_failures_24h ?? 0)}</dd>
            </div>
            <div>
              <dt className="font-medium">Webhook dead letter</dt>
              <dd>{String((data.webhook_dispatcher as Record<string, unknown>)?.dead ?? 0)}</dd>
            </div>
            <p className="text-xs text-[var(--color-muted)]">
              Privileged admin actions are stored in audit logs. Cross-tenant access attempts are blocked by RLS;
              surfaced here when logged.
            </p>
          </dl>
        )}
      </CardContent>
    </Card>
  )
}
