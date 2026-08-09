import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { useAuth } from '@/hooks/use-auth'
import {
  acceptMarketplaceOffer,
  getMarketplaceAnalytics,
  listMarketplaceJobsPage,
  rejectMarketplaceOffer,
} from '@/services/marketplace-service'

type JobRow = {
  offer_id: string
  offer_status: string
  quoted_amount_lrd_cents: number
  pickup_area_summary?: string
  destination_area_summary?: string
  fragile?: boolean
  cod_amount_lrd_cents?: number
}

export function MarketplaceJobsPage() {
  const { context } = useAuth()
  const companyId = context?.activeCompanyId
  const qc = useQueryClient()

  const { data, isLoading } = useQuery({
    queryKey: ['marketplace-jobs', companyId],
    queryFn: () => listMarketplaceJobsPage(companyId!),
    enabled: !!companyId,
  })

  const { data: analytics } = useQuery({
    queryKey: ['marketplace-analytics-provider', companyId],
    queryFn: () => getMarketplaceAnalytics('provider', companyId!),
    enabled: !!companyId,
  })

  const acceptMut = useMutation({
    mutationFn: (offerId: string) => acceptMarketplaceOffer(offerId, companyId!),
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['marketplace-jobs', companyId] }),
  })

  const rejectMut = useMutation({
    mutationFn: (offerId: string) => rejectMarketplaceOffer(offerId, companyId!),
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['marketplace-jobs', companyId] }),
  })

  const items = (data?.items ?? []) as JobRow[]

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-xl font-semibold">Marketplace jobs</h2>
        <p className="text-sm text-[var(--color-muted)]">
          Opportunities from merchants on the network. Customer details appear after you accept.
        </p>
      </div>

      {analytics && (
        <div className="grid gap-4 sm:grid-cols-2">
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium">Marketplace revenue</CardTitle>
            </CardHeader>
            <CardContent className="text-2xl font-semibold">
              LRD {Number(analytics.gmv_lrd_cents ?? 0) / 100}
            </CardContent>
          </Card>
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium">Acceptance rate</CardTitle>
            </CardHeader>
            <CardContent className="text-2xl font-semibold">
              {analytics.acceptance_rate != null
                ? `${(Number(analytics.acceptance_rate) * 100).toFixed(1)}%`
                : '—'}
            </CardContent>
          </Card>
        </div>
      )}

      <Card>
        <CardHeader>
          <CardTitle>Available jobs ({data?.total ?? 0})</CardTitle>
        </CardHeader>
        <CardContent>
          {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
          <ul className="divide-y">
            {items.map((job) => (
              <li key={job.offer_id} className="flex flex-wrap items-center justify-between gap-3 py-3">
                <div>
                  <p className="font-medium">
                    LRD {(job.quoted_amount_lrd_cents ?? 0) / 100} · {job.offer_status}
                  </p>
                  <p className="text-sm text-[var(--color-muted)]">
                    {job.pickup_area_summary ?? 'Pickup area'} →{' '}
                    {job.destination_area_summary ?? 'Destination area'}
                    {job.fragile ? ' · Fragile' : ''}
                  </p>
                </div>
                {job.offer_status === 'pending' && (
                  <div className="flex gap-2">
                    <Button size="sm" onClick={() => acceptMut.mutate(job.offer_id)}>
                      Accept
                    </Button>
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => rejectMut.mutate(job.offer_id)}
                    >
                      Decline
                    </Button>
                  </div>
                )}
              </li>
            ))}
          </ul>
        </CardContent>
      </Card>
    </div>
  )
}
