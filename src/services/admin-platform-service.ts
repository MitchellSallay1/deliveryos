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

// Commerce Phase E2 (MTN MoMo payments) — admin_list_payment_attempts_page
// and admin_reconcile_payment_attempt are not yet in the generated
// Database type (generated only against a --linked remote project, not run
// this phase), so these two bypass the typed rpc<T> helper above and call
// supabase.rpc directly, exactly like customer-commerce-service.ts already
// does throughout for the same reason.
export type PaymentAttemptAdminRow = {
  id: string
  company_id: string | null
  company_name: string | null
  commerce_order_id: string | null
  order_number: string | null
  payer_msisdn_masked: string
  currency: string
  gross_amount_cents: number
  provider_fee_cents: number | null
  provider_net_cents: number | null
  external_id: string
  state: string
  raw_provider_status: string | null
  http_status: number | null
  failure_category: string | null
  reconciliation_state: string
  // True when a SUCCESSFUL attempt's provider fee exceeded the platform's
  // own commission on the transaction — an accounting/margin review flag,
  // never an indicator of payment uncertainty (see `state` for that).
  margin_anomaly: boolean
  attempt_count: number
  created_at: string
  requested_at: string | null
  resolved_at: string | null
  total_count: number
}

export async function listAdminPaymentAttemptsPage(params: {
  state?: string[]
  reconciliationState?: string[]
  limit?: number
  offset?: number
  marginAnomalyOnly?: boolean
}): Promise<{ rows: PaymentAttemptAdminRow[]; total: number }> {
  const { data, error } = await supabase.rpc('admin_list_payment_attempts_page' as never, {
    p_state: params.state ?? null,
    p_reconciliation_state: params.reconciliationState ?? null,
    p_limit: params.limit ?? 50,
    p_offset: params.offset ?? 0,
    p_margin_anomaly_only: params.marginAnomalyOnly ?? false,
  } as never)
  if (error) throw error
  const rows = (data ?? []) as unknown as PaymentAttemptAdminRow[]
  return { rows, total: rows[0]?.total_count ?? 0 }
}

export async function adminReconcilePaymentAttempt(
  attemptId: string,
  resolution: 'confirmed_successful' | 'confirmed_failed' | 'still_unresolved',
  notes?: string,
) {
  const { data, error } = await supabase.rpc('admin_reconcile_payment_attempt' as never, {
    p_attempt_id: attemptId,
    p_resolution: resolution,
    p_notes: notes ?? null,
  } as never)
  if (error) throw error
  return data
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

export function fetchPlatformSecuritySnapshot() {
  return rpc<Record<string, unknown>>('get_platform_security_snapshot')
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
