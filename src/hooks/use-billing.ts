import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  adminCreateInvoice,
  adminMarkInvoicePaid,
  adminRecordBillingPayment,
  adminSetCompanySubscription,
  adminUpsertPlan,
  fetchCompanyUsage,
  fetchPlatformBillingMetrics,
  listAuditLogsPage,
  listBillingPaymentsPage,
  listInvoicesPage,
  listPlansAdmin,
  listPublicPlans,
} from '@/services/billing-service'
import type { CompanySubscriptionStatus } from '@/types/supabase'

export function useCompanyUsage(companyId: string | null) {
  return useQuery({
    queryKey: ['company-usage', companyId],
    queryFn: () => fetchCompanyUsage(companyId!),
    enabled: !!companyId,
  })
}

export function usePlatformBillingMetrics(enabled: boolean) {
  return useQuery({
    queryKey: ['platform-billing-metrics'],
    queryFn: fetchPlatformBillingMetrics,
    enabled,
  })
}

export function usePublicPlans(enabled: boolean) {
  return useQuery({
    queryKey: ['public-plans'],
    queryFn: listPublicPlans,
    enabled,
  })
}

export function useAdminPlans(enabled: boolean) {
  return useQuery({
    queryKey: ['admin-plans'],
    queryFn: listPlansAdmin,
    enabled,
  })
}

export function useInvoicesPage(
  params: {
    companyId?: string | null
    status?: string | null
    search?: string
    page?: number
    pageSize?: number
  },
  enabled: boolean,
) {
  const page = params.page ?? 1
  const pageSize = params.pageSize ?? 25
  return useQuery({
    queryKey: ['invoices-page', params, page, pageSize],
    queryFn: () =>
      listInvoicesPage({
        companyId: params.companyId,
        status: params.status,
        search: params.search,
        limit: pageSize,
        offset: (page - 1) * pageSize,
      }),
    enabled,
  })
}

export function useBillingPaymentsPage(
  companyId: string | null | undefined,
  page: number,
  enabled: boolean,
) {
  return useQuery({
    queryKey: ['billing-payments-page', companyId, page],
    queryFn: () =>
      listBillingPaymentsPage({
        companyId: companyId ?? null,
        limit: 25,
        offset: (page - 1) * 25,
      }),
    enabled,
  })
}

export function useAuditLogsPage(
  companyId: string | null | undefined,
  page: number,
  enabled: boolean,
) {
  return useQuery({
    queryKey: ['audit-logs-page', companyId, page],
    queryFn: () =>
      listAuditLogsPage({
        companyId: companyId ?? null,
        limit: 25,
        offset: (page - 1) * 25,
      }),
    enabled,
  })
}

export function useAdminBillingActions() {
  const qc = useQueryClient()
  const invalidate = () => {
    void qc.invalidateQueries({ queryKey: ['admin-plans'] })
    void qc.invalidateQueries({ queryKey: ['platform-billing-metrics'] })
    void qc.invalidateQueries({ queryKey: ['invoices-page'] })
    void qc.invalidateQueries({ queryKey: ['billing-payments-page'] })
    void qc.invalidateQueries({ queryKey: ['audit-logs-page'] })
    void qc.invalidateQueries({ queryKey: ['company-usage'] })
    void qc.invalidateQueries({ queryKey: ['admin-companies'] })
  }

  return {
    upsertPlan: useMutation({
      mutationFn: adminUpsertPlan,
      onSuccess: invalidate,
    }),
    setSubscription: useMutation({
      mutationFn: (p: {
        companyId: string
        planId: string
        status: CompanySubscriptionStatus
        periodEnd?: string
      }) => adminSetCompanySubscription(p.companyId, p.planId, p.status, p.periodEnd),
      onSuccess: invalidate,
    }),
    createInvoice: useMutation({ mutationFn: adminCreateInvoice, onSuccess: invalidate }),
    recordPayment: useMutation({ mutationFn: adminRecordBillingPayment, onSuccess: invalidate }),
    markInvoicePaid: useMutation({
      mutationFn: (p: { invoiceId: string; reference?: string }) =>
        adminMarkInvoicePaid(p.invoiceId, p.reference),
      onSuccess: invalidate,
    }),
  }
}
