import { supabase } from '@/lib/supabase/client'
import type {
  CustomerRow,
  DeliveryListParams,
  DeliveryListResult,
  DeliveryRow,
  RiderRow,
  TrackingPublic,
} from '@/types/delivery'
import type { DeliveryStatus } from '@/types/supabase'
import type { CreateDeliveryInput } from '@/utils/delivery-schemas'

const DEFAULT_PAGE_SIZE = 25

export async function listDeliveries(
  companyId: string,
  params: DeliveryListParams = {},
): Promise<DeliveryListResult> {
  const page = Math.max(1, params.page ?? 1)
  const pageSize = Math.min(100, Math.max(1, params.pageSize ?? DEFAULT_PAGE_SIZE))
  const from = (page - 1) * pageSize
  const to = from + pageSize - 1

  let query = supabase
    .from('deliveries')
    .select('*', { count: 'exact' })
    .eq('company_id', companyId)
    .order('created_at', { ascending: false })

  const search = params.search?.trim()
  if (search) {
    query = query.or(
      `tracking_code.ilike.%${search}%,customer_name.ilike.%${search}%,customer_phone.ilike.%${search}%`,
    )
  }

  const { data, error, count } = await query.range(from, to)

  if (error) throw error
  return {
    rows: (data ?? []) as DeliveryRow[],
    total: count ?? 0,
    page,
    pageSize,
  }
}

export async function listRiders(companyId: string) {
  const { data, error } = await supabase
    .from('riders')
    .select('id, rider_code, full_name, phone, status, access_mode, sms_channel_enabled, ussd_channel_enabled')
    .eq('company_id', companyId)
    .order('rider_code')

  if (error) throw error
  return (data ?? []) as RiderRow[]
}

export async function listCustomers(companyId: string) {
  const { data, error } = await supabase
    .from('customers')
    .select('id, full_name, phone, address')
    .eq('company_id', companyId)
    .order('full_name')

  if (error) throw error
  return (data ?? []) as CustomerRow[]
}

export async function createDelivery(companyId: string, input: CreateDeliveryInput) {
  const { data, error } = await supabase.rpc('create_delivery', {
    p_company_id: companyId,
    p_pickup_business_name: input.pickupBusinessName,
    p_pickup_address: input.pickupAddress,
    p_customer_name: input.customerName,
    p_customer_phone: input.customerPhone,
    p_destination_address: input.destinationAddress,
    p_package_description: input.packageDescription ?? null,
    p_amount_to_collect_lrd_cents: Math.round(input.amountToCollectLrd * 100),
    p_delivery_fee_lrd_cents: Math.round(input.deliveryFeeLrd * 100),
    p_customer_id: input.customerId ?? null,
    p_delivery_zone_id: input.deliveryZoneId ?? null,
    p_fee_manual_override: input.feeManualOverride ?? false,
  })

  if (error) throw error
  return data
}

export async function assignDeliveryRider(deliveryId: string, riderId: string) {
  const { data, error } = await supabase.rpc('assign_delivery_rider', {
    p_delivery_id: deliveryId,
    p_rider_id: riderId,
  })
  if (error) throw error
  return data
}

export async function resendRiderJobSms(deliveryId: string) {
  const { data, error } = await supabase.rpc('resend_rider_job_sms', {
    p_delivery_id: deliveryId,
  })
  if (error) throw error
  return data as boolean
}

export async function transitionDeliveryStatus(
  deliveryId: string,
  toStatus: DeliveryStatus,
  note?: string,
) {
  const { data, error } = await supabase.rpc('transition_delivery_status', {
    p_delivery_id: deliveryId,
    p_to_status: toStatus,
    p_note: note ?? null,
  })
  if (error) throw error
  return data
}

export async function fetchPublicTracking(trackingCode: string) {
  const { data, error } = await supabase.rpc('get_delivery_tracking', {
    p_tracking_code: trackingCode,
  })
  if (error) throw error
  const rows = data as TrackingPublic[] | null
  return rows?.[0] ?? null
}
