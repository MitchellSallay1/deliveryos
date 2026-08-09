import { useQuery } from '@tanstack/react-query'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { useAuth } from '@/hooks/use-auth'
import { listWarehouses } from '@/services/operations-service'

export function WarehousesPage() {
  const companyId = useAuth().context?.activeCompanyId ?? null
  const { data = [], isLoading } = useQuery({
    queryKey: ['warehouses', companyId],
    queryFn: () => listWarehouses(companyId!),
    enabled: !!companyId,
  })

  return (
    <Card>
      <CardHeader>
        <CardTitle>Warehouses</CardTitle>
      </CardHeader>
      <CardContent className="text-sm">
        {isLoading && <p className="text-[var(--color-muted)]">Loading…</p>}
        <ul>
          {(data as { id: string; name: string; code: string }[]).map((w) => (
            <li key={w.id} className="border-b py-2">
              {w.name} · {w.code}
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  )
}
