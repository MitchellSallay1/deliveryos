import { useEffect } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase/client'
import { fetchLatestPaymentAttemptForOrder, fetchPaymentAttempt } from '@/services/customer-commerce-service'

/**
 * Watches one payment attempt by id via Realtime (same postgres_changes
 * idiom as useCustomerOrder in use-customer-orders.ts) rather than polling
 * on an interval — the attempt moves through created/requesting/pending/
 * successful/failed/unknown server-side (mtn-collect + the background
 * provider call), and this just picks up whatever the server decided, never
 * infers status itself. RLS (payment_attempts_select) already scopes this
 * to the paying customer or the vendor tenant.
 */
export function usePaymentAttempt(attemptId: string | undefined) {
  const queryClient = useQueryClient()

  const query = useQuery({
    queryKey: ['payment-attempt', attemptId],
    queryFn: () => fetchPaymentAttempt(attemptId!),
    enabled: !!attemptId,
    // Realtime is the primary update path; this is a safety-net poll in
    // case a websocket event is ever missed, and only while genuinely
    // unresolved (no point polling a terminal state).
    refetchInterval: (query) => {
      const state = query.state.data?.state
      return state && (state === 'successful' || state === 'failed') ? false : 4_000
    },
  })

  useEffect(() => {
    if (!attemptId) return

    const invalidate = () => void queryClient.invalidateQueries({ queryKey: ['payment-attempt', attemptId] })

    const channel = supabase
      .channel(`payment-attempt:${attemptId}`)
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'payment_attempts', filter: `id=eq.${attemptId}` }, invalidate)
      .subscribe()

    return () => {
      void supabase.removeChannel(channel)
    }
  }, [attemptId, queryClient])

  return query
}

/** Resolves the most recent attempt for an order — used to resume watching after a refresh/navigation with only the order id known. */
export function useLatestPaymentAttemptForOrder(orderId: string | undefined) {
  return useQuery({
    queryKey: ['latest-payment-attempt', orderId],
    queryFn: () => fetchLatestPaymentAttemptForOrder(orderId!),
    enabled: !!orderId,
  })
}
