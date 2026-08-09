import { useState } from 'react'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { useAuditLogsAdmin } from '@/hooks/use-admin-platform'

export function AdminAuditPage() {
  const [page, setPage] = useState(1)
  const [action, setAction] = useState('')
  const [actionFilter, setActionFilter] = useState<string | undefined>()
  const { data, isLoading } = useAuditLogsAdmin(
    { action: actionFilter, limit: 25, offset: (page - 1) * 25 },
    true,
  )
  const rows = data?.rows ?? []
  const total = data?.total ?? 0

  return (
    <Card>
      <CardHeader>
        <CardTitle>Platform audit log</CardTitle>
      </CardHeader>
      <CardContent>
        <div className="mb-3 flex max-w-md gap-2">
          <Input placeholder="Filter action" value={action} onChange={(e) => setAction(e.target.value)} />
          <Button
            size="sm"
            onClick={() => {
              setActionFilter(action.trim() || undefined)
              setPage(1)
            }}
          >
            Filter
          </Button>
        </div>
        {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
        <table className="w-full text-left text-sm">
          <thead>
            <tr className="border-b text-xs uppercase text-[var(--color-muted)]">
              <th className="py-2">When</th>
              <th className="py-2">Actor</th>
              <th className="py-2">Action</th>
              <th className="py-2">Entity</th>
              <th className="py-2">Company</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={String(r.id)} className="border-b">
                <td className="py-2 text-xs">{String(r.created_at)}</td>
                <td className="py-2 text-xs">{String(r.actor_name ?? r.actor_user_id ?? '—')}</td>
                <td className="py-2">{String(r.action)}</td>
                <td className="py-2 text-xs">
                  {String(r.entity_type)} {String(r.entity_id ?? '')}
                </td>
                <td className="py-2 text-xs font-mono">{String(r.company_id ?? '—')}</td>
              </tr>
            ))}
          </tbody>
        </table>
        <p className="mt-2 text-xs text-[var(--color-muted)]">{total} events · page {page}</p>
        <div className="mt-2 flex gap-2">
          <Button size="sm" variant="outline" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>
            Previous
          </Button>
          <Button size="sm" variant="outline" disabled={page * 25 >= total} onClick={() => setPage((p) => p + 1)}>
            Next
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}
