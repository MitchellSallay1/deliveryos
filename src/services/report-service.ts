import { supabase } from '@/lib/supabase/client'
import type { ReportPeriod, WorkspaceReport } from '@/types/reports'

export async function fetchWorkspaceReport(companyId: string, period: ReportPeriod) {
  const { data, error } = await supabase.rpc('get_workspace_report', {
    p_company_id: companyId,
    p_period: period,
  })

  if (error) throw error
  return data as WorkspaceReport
}
