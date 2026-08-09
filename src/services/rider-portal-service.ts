import { supabase } from '@/lib/supabase/client'
import type { DeliveryRow } from '@/types/delivery'
import type { DeliveryStatus } from '@/types/supabase'

export async function fetchLinkedRiders(userId: string) {
  const { data, error } = await supabase
    .from('riders')
    .select('*')
    .eq('user_id', userId)

  if (error) throw error
  return (data ?? []) as (import('@/types/fleet').Rider & { user_id: string | null })[]
}

export async function linkRiderAccount(input: { riderCode?: string; inviteCode?: string }) {
  const { data, error } = await supabase.rpc('link_rider_account', {
    p_rider_code: input.riderCode?.trim() || null,
    p_invite_code: input.inviteCode?.trim() || null,
  })
  if (error) throw error
  return data as {
    rider_id: string
    rider_code: string
    invite_code: string
    company_id: string
    company_name: string
    linked: boolean
    idempotent?: boolean
  }
}

export async function fetchRiderInvitePreview(code: string) {
  const { data, error } = await supabase.rpc('get_rider_invite_preview', {
    p_invite_code: code,
  })
  if (error) throw error
  return data as {
    invite_code: string
    rider_code: string
    company_name: string
    access_mode: string
  } | null
}

export async function regenerateRiderInviteCode(riderId: string) {
  const { data, error } = await supabase.rpc('regenerate_rider_invite_code', {
    p_rider_id: riderId,
  })
  if (error) throw error
  return data as import('@/types/fleet').Rider & { invite_code?: string }
}

export async function claimRiderProfile(companyId: string, riderCode: string) {
  const { data, error } = await supabase.rpc('claim_rider_profile', {
    p_company_id: companyId,
    p_rider_code: riderCode,
  })
  if (error) throw error
  return data as import('@/types/fleet').Rider
}

export async function setRiderUserId(riderId: string, userId: string) {
  const { data, error } = await supabase.rpc('set_rider_user_id', {
    p_rider_id: riderId,
    p_user_id: userId,
  })
  if (error) throw error
  return data as import('@/types/fleet').Rider
}

export async function listRiderActiveDeliveries(riderId: string) {
  const { data, error } = await supabase
    .from('deliveries')
    .select('*')
    .eq('rider_id', riderId)
    .in('status', ['assigned', 'accepted', 'picked_up', 'in_transit'])
    .order('assigned_at', { ascending: false, nullsFirst: false })

  if (error) throw error
  return (data ?? []) as DeliveryRow[]
}

export async function riderTransitionDelivery(
  deliveryId: string,
  toStatus: DeliveryStatus,
  note?: string,
) {
  const { data, error } = await supabase.rpc('rider_transition_delivery_status', {
    p_delivery_id: deliveryId,
    p_to_status: toStatus,
    p_note: note ?? null,
  })
  if (error) throw error
  return data as DeliveryRow
}
