import { useQuery } from '@tanstack/react-query'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { useAuth } from '@/hooks/use-auth'
import { listMovements } from '@/services/operations-service'

export function InventoryMovementsPage() {
  const companyId = useAuth().context?.activeCompanyId ?? null
  const { data = [], isLoading } = useQuery({
    queryKey: ['inventory-movements', companyId],
    queryFn: () => listMovements(companyId!),
    enabled: !!companyId,
  })

  return (
    <Card>
      <CardHeader>
        <CardTitle>Inventory movements</CardTitle>
      </CardHeader>
      <CardContent className="text-sm">
        {isLoading && <p className="text-[var(--color-muted)]">Loading…</p>}
        <ul>
          {(data as { id: string; movement_type: string; quantity: number; created_at: string }[]).map(
            (m) => (
              <li key={m.id} className="border-b py-2">
                {m.movement_type} · qty {m.quantity} · {new Date(m.created_at).toLocaleString()}
              </li>
            ),
          )}
        </ul>
      </CardContent>
    </Card>
  )
}
