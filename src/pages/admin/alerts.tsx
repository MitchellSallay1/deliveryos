import { Link } from 'react-router-dom'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { Button } from '@/components/ui/Button'
import { usePlatformAlerts } from '@/hooks/use-admin-platform'
import { AdminHealthBadge } from '@/components/admin/AdminHealthBadge'

export function AdminAlertsPage() {
  const { data, isLoading } = usePlatformAlerts(true)
  const alerts = data?.alerts ?? []

  return (
    <Card>
      <CardHeader>
        <CardTitle>Alert center</CardTitle>
        <CardDescription>Conservative thresholds — only signals with database evidence.</CardDescription>
      </CardHeader>
      <CardContent>
        {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
        {!alerts.length && !isLoading && (
          <p className="text-sm text-[var(--color-muted)]">No active alerts.</p>
        )}
        <ul className="space-y-3">
          {alerts.map((a) => (
            <li key={a.title} className="flex items-center justify-between rounded-lg border p-3">
              <div>
                <AdminHealthBadge level={a.severity === 'critical' ? 'at_risk' : 'needs_attention'} />
                <p className="mt-1 font-medium">{a.title}</p>
                <p className="text-xs text-[var(--color-muted)]">{a.detail}</p>
              </div>
              <Link to={a.href}>
                <Button size="sm" variant="outline">
                  Open
                </Button>
              </Link>
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  )
}
