import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { regenerateRiderInviteCode } from '@/services/rider-portal-service'
import {
  createRider,
  fetchCompanyPlanUsage,
  listRidersDetailed,
  updateRiderAccess,
  updateRiderStatus,
} from '@/services/rider-service'
import type { RiderStatus } from '@/types/supabase'
import type { CreateRiderInput } from '@/utils/rider-schemas'

export function useRidersList(companyId: string | null) {
  return useQuery({
    queryKey: ['riders-detailed', companyId],
    queryFn: () => listRidersDetailed(companyId!),
    enabled: !!companyId,
  })
}

export function useCompanyPlanUsage(companyId: string | null) {
  return useQuery({
    queryKey: ['company-plan-usage', companyId],
    queryFn: () => fetchCompanyPlanUsage(companyId!),
    enabled: !!companyId,
  })
}

export function useCreateRider(companyId: string | null) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (input: CreateRiderInput) => createRider(companyId!, input),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['riders-detailed', companyId] })
      void queryClient.invalidateQueries({ queryKey: ['riders', companyId] })
      void queryClient.invalidateQueries({ queryKey: ['company-plan-usage', companyId] })
    },
  })
}

export function useRegenerateRiderInvite(companyId: string | null) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (riderId: string) => regenerateRiderInviteCode(riderId),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['riders-detailed', companyId] })
    },
  })
}

export function useUpdateRiderAccess(companyId: string | null) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({
      id,
      ...patch
    }: {
      id: string
      accessMode?: CreateRiderInput['accessMode']
      smsChannelEnabled?: boolean
      ussdChannelEnabled?: boolean
    }) => updateRiderAccess(id, patch),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['riders-detailed', companyId] })
      void queryClient.invalidateQueries({ queryKey: ['riders', companyId] })
    },
  })
}

export function useUpdateRiderStatus(companyId: string | null) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, status }: { id: string; status: RiderStatus }) =>
      updateRiderStatus(id, status),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['riders-detailed', companyId] })
      void queryClient.invalidateQueries({ queryKey: ['riders', companyId] })
    },
  })
}
