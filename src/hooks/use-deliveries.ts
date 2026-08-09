import { useEffect } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase/client'
import {
  assignDeliveryRider,
  createDelivery,
  listCustomers,
  listDeliveries,
  listRiders,
  resendRiderJobSms,
  transitionDeliveryStatus,
} from '@/services/delivery-service'
import type { DeliveryListParams } from '@/types/delivery'
import type { DeliveryStatus } from '@/types/supabase'
import type { CreateDeliveryInput } from '@/utils/delivery-schemas'

export function useDeliveries(companyId: string | null, params: DeliveryListParams = {}) {
  const queryClient = useQueryClient()
  const page = params.page ?? 1
  const pageSize = params.pageSize ?? 25
  const search = params.search ?? ''

  const query = useQuery({
    queryKey: ['deliveries', companyId, page, pageSize, search],
    queryFn: () => listDeliveries(companyId!, { page, pageSize, search }),
    enabled: !!companyId,
    placeholderData: (prev) => prev,
  })

  useEffect(() => {
    if (!companyId) return

    const channel = supabase
      .channel(`deliveries:${companyId}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'deliveries',
          filter: `company_id=eq.${companyId}`,
        },
        () => {
          void queryClient.invalidateQueries({ queryKey: ['deliveries', companyId] })
        },
      )
      .subscribe()

    return () => {
      void supabase.removeChannel(channel)
    }
  }, [companyId, queryClient])

  return query
}

export function useRiders(companyId: string | null) {
  return useQuery({
    queryKey: ['riders', companyId],
    queryFn: () => listRiders(companyId!),
    enabled: !!companyId,
    staleTime: 60_000,
  })
}

export function useCustomers(companyId: string | null) {
  return useQuery({
    queryKey: ['customers', companyId],
    queryFn: () => listCustomers(companyId!),
    enabled: !!companyId,
    staleTime: 60_000,
  })
}

export function useCreateDelivery(companyId: string | null) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (input: CreateDeliveryInput) => createDelivery(companyId!, input),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['deliveries', companyId] })
      void queryClient.invalidateQueries({ queryKey: ['customers', companyId] })
      void queryClient.invalidateQueries({ queryKey: ['dashboard-today', companyId] })
      void queryClient.invalidateQueries({ queryKey: ['company-plan-usage', companyId] })
    },
  })
}

export function useAssignRider(companyId: string | null) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ deliveryId, riderId }: { deliveryId: string; riderId: string }) =>
      assignDeliveryRider(deliveryId, riderId),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['deliveries', companyId] })
    },
  })
}

export function useResendRiderJobSms(companyId: string | null) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (deliveryId: string) => resendRiderJobSms(deliveryId),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['deliveries', companyId] })
    },
  })
}

export function useTransitionDelivery(companyId: string | null) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({
      deliveryId,
      status,
      note,
    }: {
      deliveryId: string
      status: DeliveryStatus
      note?: string
    }) => transitionDeliveryStatus(deliveryId, status, note),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['deliveries', companyId] })
      void queryClient.invalidateQueries({ queryKey: ['dashboard-today', companyId] })
      void queryClient.invalidateQueries({ queryKey: ['company-payments', companyId] })
    },
  })
}
