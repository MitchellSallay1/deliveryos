import { useState } from 'react'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { PageHeader } from '@/components/ui/PageHeader'
import { Badge } from '@/components/ui/Badge'
import { Tabs } from '@/components/ui/Tabs'
import { VendorGuard } from '@/components/vendor/VendorGuard'
import { useVendorContext } from '@/hooks/use-vendor-context'
import { useVendorOrderActions, useVendorOrders } from '@/hooks/use-vendor-commerce'
import { parseSupabaseError } from '@/lib/supabase-errors'
import { formatLrdFromCents } from '@/utils/delivery-schemas'
import {
  VENDOR_ORDER_TABS,
  availableOrderActions,
  orderFulfillmentStatusLabel,
  orderFulfillmentStatusVariant,
  orderPaymentStatusLabel,
  orderPaymentStatusVariant,
} from '@/lib/vendor-commerce-ui'
import type { VendorOrder } from '@/services/vendor-commerce-service'

/** Mask a phone number for the order list — full number is only ever needed for actual fulfillment contact, not a scan-through list. */
function maskedPhone(phone: string): string {
  if (phone.length <= 4) return phone
  return `${phone.slice(0, -4).replace(/\d/g, '•')}${phone.slice(-4)}`
}

function OrderCard({ order }: { order: VendorOrder }) {
  const { companyId } = useVendorContext()
  const { accept, reject, markPreparing, markReady, requestDelivery } = useVendorOrderActions(companyId)
  const [error, setError] = useState<string | null>(null)
  const [showPhone, setShowPhone] = useState(false)
  const actions = availableOrderActions(order.fulfillment_status, order.payment_status, order.payment_method)

  async function run(action: 'accept' | 'reject' | 'preparing' | 'ready' | 'request-delivery') {
    setError(null)
    try {
      if (action === 'accept') await accept.mutateAsync(order.id)
      if (action === 'reject') await reject.mutateAsync({ orderId: order.id })
      if (action === 'preparing') await markPreparing.mutateAsync(order.id)
      if (action === 'ready') await markReady.mutateAsync(order.id)
      if (action === 'request-delivery') await requestDelivery.mutateAsync(order.id)
    } catch (err) {
      setError(parseSupabaseError(err))
    }
  }

  const pending =
    accept.isPending || reject.isPending || markPreparing.isPending || markReady.isPending || requestDelivery.isPending

  return (
    <Card>
      <CardContent className="space-y-3 pt-6">
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div>
            <p className="font-semibold">{order.order_number}</p>
            <p className="text-xs text-[var(--color-muted)]">{new Date(order.created_at).toLocaleString()}</p>
          </div>
          <div className="flex flex-wrap gap-1.5">
            <Badge variant={orderFulfillmentStatusVariant(order.fulfillment_status)}>
              {orderFulfillmentStatusLabel(order.fulfillment_status)}
            </Badge>
            <Badge variant={orderPaymentStatusVariant(order.payment_status)}>
              {orderPaymentStatusLabel(order.payment_status)}
            </Badge>
            {order.delivery_status && <Badge variant="outline">Delivery: {order.delivery_status}</Badge>}
            {order.carrier_name && <Badge variant="outline">Carrier: {order.carrier_name}</Badge>}
          </div>
        </div>

        <div className="text-sm">
          <p className="font-medium">{order.customer_name}</p>
          <button
            type="button"
            className="text-xs text-[var(--color-primary)] hover:underline"
            onClick={() => setShowPhone((v) => !v)}
          >
            {showPhone ? order.customer_phone : maskedPhone(order.customer_phone)}
          </button>
          {order.delivery_address && (
            <p className="text-xs text-[var(--color-muted)]">{order.delivery_address}</p>
          )}
          {order.delivery_instructions && (
            <p className="text-xs text-[var(--color-muted)]">Note: {order.delivery_instructions}</p>
          )}
        </div>

        <ul className="space-y-1 border-t pt-2 text-sm">
          {order.items.map((item) => (
            <li key={item.id} className="flex justify-between">
              <span>
                {item.quantity}× {item.product_name}
                {item.selected_options.length > 0 && (
                  <span className="text-xs text-[var(--color-muted)]">
                    {' '}
                    ({item.selected_options.map((o) => o.name).join(', ')})
                  </span>
                )}
              </span>
              <span className="tabular-nums">{formatLrdFromCents(item.line_total_lrd_cents)}</span>
            </li>
          ))}
        </ul>
        <div className="flex justify-between border-t pt-2 text-sm font-semibold">
          <span>Subtotal</span>
          <span className="tabular-nums">{formatLrdFromCents(order.subtotal_lrd_cents)}</span>
        </div>

        {error && <p className="text-sm text-red-600">{error}</p>}

        {actions.length > 0 && (
          <div className="flex flex-wrap gap-2 border-t pt-3">
            {actions.includes('accept') && (
              <Button type="button" size="sm" disabled={pending} onClick={() => void run('accept')}>
                Accept order
              </Button>
            )}
            {actions.includes('reject') && (
              <Button type="button" size="sm" variant="destructive" disabled={pending} onClick={() => void run('reject')}>
                Reject
              </Button>
            )}
            {actions.includes('preparing') && (
              <Button type="button" size="sm" disabled={pending} onClick={() => void run('preparing')}>
                Mark preparing
              </Button>
            )}
            {actions.includes('ready') && (
              <Button type="button" size="sm" disabled={pending} onClick={() => void run('ready')}>
                Mark ready for pickup
              </Button>
            )}
          </div>
        )}
        {order.fulfillment_status === 'awaiting_vendor' && !actions.includes('accept') && (
          <p className="text-xs text-amber-700">Waiting on payment confirmation before this order can be accepted.</p>
        )}
        {order.fulfillment_status === 'awaiting_vendor' && order.payment_method === 'cod' && order.payment_status === 'pending_payment' && (
          <p className="text-xs text-[var(--color-muted)]">Cash on Delivery — collect payment when the order is delivered.</p>
        )}

        {order.fulfillment_status === 'ready_for_pickup' && !order.delivery_request_id && (
          <div className="border-t pt-3">
            <Button type="button" size="sm" disabled={pending} onClick={() => void run('request-delivery')}>
              Request delivery
            </Button>
            <p className="mt-1 text-xs text-[var(--color-muted)]">
              Sends this order to available delivery carriers using your store&apos;s pickup location.
            </p>
          </div>
        )}
        {order.delivery_request_id && !order.delivery_id && (
          <p className="border-t pt-3 text-xs text-[var(--color-muted)]">
            {order.pending_offers_count && order.pending_offers_count > 0
              ? `Delivery requested — ${order.pending_offers_count} carrier offer${order.pending_offers_count === 1 ? '' : 's'} available. Waiting for the customer to choose a carrier.`
              : 'Delivery requested — no carriers available yet.'}
          </p>
        )}
      </CardContent>
    </Card>
  )
}

function VendorOrdersContent() {
  const { companyId } = useVendorContext()
  const [tab, setTab] = useState('new')
  const [page, setPage] = useState(1)
  const activeTab = VENDOR_ORDER_TABS.find((t) => t.value === tab) ?? VENDOR_ORDER_TABS[0]
  const { data, isLoading, error } = useVendorOrders(companyId, activeTab.statuses, page)

  const rows = data?.rows ?? []
  const total = data?.total ?? 0
  const totalPages = Math.max(1, Math.ceil(total / 25))

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader title="Order inbox" description="Updates live via Supabase Realtime — no need to refresh." />

      <Tabs
        value={tab}
        onValueChange={(v) => {
          setTab(v)
          setPage(1)
        }}
        items={VENDOR_ORDER_TABS.map((t) => ({ value: t.value, label: t.label }))}
      />

      {error && <p className="text-sm text-red-600">{parseSupabaseError(error)}</p>}
      {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}

      {!isLoading && rows.length === 0 && (
        <Card>
          <CardHeader>
            <CardTitle>No orders here</CardTitle>
          </CardHeader>
          <CardContent className="text-sm text-[var(--color-muted)]">
            Nothing in {activeTab.label.toLowerCase()} right now.
          </CardContent>
        </Card>
      )}

      <div className="grid gap-4 lg:grid-cols-2">
        {rows.map((order) => (
          <OrderCard key={order.id} order={order} />
        ))}
      </div>

      {totalPages > 1 && (
        <div className="flex items-center justify-between text-sm">
          <span className="text-[var(--color-muted)]">Page {page} of {totalPages}</span>
          <div className="flex gap-2">
            <Button type="button" size="sm" variant="outline" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>
              Previous
            </Button>
            <Button type="button" size="sm" variant="outline" disabled={page >= totalPages} onClick={() => setPage((p) => p + 1)}>
              Next
            </Button>
          </div>
        </div>
      )}
    </div>
  )
}

export function VendorOrdersPage() {
  return (
    <VendorGuard>
      <VendorOrdersContent />
    </VendorGuard>
  )
}
