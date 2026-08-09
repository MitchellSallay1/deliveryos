import { supabase } from '@/lib/supabase/client'
import type { Json } from '@/types/supabase'

export type RiderLocationRow = {
  rider_id: string
  rider_name: string
  rider_code: string
  rider_status: string
  delivery_id: string | null
  tracking_code: string | null
  delivery_status: string | null
  latitude: number
  longitude: number
  tracking_state: string
  recorded_at: string
}

export async function recordRiderLocation(input: {
  latitude: number
  longitude: number
  accuracy?: number
  heading?: number
  speed?: number
  trackingState?: string
  deliveryId?: string | null
}) {
  const { data, error } = await supabase.rpc('record_rider_location', {
    p_latitude: input.latitude,
    p_longitude: input.longitude,
    p_accuracy: input.accuracy ?? null,
    p_heading: input.heading ?? null,
    p_speed: input.speed ?? null,
    p_tracking_state: (input.trackingState ?? 'active_delivery') as
      | 'off'
      | 'available'
      | 'active_delivery'
      | 'paused',
    p_delivery_id: input.deliveryId ?? null,
  })
  if (error) throw error
  return data
}

export async function fetchCompanyRiderLocations(companyId: string) {
  const { data, error } = await supabase.rpc('list_company_rider_locations', {
    p_company_id: companyId,
  })
  if (error) throw error
  const rows = data as unknown
  return (Array.isArray(rows) ? rows : []) as RiderLocationRow[]
}

function trackingClientKey(): string {
  const k = 'deliveryos_track_client'
  let v = sessionStorage.getItem(k)
  if (!v) {
    v = crypto.randomUUID()
    sessionStorage.setItem(k, v)
  }
  return v
}

export async function fetchPublicDeliveryTracking(trackingCode: string) {
  const { data, error } = await supabase.rpc('get_public_delivery_tracking', {
    p_tracking_code: trackingCode,
    p_client_key: trackingClientKey(),
  })
  if (error) throw error
  return data as Json | null
}

export async function listDeliveryZones(companyId: string) {
  const { data, error } = await supabase.rpc('list_delivery_zones', { p_company_id: companyId })
  if (error) throw error
  return data ?? []
}

export async function upsertDeliveryZone(payload: Record<string, unknown>) {
  const { data, error } = await supabase.rpc('upsert_delivery_zone', {
    p_payload: payload as Json,
  })
  if (error) throw error
  return data
}

export async function fetchOperationalAnalytics(companyId: string, days = 30) {
  const { data, error } = await supabase.rpc('get_operational_analytics', {
    p_company_id: companyId,
    p_days: days,
  })
  if (error) throw error
  return data as Json
}

export async function fetchRiderPerformance(companyId: string, days = 30) {
  const { data, error } = await supabase.rpc('get_rider_performance_metrics', {
    p_company_id: companyId,
    p_days: days,
  })
  if (error) throw error
  return data as Json
}

export async function createApiKey(
  companyId: string,
  name: string,
  permissions: string[],
  expiresAt?: string,
) {
  const { data, error } = await supabase.rpc('create_company_api_key', {
    p_company_id: companyId,
    p_name: name,
    p_permissions: permissions,
    p_expires_at: expiresAt ?? null,
  })
  if (error) throw error
  return data as Json
}

export async function listApiKeys(companyId: string) {
  const { data, error } = await supabase.rpc('list_company_api_keys', {
    p_company_id: companyId,
  })
  if (error) throw error
  return data ?? []
}

export async function revokeApiKey(keyId: string) {
  const { error } = await supabase.rpc('revoke_company_api_key', { p_key_id: keyId })
  if (error) throw error
}

export async function upsertWebhookEndpoint(payload: Record<string, unknown>) {
  const { data, error } = await supabase.rpc('upsert_webhook_endpoint', {
    p_payload: payload as Json,
  })
  if (error) throw error
  return data
}
