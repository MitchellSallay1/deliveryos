import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { useAuth } from '@/hooks/use-auth'
import {
  listMarketplaceProvidersPage,
  upsertMerchantProviderRelationship,
} from '@/services/marketplace-service'

type ProviderRow = {
  id: string
  name: string
  service_description?: string
  minimum_delivery_fee_lrd_cents?: number
  accepting_jobs?: boolean
  avg_rating?: number
}

export function MarketplaceProvidersPage() {
  const { context } = useAuth()
  const companyId = context?.activeCompanyId
  const qc = useQueryClient()

  const { data, isLoading } = useQuery({
    queryKey: ['marketplace-providers', companyId],
    queryFn: () => listMarketplaceProvidersPage(companyId!),
    enabled: !!companyId,
  })

  const preferMut = useMutation({
    mutationFn: (providerId: string) =>
      upsertMerchantProviderRelationship({
        merchant_company_id: companyId,
        provider_company_id: providerId,
        relationship_type: 'preferred',
      }),
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['marketplace-providers', companyId] }),
  })

  const items = (data?.items ?? []) as ProviderRow[]

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-xl font-semibold">Preferred providers</h2>
        <p className="text-sm text-[var(--color-muted)]">
          Opt-in delivery companies participating in the DeliveryOS marketplace.
        </p>
      </div>
      <Card>
        <CardHeader>
          <CardTitle>Directory ({data?.total ?? 0})</CardTitle>
        </CardHeader>
        <CardContent>
          {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
          <ul className="divide-y">
            {items.map((p) => (
              <li key={p.id} className="flex flex-wrap items-center justify-between gap-2 py-3">
                <div>
                  <p className="font-medium">{p.name}</p>
                  <p className="text-sm text-[var(--color-muted)]">
                    {p.service_description || 'No description'}
                    {p.avg_rating != null ? ` · ★ ${p.avg_rating}` : ''}
                  </p>
                </div>
                <Button size="sm" variant="outline" onClick={() => preferMut.mutate(p.id)}>
                  Mark preferred
                </Button>
              </li>
            ))}
          </ul>
        </CardContent>
      </Card>
    </div>
  )
}
