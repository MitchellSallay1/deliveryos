import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  adminTopUpSms,
  fetchPlatformAnalytics,
  listAllCompanies,
  setCompanyStatus,
} from '@/services/admin-service'

export function usePlatformAnalytics(enabled: boolean) {
  return useQuery({
    queryKey: ['platform-analytics'],
    queryFn: fetchPlatformAnalytics,
    enabled,
  })
}

export function useAdminCompanies(enabled: boolean) {
  return useQuery({
    queryKey: ['admin-companies'],
    queryFn: listAllCompanies,
    enabled,
  })
}

export function useAdminCompanyActions() {
  const queryClient = useQueryClient()
  const invalidate = () => {
    void queryClient.invalidateQueries({ queryKey: ['admin-companies'] })
    void queryClient.invalidateQueries({ queryKey: ['platform-analytics'] })
  }

  const statusMutation = useMutation({
    mutationFn: ({ id, status }: { id: string; status: 'pending' | 'active' | 'suspended' }) =>
      setCompanyStatus(id, status),
    onSuccess: invalidate,
  })

  const smsMutation = useMutation({
    mutationFn: ({ id, amount }: { id: string; amount: number }) => adminTopUpSms(id, amount),
    onSuccess: invalidate,
  })

  return { statusMutation, smsMutation }
}
