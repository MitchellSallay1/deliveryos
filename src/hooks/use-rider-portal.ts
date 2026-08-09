import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  claimRiderProfile,
  fetchLinkedRiders,
  linkRiderAccount,
  listRiderActiveDeliveries,
  riderTransitionDelivery,
  setRiderUserId,
} from '@/services/rider-portal-service'
import type { DeliveryStatus } from '@/types/supabase'

export function useLinkedRiders(userId: string | undefined) {
  return useQuery({
    queryKey: ['linked-riders', userId],
    queryFn: () => fetchLinkedRiders(userId!),
    enabled: !!userId,
  })
}

export function useRiderJobs(riderId: string | null) {
  return useQuery({
    queryKey: ['rider-jobs', riderId],
    queryFn: () => listRiderActiveDeliveries(riderId!),
    enabled: !!riderId,
    refetchInterval: 30_000,
  })
}

export function useLinkRiderAccount() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: linkRiderAccount,
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['linked-riders'] })
      void queryClient.invalidateQueries({ queryKey: ['auth-context'] })
    },
  })
}

export function useClaimRider(companyId: string | null) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (riderCode: string) => claimRiderProfile(companyId!, riderCode),
    onSuccess: (_data, _vars, _ctx) => {
      void queryClient.invalidateQueries({ queryKey: ['linked-riders'] })
      void queryClient.invalidateQueries({ queryKey: ['riders-detailed', companyId] })
    },
  })
}

export function useSetRiderUser(companyId: string | null) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ riderId, userId }: { riderId: string; userId: string }) =>
      setRiderUserId(riderId, userId),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['linked-riders'] })
      void queryClient.invalidateQueries({ queryKey: ['riders-detailed', companyId] })
    },
  })
}

export function useRiderTransition(riderId: string | null) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ deliveryId, status }: { deliveryId: string; status: DeliveryStatus }) =>
      riderTransitionDelivery(deliveryId, status),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['rider-jobs', riderId] })
      void queryClient.invalidateQueries({ queryKey: ['deliveries'] })
    },
  })
}
