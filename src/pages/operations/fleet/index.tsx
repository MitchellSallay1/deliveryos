import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { useAuth } from '@/hooks/use-auth'
import { listVehiclesPage } from '@/services/operations-service'

export function FleetPage() {
  const companyId = useAuth().context?.activeCompanyId ?? null
  const [page, setPage] = useState(1)
  const [search, setSearch] = useState('')
  const { data, isLoading } = useQuery({
    queryKey: ['vehicles-page', companyId, page, search],
    queryFn: () => listVehiclesPage(companyId!, search, page),
    enabled: !!companyId,
  })
  const rows = (data?.rows ?? []) as Record<string, unknown>[]

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle>Fleet vehicles</CardTitle>
        </CardHeader>
        <CardContent>
          <Input
            className="mb-3 max-w-xs"
            placeholder="Search code"
            value={search}
            onChange={(e) => {
              setSearch(e.target.value)
              setPage(1)
            }}
          />
          {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
          <table className="w-full text-left text-sm">
            <thead>
              <tr className="border-b text-xs uppercase text-[var(--color-muted)]">
                <th className="py-2">Code</th>
                <th className="py-2">Type</th>
                <th className="py-2">Status</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((v) => (
                <tr key={String(v.id)} className="border-b">
                  <td className="py-2">
                    <Link className="text-[var(--color-primary)] underline" to={`/operations/fleet/${v.id}`}>
                      {String(v.vehicle_code)}
                    </Link>
                  </td>
                  <td className="py-2">{String(v.vehicle_type)}</td>
                  <td className="py-2 capitalize">{String(v.status)}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <div className="mt-2 flex gap-2">
            <Button size="sm" variant="outline" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>
              Previous
            </Button>
            <Button size="sm" variant="outline" onClick={() => setPage((p) => p + 1)}>
              Next
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
