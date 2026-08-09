import { supabase } from '@/lib/supabase/client'

export type CommandCenterMetrics = {
  companies_total: number
  companies_active: number
  companies_pending: number
  companies_suspended: number
  logistics_providers: number
  merchants: number
  riders_total: number
  riders_active: number
  deliveries_today: number
  deliveries_yesterday: number
  deliveries_in_transit: number
  deliveries_completed_today: number
  deliveries_failed_today: number
  marketplace_requests_today: number
  marketplace_gmv_lrd_cents: number
  subscription_mrr_estimate_cents: number
  cod_outstanding_lrd_cents: number
  sms_sent_today: number
  sms_sent_yesterday: number
  api_requests_today: number
  api_requests_yesterday: number
  checked_at: string
}

async function rpc<T>(name: keyof import('@/types/supabase').Database['public']['Functions'], args: Record<string, unknown> = {}): Promise<T> {
  const { data, error } = await supabase.rpc(name, args as never)
  if (error) throw error
  return data as T
}

export function fetchCommandCenter() {
  return rpc<CommandCenterMetrics>('get_platform_command_center')
}

export function fetchLiveSnapshot() {
  return rpc<Record<string, unknown>>('get_platform_live_snapshot')
}

export function fetchNetworkMetrics(days: number) {
  return rpc<Record<string, unknown>>('get_platform_network_metrics', { p_days: days })
}

export function fetchTrialFunnel() {
  return rpc<Record<string, unknown>>('get_platform_trial_funnel')
}

export function fetchPlatformAlerts() {
  return rpc<{ alerts: Array<{ severity: string; title: string; detail: string; href: string }> }>(
    'get_platform_alerts',
  )
}

export function listAdminCompaniesPage(params: {
  search?: string
  businessType?: string
  status?: string
  limit?: number
  offset?: number
}) {
  return rpc<{ total: number; rows: Record<string, unknown>[] }>('list_admin_companies_page', {
    p_search: params.search ?? null,
    p_business_type: params.businessType ?? null,
    p_status: params.status ?? null,
    p_limit: params.limit ?? 25,
    p_offset: params.offset ?? 0,
  })
}

export function fetchCompany360(companyId: string) {
  return rpc<Record<string, unknown>>('get_company_admin_360', { p_company_id: companyId })
}

export function fetchCompanyHealth(companyId: string) {
  return rpc<{ level: string; reasons: string[] }>('get_company_health_score', {
    p_company_id: companyId,
  })
}

export function listAdminDeliveriesPage(params: {
  trackingCode?: string
  companyId?: string
  status?: string
  limit?: number
  offset?: number
}) {
  return rpc<{ total: number; rows: Record<string, unknown>[] }>('list_admin_deliveries_page', {
    p_tracking_code: params.trackingCode ?? null,
    p_company_id: params.companyId ?? null,
    p_status: params.status ?? null,
    p_limit: params.limit ?? 25,
    p_offset: params.offset ?? 0,
  })
}

export function fetchAdminDeliveryDetail(deliveryId: string) {
  return rpc<Record<string, unknown>>('get_admin_delivery_detail', { p_delivery_id: deliveryId })
}

export function fetchAdminMapPoints(companyId?: string, status?: string) {
  return rpc<{ riders: unknown[]; deliveries: unknown[] }>('list_admin_map_points', {
    p_company_id: companyId ?? null,
    p_status: status ?? null,
  })
}

export function fetchCommunicationsSummary(days: number) {
  return rpc<Record<string, unknown>>('get_admin_communications_summary', { p_days: days })
}

export function listAdminApiKeysPage(params: { companyId?: string; limit?: number; offset?: number }) {
  return rpc<{ total: number; rows: Record<string, unknown>[] }>('list_admin_api_keys_page', {
    p_company_id: params.companyId ?? null,
    p_limit: params.limit ?? 25,
    p_offset: params.offset ?? 0,
  })
}

export function adminGlobalSearch(query: string) {
  return rpc<{ results: Array<{ kind: string; id: string; label: string; href: string }> }>(
    'admin_global_search',
    { p_query: query },
  )
}

export function adminSupportLookup(query: string) {
  return rpc<Record<string, unknown>>('admin_support_lookup', { p_query: query })
}

export function listAuditLogsAdmin(params: {
  companyId?: string
  action?: string
  limit?: number
  offset?: number
}) {
  return rpc<{ total: number; rows: Record<string, unknown>[] }>('list_audit_logs_admin', {
    p_company_id: params.companyId ?? null,
    p_action: params.action ?? null,
    p_limit: params.limit ?? 25,
    p_offset: params.offset ?? 0,
  })
}

export function fetchExtendedHealthSnapshot() {
  return rpc<Record<string, unknown>>('get_platform_health_snapshot')
}

export async function adminSetCompanyStatus(
  companyId: string,
  status: 'pending' | 'active' | 'suspended',
) {
  const { data, error } = await supabase.rpc('admin_set_company_status', {
    p_company_id: companyId,
    p_status: status,
  })
  if (error) throw error
  return data
}
