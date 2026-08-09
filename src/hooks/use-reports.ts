import { useQuery } from '@tanstack/react-query'
import { fetchWorkspaceReport } from '@/services/report-service'
import type { ReportPeriod } from '@/types/reports'

export function useWorkspaceReport(companyId: string | null, period: ReportPeriod) {
  return useQuery({
    queryKey: ['workspace-report', companyId, period],
    queryFn: () => fetchWorkspaceReport(companyId!, period),
    enabled: !!companyId,
  })
}
