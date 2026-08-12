import { supabase } from '@/lib/supabase/client'
import type { Json } from '@/types/supabase'

export type CommerceOrderFinanceRow = {
  order_id: string
  order_number: string
  vendor_gross_lrd_cents: number
  vendor_platform_fee_lrd_cents: number
  vendor_net_lrd_cents: number
  recognized_at: string
}

export type VendorCommerceFinance = {
  vendor_gross_lrd_cents: number
  platform_fees_lrd_cents: number
  net_earnings_lrd_cents: number
  settled_lrd_cents: number
  pending_settlement_lrd_cents: number
  orders: CommerceOrderFinanceRow[]
}

export async function fetchVendorCommerceFinance(vendorCompanyId: string): Promise<VendorCommerceFinance> {
  const { data, error } = await supabase.rpc('get_vendor_commerce_finance', { p_vendor_company_id: vendorCompanyId })
  if (error) throw error
  return data as unknown as VendorCommerceFinance
}

export type CommerceDeliveryFinanceRow = {
  delivery_id: string
  tracking_code: string
  carrier_gross_lrd_cents: number
  carrier_platform_fee_lrd_cents: number
  carrier_net_lrd_cents: number
  recognized_at: string
}

export type CarrierCommerceFinance = {
  carrier_gross_lrd_cents: number
  platform_fees_lrd_cents: number
  net_earnings_lrd_cents: number
  settled_lrd_cents: number
  pending_settlement_lrd_cents: number
  deliveries: CommerceDeliveryFinanceRow[]
}

export async function fetchCarrierCommerceFinance(carrierCompanyId: string): Promise<CarrierCommerceFinance> {
  const { data, error } = await supabase.rpc('get_carrier_commerce_finance', { p_carrier_company_id: carrierCompanyId })
  if (error) throw error
  return data as unknown as CarrierCommerceFinance
}

export type CommerceSettlementStatus = 'pending' | 'processing' | 'settled' | 'failed' | 'reversed'
export type CommerceSettlementPayeeType = 'vendor' | 'carrier'

export type CommerceSettlement = {
  id: string
  payee_type: CommerceSettlementPayeeType
  payee_company_id: string
  payee_company_name: string
  status: CommerceSettlementStatus
  total_amount_lrd_cents: number
  currency: string
  external_reference: string | null
  notes: string | null
  created_at: string
  settled_at: string | null
  failed_at: string | null
  reversed_at: string | null
}

export async function listCommerceSettlements(params: {
  payeeType?: CommerceSettlementPayeeType
  payeeCompanyId?: string
  status?: CommerceSettlementStatus
  limit?: number
  offset?: number
}): Promise<{ total: number; rows: CommerceSettlement[] }> {
  const { data, error } = await supabase.rpc('list_commerce_settlements', {
    p_payee_type: params.payeeType ?? null,
    p_payee_company_id: params.payeeCompanyId ?? null,
    p_status: params.status ?? null,
    p_limit: params.limit ?? 25,
    p_offset: params.offset ?? 0,
  })
  if (error) throw error
  const payload = (data ?? { total: 0, rows: [] }) as unknown as { total: number; rows: CommerceSettlement[] }
  return { rows: payload.rows ?? [], total: payload.total ?? 0 }
}

export async function adminCreateCommerceSettlement(
  payeeType: CommerceSettlementPayeeType,
  payeeCompanyId: string,
  notes?: string,
) {
  const { data, error } = await supabase.rpc('admin_create_commerce_settlement', {
    p_payee_type: payeeType,
    p_payee_company_id: payeeCompanyId,
    p_notes: notes ?? null,
  })
  if (error) throw error
  return data as unknown as CommerceSettlement
}

export async function adminMarkSettlementProcessing(settlementId: string) {
  const { error } = await supabase.rpc('admin_mark_commerce_settlement_processing', { p_settlement_id: settlementId })
  if (error) throw error
}

export async function adminRecordSettlementReference(settlementId: string, externalReference: string, notes?: string) {
  const { error } = await supabase.rpc('admin_record_commerce_settlement_reference', {
    p_settlement_id: settlementId,
    p_external_reference: externalReference,
    p_notes: notes ?? null,
  })
  if (error) throw error
}

export async function adminMarkSettlementCompleted(settlementId: string) {
  const { error } = await supabase.rpc('admin_mark_commerce_settlement_completed', { p_settlement_id: settlementId })
  if (error) throw error
}

export async function adminMarkSettlementFailed(settlementId: string, reason?: string) {
  const { error } = await supabase.rpc('admin_mark_commerce_settlement_failed', {
    p_settlement_id: settlementId,
    p_reason: reason ?? null,
  })
  if (error) throw error
}

export async function adminReverseSettlement(settlementId: string, reason?: string) {
  const { error } = await supabase.rpc('admin_reverse_commerce_settlement', {
    p_settlement_id: settlementId,
    p_reason: reason ?? null,
  })
  if (error) throw error
}

export type AdminCommerceFinanceOverview = {
  commerce_gmv_lrd_cents: number
  cod_collected_lrd_cents: number
  platform_revenue_lrd_cents: number
  vendor_unsettled_lrd_cents: number
  carrier_unsettled_lrd_cents: number
  settlements_pending: number
  settlements_processing: number
  settlements_completed: number
  settlements_failed: number
  reversals_count: number
}

export async function fetchAdminCommerceFinanceOverview(filters?: {
  from?: string
  to?: string
  vendorCompanyId?: string
  carrierCompanyId?: string
}): Promise<AdminCommerceFinanceOverview> {
  const { data, error } = await supabase.rpc('get_admin_commerce_finance_overview', {
    p_from: filters?.from ?? null,
    p_to: filters?.to ?? null,
    p_vendor_company_id: filters?.vendorCompanyId ?? null,
    p_carrier_company_id: filters?.carrierCompanyId ?? null,
  })
  if (error) throw error
  return data as unknown as AdminCommerceFinanceOverview
}

export type CommerceFinancialEventRow = {
  id: string
  event_type: 'cod_collected' | 'reversal' | 'adjustment'
  commerce_order_id: string
  order_number: string
  vendor_company_id: string
  delivery_id: string | null
  snapshot: Record<string, unknown>
  reason: string | null
  created_at: string
}

export async function adminListCommerceFinancialEvents(
  limit = 25,
  offset = 0,
  filters?: { from?: string; to?: string; vendorCompanyId?: string; eventType?: string },
): Promise<{ total: number; rows: CommerceFinancialEventRow[] }> {
  const { data, error } = await supabase.rpc('admin_list_commerce_financial_events', {
    p_limit: limit,
    p_offset: offset,
    p_from: filters?.from ?? null,
    p_to: filters?.to ?? null,
    p_vendor_company_id: filters?.vendorCompanyId ?? null,
    p_event_type: filters?.eventType ?? null,
  })
  if (error) throw error
  const payload = (data ?? { total: 0, rows: [] }) as unknown as { total: number; rows: CommerceFinancialEventRow[] }
  return { rows: payload.rows ?? [], total: payload.total ?? 0 }
}

export type CommerceFeeRule = {
  id: string
  name: string
  fee_model: 'fixed' | 'percentage' | 'subscription_only' | 'zero_commission'
  fixed_fee_lrd_cents: number
  percentage_bps: number
  is_active: boolean
  is_platform_default: boolean
  applies_to_vendor_company_id: string | null
  created_at: string
  updated_at: string
}

export async function fetchCommerceFeeRules(): Promise<CommerceFeeRule[]> {
  const { data, error } = await supabase
    .from('commerce_fee_rules')
    .select(
      'id, name, fee_model, fixed_fee_lrd_cents, percentage_bps, is_active, is_platform_default, applies_to_vendor_company_id, created_at, updated_at',
    )
    .order('is_platform_default', { ascending: false })
    .order('created_at', { ascending: false })
  if (error) throw error
  return (data ?? []) as unknown as CommerceFeeRule[]
}

export async function adminUpsertCommerceFeeRule(payload: {
  id?: string
  name: string
  fee_model: string
  fixed_fee_lrd_cents?: number
  percentage_bps?: number
  is_active?: boolean
  is_platform_default?: boolean
  applies_to_vendor_company_id?: string | null
}) {
  const { data, error } = await supabase.rpc('admin_upsert_commerce_fee_rule', { p_payload: payload as Json })
  if (error) throw error
  return data as unknown as CommerceFeeRule
}
