import { supabase } from '@/lib/supabase/client'
import type { Json } from '@/types/supabase'

export type CompanyBusinessType = 'logistics_provider' | 'merchant' | 'hybrid'

export async function createDeliveryRequest(payload: Record<string, unknown>) {
  const { data, error } = await supabase.rpc('create_delivery_request', {
    p_payload: payload as Json,
  })
  if (error) throw error
  return data
}

export async function publishDeliveryRequest(requestId: string, merchantCompanyId: string) {
  const { data, error } = await supabase.rpc('publish_delivery_request', {
    p_request_id: requestId,
    p_merchant_company_id: merchantCompanyId,
  })
  if (error) throw error
  return data
}

export async function listDeliveryRequestsPage(
  merchantCompanyId: string,
  opts?: { status?: string; limit?: number; offset?: number },
) {
  const { data, error } = await supabase.rpc('list_delivery_requests_page', {
    p_merchant_company_id: merchantCompanyId,
    p_status: opts?.status ?? null,
    p_limit: opts?.limit ?? 25,
    p_offset: opts?.offset ?? 0,
  })
  if (error) throw error
  return data as unknown as { items: unknown[]; total: number; limit: number; offset: number }
}

export async function cancelDeliveryRequest(
  requestId: string,
  merchantCompanyId: string,
  reason?: string,
) {
  const { data, error } = await supabase.rpc('cancel_delivery_request', {
    p_request_id: requestId,
    p_merchant_company_id: merchantCompanyId,
    p_reason: reason ?? null,
  })
  if (error) throw error
  return data
}

export async function listMarketplaceJobsPage(
  providerCompanyId: string,
  opts?: { status?: string; limit?: number; offset?: number },
) {
  const { data, error } = await supabase.rpc('list_marketplace_jobs_page', {
    p_provider_company_id: providerCompanyId,
    p_status: opts?.status ?? 'pending',
    p_limit: opts?.limit ?? 25,
    p_offset: opts?.offset ?? 0,
  })
  if (error) throw error
  return data as unknown as { items: unknown[]; total: number }
}

export async function acceptMarketplaceOffer(offerId: string, providerCompanyId: string) {
  const { data, error } = await supabase.rpc('accept_marketplace_offer', {
    p_offer_id: offerId,
    p_provider_company_id: providerCompanyId,
  })
  if (error) throw error
  return data
}

export async function rejectMarketplaceOffer(offerId: string, providerCompanyId: string) {
  const { data, error } = await supabase.rpc('reject_marketplace_offer', {
    p_offer_id: offerId,
    p_provider_company_id: providerCompanyId,
  })
  if (error) throw error
  return data
}

export async function listMarketplaceProvidersPage(merchantCompanyId: string, offset = 0) {
  const { data, error } = await supabase.rpc('list_marketplace_providers_page', {
    p_merchant_company_id: merchantCompanyId,
    p_limit: 25,
    p_offset: offset,
  })
  if (error) throw error
  return data as unknown as { items: unknown[]; total: number }
}

export async function upsertProviderMarketplaceProfile(payload: Record<string, unknown>) {
  const { data, error } = await supabase.rpc('upsert_provider_marketplace_profile', {
    p_payload: payload as Json,
  })
  if (error) throw error
  return data
}

export async function upsertMerchantProviderRelationship(payload: Record<string, unknown>) {
  const { data, error } = await supabase.rpc('upsert_merchant_provider_relationship', {
    p_payload: payload as Json,
  })
  if (error) throw error
  return data
}

export async function getMarketplaceAnalytics(
  scope: 'platform' | 'merchant' | 'provider',
  companyId?: string,
) {
  const { data, error } = await supabase.rpc('get_marketplace_analytics', {
    p_company_id: companyId ?? null,
    p_scope: scope,
  })
  if (error) throw error
  return data as unknown as Record<string, unknown>
}

export async function createProviderReview(payload: Record<string, unknown>) {
  const { data, error } = await supabase.rpc('create_provider_review', {
    p_payload: payload as Json,
  })
  if (error) throw error
  return data
}
