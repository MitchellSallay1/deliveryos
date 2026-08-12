import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { useAuth } from '@/hooks/use-auth'
import { OnboardingProgressStrip } from '@/components/dashboard/OnboardingProgressStrip'
import {
  cancelDeliveryRequest,
  createDeliveryRequest,
  getMarketplaceAnalytics,
  listDeliveryRequestsPage,
  publishDeliveryRequest,
} from '@/services/marketplace-service'

export function MerchantRequestsPage() {
  const { context } = useAuth()
  const companyId = context?.activeCompanyId
  const qc = useQueryClient()
  const [formOpen, setFormOpen] = useState(false)

  const { data: list, isLoading } = useQuery({
    queryKey: ['delivery-requests', companyId],
    queryFn: () => listDeliveryRequestsPage(companyId!),
    enabled: !!companyId,
  })

  const { data: analytics } = useQuery({
    queryKey: ['marketplace-analytics-merchant', companyId],
    queryFn: () => getMarketplaceAnalytics('merchant', companyId!),
    enabled: !!companyId,
  })

  const createMut = useMutation({
    mutationFn: async (fd: FormData) => {
      const row = await createDeliveryRequest({
        merchant_company_id: companyId,
        pickup_address: String(fd.get('pickup_address')),
        pickup_area_summary: String(fd.get('pickup_area_summary') || ''),
        destination_address: String(fd.get('destination_address')),
        destination_area_summary: String(fd.get('destination_area_summary') || ''),
        customer_name: String(fd.get('customer_name')),
        customer_phone: String(fd.get('customer_phone')),
        package_description: String(fd.get('package_description') || ''),
        cod_amount_lrd_cents: Math.round(Number(fd.get('cod_lrd') || 0) * 100),
        quoted_amount_lrd_cents: Math.round(Number(fd.get('quoted_lrd') || 0) * 100),
        fragile: fd.get('fragile') === 'on',
        status: 'draft',
        selected_provider_id: String(fd.get('provider_id') || '') || null,
      })
      const id = (row as { id: string }).id
      await publishDeliveryRequest(id, companyId!)
      return row
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['delivery-requests', companyId] })
      setFormOpen(false)
    },
  })

  const cancelMut = useMutation({
    mutationFn: (id: string) => cancelDeliveryRequest(id, companyId!, 'Merchant cancelled'),
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['delivery-requests', companyId] }),
  })

  const items = (list?.items ?? []) as Record<string, unknown>[]

  return (
    <div className="space-y-6">
      {companyId && <OnboardingProgressStrip companyId={companyId} />}

      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="text-xl font-semibold">Delivery requests</h2>
          <p className="text-sm text-[var(--color-muted)]">
            Request external delivery providers on the DeliveryOS network.
          </p>
        </div>
        <Button onClick={() => setFormOpen((v) => !v)}>
          {formOpen ? 'Close form' : 'Create external request'}
        </Button>
      </div>

      {analytics && (
        <div className="grid gap-4 sm:grid-cols-3">
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium">Spend (GMV)</CardTitle>
            </CardHeader>
            <CardContent className="text-2xl font-semibold">
              LRD {Number(analytics.gmv_lrd_cents ?? 0) / 100}
            </CardContent>
          </Card>
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium">Open requests</CardTitle>
            </CardHeader>
            <CardContent className="text-2xl font-semibold">
              {String(analytics.open_requests ?? 0)}
            </CardContent>
          </Card>
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium">Completed</CardTitle>
            </CardHeader>
            <CardContent className="text-2xl font-semibold">
              {String(analytics.completed_conversions ?? 0)}
            </CardContent>
          </Card>
        </div>
      )}

      {formOpen && (
        <Card>
          <CardHeader>
            <CardTitle>New external delivery request</CardTitle>
          </CardHeader>
          <CardContent>
            <form
              className="grid max-w-xl gap-3"
              onSubmit={(e) => {
                e.preventDefault()
                createMut.mutate(new FormData(e.currentTarget))
              }}
            >
              <div className="space-y-2">
                <Label>Pickup address</Label>
                <Input name="pickup_address" required />
              </div>
              <div className="space-y-2">
                <Label>Pickup area (shown to providers pre-acceptance)</Label>
                <Input name="pickup_area_summary" placeholder="e.g. Sinkor, Monrovia" />
              </div>
              <div className="space-y-2">
                <Label>Destination address</Label>
                <Input name="destination_address" required />
              </div>
              <div className="space-y-2">
                <Label>Destination area summary</Label>
                <Input name="destination_area_summary" />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-2">
                  <Label>Customer name</Label>
                  <Input name="customer_name" required />
                </div>
                <div className="space-y-2">
                  <Label>Customer phone</Label>
                  <Input name="customer_phone" required />
                </div>
              </div>
              <div className="space-y-2">
                <Label>Package description</Label>
                <Input name="package_description" />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-2">
                  <Label>Quoted delivery fee (LRD)</Label>
                  <Input name="quoted_lrd" type="number" min={0} step="0.01" required />
                </div>
                <div className="space-y-2">
                  <Label>COD amount (LRD)</Label>
                  <Input name="cod_lrd" type="number" min={0} step="0.01" />
                </div>
              </div>
              <label className="flex items-center gap-2 text-sm">
                <input type="checkbox" name="fragile" /> Fragile
              </label>
              {createMut.isError && (
                <p className="text-sm text-red-600">{String(createMut.error)}</p>
              )}
              <Button type="submit" disabled={createMut.isPending}>
                {createMut.isPending ? 'Publishing…' : 'Publish to network'}
              </Button>
            </form>
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader>
          <CardTitle>Requests ({list?.total ?? 0})</CardTitle>
        </CardHeader>
        <CardContent>
          {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
          {!isLoading && items.length === 0 && (
            <p className="text-sm text-[var(--color-muted)]">No delivery requests yet.</p>
          )}
          <ul className="divide-y">
            {items.map((r) => (
              <li key={String(r.id)} className="flex flex-wrap items-center justify-between gap-2 py-3">
                <div>
                  <p className="font-medium">{String(r.status)}</p>
                  <p className="text-sm text-[var(--color-muted)]">
                    {String(r.pickup_area_summary || r.pickup_address)} →{' '}
                    {String(r.destination_area_summary || r.destination_address)}
                  </p>
                </div>
                {['draft', 'open', 'offered'].includes(String(r.status)) && (
                  <Button
                    variant="outline"
                    size="sm"
                    disabled={cancelMut.isPending}
                    onClick={() => cancelMut.mutate(String(r.id))}
                  >
                    Cancel
                  </Button>
                )}
              </li>
            ))}
          </ul>
        </CardContent>
      </Card>
    </div>
  )
}
