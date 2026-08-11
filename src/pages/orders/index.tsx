import { Link } from 'react-router-dom'
import { Badge } from '@/components/ui/Badge'
import { Card, CardContent } from '@/components/ui/Card'
import { PhoneOtpFlow } from '@/components/PhoneOtpFlow'
import { useAuth } from '@/hooks/use-auth'
import { useCustomerOrders } from '@/hooks/use-customer-orders'
import {
  orderFulfillmentStatusLabel,
  orderFulfillmentStatusVariant,
  orderPaymentStatusLabel,
  orderPaymentStatusVariant,
} from '@/lib/vendor-commerce-ui'
import { parseSupabaseError } from '@/lib/supabase-errors'
import { formatLrdFromCents } from '@/utils/delivery-schemas'

export function OrderHistoryPage() {
  const { user, loading: authLoading } = useAuth()
  const { data: orders = [], isLoading, error } = useCustomerOrders(user?.id)

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
              description="Verify your phone number to see your orders."
              onVerified={() => {}}
            />
          </CardContent>
        </Card>
      </div>
    )
  }

  return (
    <div className="mx-auto min-h-screen max-w-lg space-y-4 p-4 pb-10">
      <h1 className="text-xl font-semibold">Your orders</h1>

      {error && <p className="text-sm text-red-600">{parseSupabaseError(error)}</p>}
      {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
      {!isLoading && orders.length === 0 && <p className="text-sm text-[var(--color-muted)]">No orders yet.</p>}

      <ul className="space-y-3">
        {orders.map((order) => (
          <li key={order.id}>
            <Link to={`/orders/${order.id}`}>
              <Card>
                <CardContent className="space-y-2 pt-4">
                  <div className="flex items-center justify-between">
                    <span className="font-medium">{order.order_number}</span>
                    <span className="text-sm font-semibold tabular-nums">{formatLrdFromCents(order.total_lrd_cents)}</span>
                  </div>
                  <div className="flex flex-wrap gap-1.5">
                    <Badge variant={orderFulfillmentStatusVariant(order.fulfillment_status)}>
                      {orderFulfillmentStatusLabel(order.fulfillment_status)}
                    </Badge>
                    <Badge variant={orderPaymentStatusVariant(order.payment_status)}>
                      {orderPaymentStatusLabel(order.payment_status)}
                    </Badge>
                  </div>
                  <p className="text-xs text-[var(--color-muted)]">{new Date(order.created_at).toLocaleString()}</p>
                </CardContent>
              </Card>
            </Link>
          </li>
        ))}
      </ul>
    </div>
  )
}
