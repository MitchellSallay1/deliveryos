import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  listCustomersDetailed,
  updateCustomer,
  upsertCustomer,
} from '@/services/customer-service'
import type { CustomerInput } from '@/utils/customer-schemas'

export function useCustomersList(companyId: string | null) {
  return useQuery({
    queryKey: ['customers-detailed', companyId],
    queryFn: () => listCustomersDetailed(companyId!),
    enabled: !!companyId,
  })
}

export function useUpsertCustomer(companyId: string | null) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (input: CustomerInput) => upsertCustomer(companyId!, input),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['customers-detailed', companyId] })
      void queryClient.invalidateQueries({ queryKey: ['customers', companyId] })
    },
  })
}

export function useUpdateCustomer(companyId: string | null) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, input }: { id: string; input: CustomerInput }) =>
      updateCustomer(id, input),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['customers-detailed', companyId] })
      void queryClient.invalidateQueries({ queryKey: ['customers', companyId] })
    },
  })
}
