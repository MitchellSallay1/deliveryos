import { useEffect } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase/client'
import { fetchCustomerOrder, fetchCustomerOrders, fetchStoreBrief } from '@/services/customer-commerce-service'

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
