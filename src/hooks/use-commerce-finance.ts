import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  adminCreateCommerceSettlement,
  adminListCommerceFinancialEvents,
  adminMarkSettlementCompleted,
  adminMarkSettlementFailed,
  adminMarkSettlementProcessing,
  adminRecordSettlementReference,
  adminReverseSettlement,
  adminUpsertCommerceFeeRule,
  fetchAdminCommerceFinanceOverview,
  fetchCarrierCommerceFinance,
  fetchCommerceFeeRules,
  fetchVendorCommerceFinance,
  listCommerceSettlements,
  type CommerceSettlementPayeeType,
  type CommerceSettlementStatus,
} from '@/services/commerce-finance-service'

export function useVendorCommerceFinance(vendorCompanyId: string | null) {
  return useQuery({
    queryKey: ['vendor-commerce-finance', vendorCompanyId],
    queryFn: () => fetchVendorCommerceFinance(vendorCompanyId!),
    enabled: !!vendorCompanyId,
  })
}

export function useCarrierCommerceFinance(carrierCompanyId: string | null) {
  return useQuery({
    queryKey: ['carrier-commerce-finance', carrierCompanyId],
    queryFn: () => fetchCarrierCommerceFinance(carrierCompanyId!),
    enabled: !!carrierCompanyId,
  })
}

export function useCommerceSettlements(params: {
  payeeType?: CommerceSettlementPayeeType
  payeeCompanyId?: string
  status?: CommerceSettlementStatus
  page: number
  pageSize?: number
}) {
  const pageSize = params.pageSize ?? 25
  return useQuery({
    queryKey: ['commerce-settlements', params.payeeType, params.payeeCompanyId, params.status, params.page],
    queryFn: () =>
      listCommerceSettlements({
        payeeType: params.payeeType,
        payeeCompanyId: params.payeeCompanyId,
        status: params.status,
        limit: pageSize,
        offset: (params.page - 1) * pageSize,
      }),
  })
}

export function useAdminCommerceFinanceOverview(filters?: {
  from?: string
  to?: string
  vendorCompanyId?: string
  carrierCompanyId?: string
}) {
  return useQuery({
    queryKey: ['admin-commerce-finance-overview', filters?.from, filters?.to, filters?.vendorCompanyId, filters?.carrierCompanyId],
    queryFn: () => fetchAdminCommerceFinanceOverview(filters),
  })
}

export function useAdminCommerceFinancialEvents(
  page: number,
  pageSize = 25,
  filters?: { from?: string; to?: string; vendorCompanyId?: string; eventType?: string },
) {
  return useQuery({
    queryKey: ['admin-commerce-financial-events', page, filters?.from, filters?.to, filters?.vendorCompanyId, filters?.eventType],
    queryFn: () => adminListCommerceFinancialEvents(pageSize, (page - 1) * pageSize, filters),
  })
}

export function useCommerceSettlementActions() {
  const qc = useQueryClient()
  const invalidate = () => {
    void qc.invalidateQueries({ queryKey: ['commerce-settlements'] })
    void qc.invalidateQueries({ queryKey: ['admin-commerce-finance-overview'] })
    void qc.invalidateQueries({ queryKey: ['vendor-commerce-finance'] })
    void qc.invalidateQueries({ queryKey: ['carrier-commerce-finance'] })
  }
  return {
    create: useMutation({
      mutationFn: ({ payeeType, payeeCompanyId, notes }: { payeeType: CommerceSettlementPayeeType; payeeCompanyId: string; notes?: string }) =>
        adminCreateCommerceSettlement(payeeType, payeeCompanyId, notes),
      onSuccess: invalidate,
    }),
    markProcessing: useMutation({ mutationFn: adminMarkSettlementProcessing, onSuccess: invalidate }),
    recordReference: useMutation({
      mutationFn: ({ settlementId, externalReference, notes }: { settlementId: string; externalReference: string; notes?: string }) =>
        adminRecordSettlementReference(settlementId, externalReference, notes),
      onSuccess: invalidate,
    }),
    markCompleted: useMutation({ mutationFn: adminMarkSettlementCompleted, onSuccess: invalidate }),
    markFailed: useMutation({
      mutationFn: ({ settlementId, reason }: { settlementId: string; reason?: string }) => adminMarkSettlementFailed(settlementId, reason),
      onSuccess: invalidate,
    }),
    reverse: useMutation({
      mutationFn: ({ settlementId, reason }: { settlementId: string; reason?: string }) => adminReverseSettlement(settlementId, reason),
      onSuccess: invalidate,
    }),
  }
}

export function useCommerceFeeRules() {
  return useQuery({
    queryKey: ['commerce-fee-rules'],
    queryFn: fetchCommerceFeeRules,
  })
}

export function useUpsertCommerceFeeRule() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: adminUpsertCommerceFeeRule,
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['commerce-fee-rules'] }),
  })
}
