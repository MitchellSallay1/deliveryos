import { useQuery } from '@tanstack/react-query'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { useAuth } from '@/hooks/use-auth'
import { listInventoryItems, listStock } from '@/services/operations-service'

export function InventoryPage() {
  const companyId = useAuth().context?.activeCompanyId ?? null
  const { data: items = [] } = useQuery({
    queryKey: ['inventory-items', companyId],
    queryFn: () => listInventoryItems(companyId!),
    enabled: !!companyId,
  })
  const { data: stock = [] } = useQuery({
    queryKey: ['inventory-stock', companyId],
    queryFn: () => listStock(companyId!),
    enabled: !!companyId,
  })

  return (
    <div className="grid gap-4 lg:grid-cols-2">
      <Card>
        <CardHeader>
          <CardTitle>Catalog</CardTitle>
        </CardHeader>
        <CardContent className="text-sm">
          <ul>
            {(items as { id: string; sku: string; name: string }[]).map((i) => (
              <li key={i.id} className="border-b py-2">
                {i.sku} · {i.name}
              </li>
            ))}
          </ul>
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>Stock levels</CardTitle>
        </CardHeader>
        <CardContent className="text-sm">
          <ul>
            {(stock as { quantity_on_hand: number; inventory_items: { name: string } | null }[]).map(
              (s, idx) => (
                <li key={idx} className="border-b py-2">
                  {s.inventory_items?.name ?? 'Item'} · on hand {s.quantity_on_hand}
                </li>
              ),
            )}
          </ul>
        </CardContent>
      </Card>
    </div>
  )
}
