import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  fetchCompanySettings,
  listCompanyPayments,
  markPaymentDeposited,
  updateCompanyRiderChannelSettings,
  updateCompanySettings,
  updateMyProfile,
} from '@/services/settings-service'

export function useCompanySettings(companyId: string | null) {
  return useQuery({
    queryKey: ['company-settings', companyId],
    queryFn: () => fetchCompanySettings(companyId!),
    enabled: !!companyId,
  })
}

export function useUpdateCompanySettings(companyId: string | null) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (patch: Parameters<typeof updateCompanySettings>[1]) =>
      updateCompanySettings(companyId!, patch),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['company-settings', companyId] })
      void queryClient.invalidateQueries({ queryKey: ['company-plan-usage', companyId] })
      void queryClient.invalidateQueries({ queryKey: ['auth-context'] })
    },
  })
}

export function useUpdateCompanyRiderChannels(companyId: string | null) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (settings: Parameters<typeof updateCompanyRiderChannelSettings>[1]) =>
      updateCompanyRiderChannelSettings(companyId!, settings),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['company-settings', companyId] })
    },
  })
}

export function useUpdateProfile() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: updateMyProfile,
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['auth-context'] })
    },
  })
}

export function useCompanyPayments(companyId: string | null) {
  return useQuery({
    queryKey: ['company-payments', companyId],
    queryFn: () => listCompanyPayments(companyId!),
    enabled: !!companyId,
  })
}

export function useMarkPaymentDeposited(companyId: string | null) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (paymentId: string) => markPaymentDeposited(paymentId),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['company-payments', companyId] })
    },
  })
}
