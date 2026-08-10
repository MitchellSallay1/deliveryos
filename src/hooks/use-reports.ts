import { useQuery } from '@tanstack/react-query'
import { fetchCompanyDeliveryTrend, fetchWorkspaceReport } from '@/services/report-service'
import type { ReportPeriod } from '@/types/reports'

export function useWorkspaceReport(companyId: string | null, period: ReportPeriod) {
  return useQuery({
    queryKey: ['workspace-report', companyId, period],
    queryFn: () => fetchWorkspaceReport(companyId!, period),
    enabled: !!companyId,
  })
}

export function useCompanyDeliveryTrend(companyId: string | null, days = 7) {
  return useQuery({
    queryKey: ['company-delivery-trend', companyId, days],
    queryFn: () => fetchCompanyDeliveryTrend(companyId!, days),
    enabled: !!companyId,
  })
}
