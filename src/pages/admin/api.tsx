import { useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { useAdminApiKeysPage } from '@/hooks/use-admin-platform'
import { useExtendedHealth } from '@/hooks/use-admin-platform'
import { Button } from '@/components/ui/Button'

const PAGE = 25

export function AdminApiPage() {
  const [page, setPage] = useState(1)
  const { data, isLoading } = useAdminApiKeysPage({ limit: PAGE, offset: (page - 1) * PAGE }, true)
  const { data: health } = useExtendedHealth(true)
  const rows = data?.rows ?? []
  const total = data?.total ?? 0

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>API auth (24h)</CardTitle>
        </CardHeader>
        <CardContent className="text-sm">
          Failed auth events: <strong>{String(health?.api_auth_failures_24h ?? '—')}</strong>
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>API keys (metadata only)</CardTitle>
        </CardHeader>
        <CardContent>
          {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
          <table className="w-full text-left text-sm">
            <thead>
              <tr className="border-b text-xs uppercase text-[var(--color-muted)]">
                <th className="py-2">Company</th>
                <th className="py-2">Name</th>
                <th className="py-2">Prefix</th>
                <th className="py-2">Active</th>
                <th className="py-2">Last used</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={String(r.id)} className="border-b">
                  <td className="py-2">{String(r.company_name)}</td>
                  <td className="py-2">{String(r.name)}</td>
                  <td className="py-2 font-mono text-xs">{String(r.key_prefix)}</td>
                  <td className="py-2">{String(r.is_active)}</td>
                  <td className="py-2 text-xs">{String(r.last_used_at ?? '—')}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <p className="mt-2 text-xs text-[var(--color-muted)]">{total} keys</p>
          <div className="mt-2 flex gap-2">
            <Button size="sm" variant="outline" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>
              Previous
            </Button>
            <Button size="sm" variant="outline" disabled={page * PAGE >= total} onClick={() => setPage((p) => p + 1)}>
              Next
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
