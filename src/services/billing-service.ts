import { supabase } from '@/lib/supabase/client'
import type { BillingPaymentMethod, CompanySubscriptionStatus, Json } from '@/types/supabase'

export type CompanyUsage = {
  subscription: Json
  plan: Json
  trial?: {
    is_free_trial?: boolean
    status?: string
    trial_ends_at?: string | null
    days_remaining?: number | null
    expired?: boolean
  }
  period?: { start: string; end: string }
  usage: {
    deliveries_created: number
    deliveries_completed: number
    riders: number
    sms_consumed: number
    storage_photos: number
  }
  limits: {
    max_deliveries_per_month: number | null
    max_riders: number
    monthly_sms_allowance: number
  }
}

export async function fetchCompanyUsage(companyId: string) {
  const { data, error } = await supabase.rpc('get_company_usage', {
    p_company_id: companyId,
  })
  if (error) throw error
  return data as CompanyUsage
}

export async function fetchPlatformBillingMetrics() {
  const { data, error } = await supabase.rpc('get_platform_billing_metrics')
  if (error) throw error
  return data as Json
}

export async function listPlansAdmin() {
  const { data, error } = await supabase.rpc('list_plans_admin')
  if (error) throw error
  return data ?? []
}

export async function adminUpsertPlan(payload: Json | Record<string, unknown>) {
  const { data, error } = await supabase.rpc('admin_upsert_plan', {
    p_payload: payload as Json,
  })
  if (error) throw error
  return data
}

export async function adminSetCompanySubscription(
  companyId: string,
  planId: string,
  status: CompanySubscriptionStatus,
  periodEnd?: string,
) {
  const { data, error } = await supabase.rpc('admin_set_company_subscription', {
    p_company_id: companyId,
    p_plan_id: planId,
    p_status: status,
    p_period_end: periodEnd ?? null,
  })
  if (error) throw error
  return data
}

export async function adminCreateInvoice(input: {
  companyId: string
  planId: string
  amountCents: number
  periodStart: string
  periodEnd: string
  dueAt: string
}) {
  const { data, error } = await supabase.rpc('admin_create_invoice', {
    p_company_id: input.companyId,
    p_plan_id: input.planId,
    p_amount_cents: input.amountCents,
    p_period_start: input.periodStart,
    p_period_end: input.periodEnd,
    p_due_at: input.dueAt,
  })
  if (error) throw error
  return data
}

export async function adminRecordBillingPayment(input: {
  companyId: string
  invoiceId: string
  amountCents: number
  paymentMethod: BillingPaymentMethod
  reference?: string
  paidAt?: string
}) {
  const { data, error } = await supabase.rpc('admin_record_billing_payment', {
    p_company_id: input.companyId,
    p_invoice_id: input.invoiceId,
    p_amount_cents: input.amountCents,
    p_payment_method: input.paymentMethod,
    p_reference: input.reference ?? null,
    p_paid_at: input.paidAt ?? null,
  })
  if (error) throw error
  return data
}

export async function adminMarkInvoicePaid(invoiceId: string, reference?: string) {
  const { data, error } = await supabase.rpc('admin_mark_invoice_paid', {
    p_invoice_id: invoiceId,
    p_payment_reference: reference ?? null,
  })
  if (error) throw error
  return data
}

export async function listInvoicesPage(params: {
  companyId?: string | null
  status?: string | null
  search?: string
  limit?: number
  offset?: number
}) {
  const { data, error } = await supabase.rpc('list_invoices_page', {
    p_company_id: params.companyId ?? null,
    p_status: params.status ?? null,
    p_search: params.search ?? null,
    p_limit: params.limit ?? 25,
    p_offset: params.offset ?? 0,
  })
  if (error) throw error
  return data as { total: number; rows: Json[] }
}

export async function listBillingPaymentsPage(params: {
  companyId?: string | null
  limit?: number
  offset?: number
}) {
  const { data, error } = await supabase.rpc('list_billing_payments_page', {
    p_company_id: params.companyId ?? null,
    p_limit: params.limit ?? 25,
    p_offset: params.offset ?? 0,
  })
  if (error) throw error
  return data as { total: number; rows: Json[] }
}

export async function listAuditLogsPage(params: {
  companyId?: string | null
  limit?: number
  offset?: number
}) {
  const { data, error } = await supabase.rpc('list_audit_logs_page', {
    p_company_id: params.companyId ?? null,
    p_limit: params.limit ?? 25,
    p_offset: params.offset ?? 0,
  })
  if (error) throw error
  return data as { total: number; rows: Json[] }
}

export async function listPublicPlans() {
  const { data, error } = await supabase
    .from('subscriptions')
    .select(
      'id, slug, name, price_lrd_cents, currency, max_riders, max_deliveries_per_month, monthly_sms_allowance, proof_of_delivery, advanced_reports, api_access, gps_tracking, custom_branding',
    )
    .eq('is_active', true)
    .order('price_lrd_cents')
  if (error) throw error
  return data ?? []
}

export async function canUseFeature(companyId: string, featureKey: string) {
  const { data, error } = await supabase.rpc('can_use_feature', {
    p_company_id: companyId,
    p_feature_key: featureKey,
  })
  if (error) throw error
  return Boolean(data)
}
