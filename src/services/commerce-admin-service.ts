import { supabase } from '@/lib/supabase/client'

export type CommerceOrdersSummary = {
  by_status: Record<string, number>
  stuck_count: number
}

export async function fetchCommerceOrdersSummary(stuckAfterHours = 24): Promise<CommerceOrdersSummary> {
  const { data, error } = await supabase.rpc('admin_get_commerce_orders_summary', {
    p_stuck_after_hours: stuckAfterHours,
  })
  if (error) throw error
  return data as unknown as CommerceOrdersSummary
}

export type AdminCommerceOrderRow = {
  id: string
  order_number: string
  fulfillment_status: string
  payment_status: string
  payment_method: string
  customer_name: string
  total_lrd_cents: number
  created_at: string
  updated_at: string
  vendor_name: string
  vendor_company_id: string
  delivery_status: string | null
  carrier_company_id: string | null
  carrier_name: string | null
  is_stuck: boolean
  hours_since_update: number
}

export async function listCommerceOrdersPage(params: {
  fulfillmentStatuses?: string[]
  stuckOnly?: boolean
  stuckAfterHours?: number
  search?: string
  limit?: number
  offset?: number
}): Promise<{ total: number; rows: AdminCommerceOrderRow[] }> {
  const { data, error } = await supabase.rpc('admin_list_commerce_orders_page', {
    p_fulfillment_statuses: params.fulfillmentStatuses ?? null,
    p_stuck_only: params.stuckOnly ?? false,
    p_stuck_after_hours: params.stuckAfterHours ?? 24,
    p_search: params.search ?? null,
    p_limit: params.limit ?? 25,
    p_offset: params.offset ?? 0,
  })
  if (error) throw error
  const payload = (data ?? { total: 0, rows: [] }) as unknown as { total: number; rows: AdminCommerceOrderRow[] }
  return { rows: payload.rows ?? [], total: payload.total ?? 0 }
}

export type AdminCommerceProviderRow = {
  company_id: string
  company_name: string
  company_status: string
  marketplace_enabled: boolean
  accepting_jobs: boolean
  minimum_delivery_fee_lrd_cents: number
  delivery_pricing_configured_at: string | null
  admin_marketplace_disabled: boolean
  available_riders: number
  total_riders: number
}

export async function listCommerceProvidersPage(params: {
  search?: string
  limit?: number
  offset?: number
}): Promise<{ total: number; rows: AdminCommerceProviderRow[] }> {
  const { data, error } = await supabase.rpc('admin_list_commerce_providers_page', {
    p_search: params.search ?? null,
    p_limit: params.limit ?? 25,
    p_offset: params.offset ?? 0,
  })
  if (error) throw error
  const payload = (data ?? { total: 0, rows: [] }) as unknown as { total: number; rows: AdminCommerceProviderRow[] }
  return { rows: payload.rows ?? [], total: payload.total ?? 0 }
}

export type CommerceReconciliationGapRow = {
  id: string
  order_number: string
  vendor_company_id: string
  payment_status: string
  payment_method: string
  total_lrd_cents: number
  updated_at: string
}

export async function fetchCommerceReconciliationGaps(limit = 50): Promise<{ rows: CommerceReconciliationGapRow[]; count: number }> {
  const { data, error } = await supabase.rpc('admin_commerce_reconciliation_gaps', { p_limit: limit })
  if (error) throw error
  return data as unknown as { rows: CommerceReconciliationGapRow[]; count: number }
}
