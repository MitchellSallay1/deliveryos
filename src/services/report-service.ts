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

export type DeliveryTrendDay = { date: string; total: number; completed: number; failed: number }

export async function fetchCompanyDeliveryTrend(companyId: string, days = 7) {
  const { data, error } = await supabase.rpc('get_company_delivery_trend', {
    p_company_id: companyId,
    p_days: days,
  })

  if (error) throw error
  return (data as { days: DeliveryTrendDay[] }).days
}
