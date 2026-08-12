import { useQuery } from '@tanstack/react-query'
import {
  fetchCommerceOrdersSummary,
  fetchCommerceReconciliationGaps,
  listCommerceOrdersPage,
  listCommerceProvidersPage,
} from '@/services/commerce-admin-service'

export function useCommerceOrdersSummary(stuckAfterHours = 24) {
  return useQuery({
    queryKey: ['admin-commerce-orders-summary', stuckAfterHours],
    queryFn: () => fetchCommerceOrdersSummary(stuckAfterHours),
  })
}

export function useCommerceOrdersPage(params: {
  fulfillmentStatuses?: string[]
  stuckOnly?: boolean
  stuckAfterHours?: number
  search?: string
  page: number
  pageSize?: number
}) {
  const pageSize = params.pageSize ?? 25
  return useQuery({
    queryKey: [
      'admin-commerce-orders',
      params.fulfillmentStatuses,
      params.stuckOnly,
      params.stuckAfterHours,
      params.search,
      params.page,
    ],
    queryFn: () =>
      listCommerceOrdersPage({
        fulfillmentStatuses: params.fulfillmentStatuses,
        stuckOnly: params.stuckOnly,
        stuckAfterHours: params.stuckAfterHours,
        search: params.search,
        limit: pageSize,
        offset: (params.page - 1) * pageSize,
      }),
  })
}

export function useCommerceProvidersPage(params: { search?: string; page: number; pageSize?: number }) {
  const pageSize = params.pageSize ?? 25
  return useQuery({
    queryKey: ['admin-commerce-providers', params.search, params.page],
    queryFn: () =>
      listCommerceProvidersPage({ search: params.search, limit: pageSize, offset: (params.page - 1) * pageSize }),
  })
}

export function useCommerceReconciliationGaps() {
  return useQuery({
    queryKey: ['admin-commerce-reconciliation-gaps'],
    queryFn: () => fetchCommerceReconciliationGaps(50),
  })
}
