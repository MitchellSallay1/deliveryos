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
    // Legacy keys (companies.tsx / index.tsx still use these hooks).
    void queryClient.invalidateQueries({ queryKey: ['admin-companies'] })
    void queryClient.invalidateQueries({ queryKey: ['platform-analytics'] })
    // Keys actually used by the rebuilt Company 360 page and command
    // center — without these, the page you're looking at when you click
    // Activate/Suspend/Top-up doesn't refresh (pre-existing bug).
    void queryClient.invalidateQueries({ queryKey: ['admin', 'company-360'] })
    void queryClient.invalidateQueries({ queryKey: ['admin', 'companies-page'] })
    void queryClient.invalidateQueries({ queryKey: ['admin', 'command-center'] })
    void queryClient.invalidateQueries({ queryKey: ['admin', 'alerts'] })
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
