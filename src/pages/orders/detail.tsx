import { Link, useParams } from 'react-router-dom'
import { Badge } from '@/components/ui/Badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { PhoneOtpFlow } from '@/components/PhoneOtpFlow'
import { useAuth } from '@/hooks/use-auth'
import { useCustomerOrder, useStoreBrief } from '@/hooks/use-customer-orders'
import {
  orderFulfillmentStatusLabel,
  orderFulfillmentStatusVariant,
  orderPaymentStatusLabel,
  orderPaymentStatusVariant,
} from '@/lib/vendor-commerce-ui'
import { formatLrdFromCents } from '@/utils/delivery-schemas'

export function OrderDetailPage() {
  const { id } = useParams()
  const { user, loading: authLoading } = useAuth()
  const { data: order, isLoading, error } = useCustomerOrder(id, user?.id)
  const { data: store } = useStoreBrief(order?.vendor_company_id)

  if (authLoading) {
    return <div className="flex min-h-screen items-center justify-center text-sm text-[var(--color-muted)]">Loading…</div>
  }

  if (!user) {
    return (
      <div className="mx-auto flex min-h-screen max-w-md items-center p-4">
        <Card className="w-full">
          <CardContent className="pt-6">
            <PhoneOtpFlow
              title="Verify your phone"
              description="Verify your phone number to view this order."
              onVerified={() => {}}
            />
          </CardContent>
        </Card>
      </div>
    )
  }

  if (isLoading) {
    return <div className="flex min-h-screen items-center justify-center text-sm text-[var(--color-muted)]">Loading order…</div>
  }

  if (error || !order) {
    return (
      <div className="flex min-h-screen items-center justify-center p-6 text-center text-sm text-[var(--color-muted)]">
        Order not found.
      </div>
    )
  }

  return (
    <div className="mx-auto min-h-screen max-w-lg space-y-5 p-4 pb-10">
      <div>
        <Link to="/orders" className="text-sm text-[var(--color-muted)] hover:underline">
          ← Your orders
        </Link>
        <h1 className="mt-1 text-xl font-semibold">{order.order_number}</h1>
        <p className="text-sm text-[var(--color-muted)]">{store?.display_name ?? 'Store'}</p>
      </div>

      <div className="flex flex-wrap gap-2">
        <Badge variant={orderFulfillmentStatusVariant(order.fulfillment_status)}>
          {orderFulfillmentStatusLabel(order.fulfillment_status)}
        </Badge>
        <Badge variant={orderPaymentStatusVariant(order.payment_status)}>{orderPaymentStatusLabel(order.payment_status)}</Badge>
      </div>

      {order.payment_method === 'cod' && order.payment_status === 'pending_payment' && (
        <p className="rounded-md bg-amber-50 px-3 py-2 text-sm text-amber-800">
          Cash on Delivery — please have {formatLrdFromCents(order.total_lrd_cents)} ready when your order arrives.
        </p>
      )}
      {order.fulfillment_status === 'vendor_rejected' && (
        <p className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">
          This order was declined by the store{order.payment_status === 'refund_pending' ? ' — a refund is pending' : ''}.
        </p>
      )}

      <Card>
        <CardHeader>
          <CardTitle>Items</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          {order.items.map((item) => (
            <div key={item.id} className="flex justify-between text-sm">
              <span>
                {item.quantity}× {item.product_name}
                {item.selected_options.length > 0 && (
                  <span className="text-xs text-[var(--color-muted)]"> ({item.selected_options.map((o) => o.name).join(', ')})</span>
                )}
              </span>
              <span className="tabular-nums">{formatLrdFromCents(item.line_total_lrd_cents)}</span>
            </div>
          ))}
          <div className="flex justify-between border-t pt-2 text-sm">
            <span>Subtotal</span>
            <span className="tabular-nums">{formatLrdFromCents(order.subtotal_lrd_cents)}</span>
          </div>
          <div className="flex justify-between text-sm font-semibold">
            <span>Total</span>
            <span className="tabular-nums">{formatLrdFromCents(order.total_lrd_cents)}</span>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Delivery</CardTitle>
        </CardHeader>
        <CardContent className="space-y-1 text-sm">
          {order.delivery_area_summary && <p>{order.delivery_area_summary}</p>}
          {order.delivery_address && <p className="text-[var(--color-muted)]">{order.delivery_address}</p>}
          {order.delivery_instructions && <p className="text-[var(--color-muted)]">Note: {order.delivery_instructions}</p>}
          {!order.delivery_address && !order.delivery_area_summary && (
            <p className="text-[var(--color-muted)]">No delivery details provided.</p>
          )}
          <p className="pt-2 text-xs text-[var(--color-muted)]">
            {order.fulfillment_status === 'ready_for_pickup' || order.fulfillment_status === 'handed_to_carrier'
              ? 'Your order is being assigned for delivery.'
              : 'Delivery details will appear here once the store accepts your order.'}
          </p>
        </CardContent>
      </Card>

      <p className="text-center text-xs text-[var(--color-muted)]">Placed {new Date(order.created_at).toLocaleString()}</p>
    </div>
  )
}
