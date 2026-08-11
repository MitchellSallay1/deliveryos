import { useEffect } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase/client'
import {
  fetchCommerceOrderDeliveryStatus,
  fetchCustomerOrder,
  fetchCustomerOrders,
  fetchStoreBrief,
} from '@/services/customer-commerce-service'

/**
 * Realtime updates for a single order's fulfillment/payment status —
 * mirrors the exact pattern already used by useVendorOrders
 * (src/hooks/use-vendor-commerce.ts): a per-subject channel that
 * invalidates the query on any change, letting the next fetch pick up the
 * new row. RLS (customer_id = auth.uid()) already scopes what this
 * customer's realtime subscription can receive — no new grant needed.
 */
export function useCustomerOrder(orderId: string | undefined, customerId: string | undefined) {
  const queryClient = useQueryClient()

  const query = useQuery({
    queryKey: ['customer-order', orderId, customerId],
    queryFn: () => fetchCustomerOrder(orderId!, customerId!),
    enabled: !!orderId && !!customerId,
  })

  useEffect(() => {
    if (!orderId) return

    const invalidate = () => void queryClient.invalidateQueries({ queryKey: ['customer-order', orderId, customerId] })

    const channel = supabase
      .channel(`customer-commerce-order:${orderId}`)
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'commerce_orders', filter: `id=eq.${orderId}` }, invalidate)
      .subscribe()

    return () => {
      void supabase.removeChannel(channel)
    }
  }, [orderId, customerId, queryClient])

  return query
}

export function useStoreBrief(companyId: string | undefined) {
  return useQuery({
    queryKey: ['store-brief', companyId],
    queryFn: () => fetchStoreBrief(companyId!),
    enabled: !!companyId,
    staleTime: 60_000,
  })
}

export function useCustomerOrders(customerId: string | undefined) {
  return useQuery({
    queryKey: ['customer-orders', customerId],
    queryFn: () => fetchCustomerOrders(customerId!),
    enabled: !!customerId,
  })
}

/**
 * Carrier options + delivery/rider status for one order. Reuses the same
 * invalidate-on-postgres_changes idiom as useCustomerOrder/useVendorOrders.
 * Three subscriptions, each keyed on a value known at a different point:
 * commerce_orders (known immediately — fires when a delivery is requested
 * or a carrier accepts), deliveries (known immediately — filters on
 * commerce_order_id, which simply matches nothing until a delivery exists),
 * and delivery_offers (only knowable once the first fetch reveals the
 * linked delivery_request_id, so that subscription is (re)established once
 * that id is available).
 */
export function useCommerceOrderDeliveryStatus(orderId: string | undefined) {
  const queryClient = useQueryClient()

  const query = useQuery({
    queryKey: ['commerce-order-delivery-status', orderId],
    queryFn: () => fetchCommerceOrderDeliveryStatus(orderId!),
    enabled: !!orderId,
  })

  const requestId = query.data?.delivery_request?.id

  useEffect(() => {
    if (!orderId) return

    const invalidate = () => void queryClient.invalidateQueries({ queryKey: ['commerce-order-delivery-status', orderId] })

    const channel = supabase
      .channel(`customer-commerce-delivery:${orderId}`)
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'commerce_orders', filter: `id=eq.${orderId}` }, invalidate)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'deliveries', filter: `commerce_order_id=eq.${orderId}` }, invalidate)
      .subscribe()

    return () => {
      void supabase.removeChannel(channel)
    }
  }, [orderId, queryClient])

  useEffect(() => {
    if (!requestId) return

    const invalidate = () => void queryClient.invalidateQueries({ queryKey: ['commerce-order-delivery-status', orderId] })

    const channel = supabase
      .channel(`customer-commerce-offers:${requestId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'delivery_offers', filter: `delivery_request_id=eq.${requestId}` },
        invalidate,
      )
      .subscribe()

    return () => {
      void supabase.removeChannel(channel)
    }
  }, [requestId, orderId, queryClient])

  return query
}
