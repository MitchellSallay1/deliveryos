import { useMemo, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { Button } from '@/components/ui/Button'
import { Sheet } from '@/components/ui/Sheet'
import { useAdminDeliveriesPage, useAdminDeliveryDetail } from '@/hooks/use-admin-platform'

const PAGE = 25

export function AdminDeliveriesPage() {
  const [params, setParams] = useSearchParams()
  const code = params.get('code') ?? ''
  const [tracking, setTracking] = useState(code)
  const [page, setPage] = useState(1)
  const [selectedId, setSelectedId] = useState<string | null>(null)

  const query = useMemo(
    () => ({ trackingCode: tracking || undefined, limit: PAGE, offset: (page - 1) * PAGE }),
    [tracking, page],
  )
  const { data, isLoading } = useAdminDeliveriesPage(query, true)
  const rows = data?.rows ?? []
  const total = data?.total ?? 0

  const detail = useAdminDeliveryDetail(selectedId ?? undefined, !!selectedId)

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle>Platform deliveries</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="mb-4 flex flex-wrap gap-2">
            <Input
              className="max-w-xs"
              placeholder="Tracking code"
              value={tracking}
              onChange={(e) => setTracking(e.target.value)}
            />
            <Button
              size="sm"
              onClick={() => {
                setPage(1)
                if (tracking) setParams({ code: tracking })
              }}
            >
              Search
            </Button>
          </div>
          {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
          <div className="overflow-x-auto">
            <table className="w-full min-w-[720px] text-left text-sm">
              <thead>
                <tr className="border-b text-xs uppercase text-[var(--color-muted)]">
                  <th className="py-2">Tracking</th>
                  <th className="py-2">Company</th>
                  <th className="py-2">Status</th>
                  <th className="py-2">Customer</th>
                  <th className="py-2">Created</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr
                    key={String(r.id)}
                    className="cursor-pointer border-b hover:bg-zinc-50"
                    onClick={() => setSelectedId(String(r.id))}
                  >
                    <td className="py-2 font-mono text-xs">{String(r.tracking_code)}</td>
                    <td className="py-2">{String(r.company_name)}</td>
                    <td className="py-2 capitalize">{String(r.status)}</td>
                    <td className="py-2">{String(r.customer_name)}</td>
                    <td className="py-2 text-xs">{String(r.created_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="mt-2 text-xs text-[var(--color-muted)]">
            {total} deliveries · page {page}
          </p>
          <div className="mt-2 flex gap-2">
            <Button size="sm" variant="outline" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>
              Previous
            </Button>
            <Button
              size="sm"
              variant="outline"
              disabled={page * PAGE >= total}
              onClick={() => setPage((p) => p + 1)}
            >
              Next
            </Button>
          </div>
        </CardContent>
      </Card>

      <Sheet
        open={!!selectedId}
        onClose={() => setSelectedId(null)}
        title="Delivery inspection"
      >
        {detail.isLoading && <p className="text-sm text-[var(--color-muted)]">Loading detail…</p>}
        {detail.data && (
          <pre className="max-h-[70vh] overflow-auto rounded-lg bg-zinc-50 p-3 text-xs">
            {JSON.stringify(detail.data, null, 2)}
          </pre>
        )}
      </Sheet>
    </div>
  )
}
