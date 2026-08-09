import { supabase } from '@/lib/supabase/client'
import type { CompanyPlanUsage, Rider } from '@/types/fleet'
import type { RiderStatus } from '@/types/supabase'
import type { CreateRiderInput } from '@/utils/rider-schemas'

export async function listRidersDetailed(companyId: string) {
  const { data, error } = await supabase
    .from('riders')
    .select('*')
    .eq('company_id', companyId)
    .order('rider_code')

  if (error) throw error
  return (data ?? []) as Rider[]
}

export async function createRider(companyId: string, input: CreateRiderInput) {
  const { data, error } = await supabase
    .from('riders')
    .insert({
      company_id: companyId,
      rider_code: input.riderCode,
      full_name: input.fullName,
      phone: input.phone,
      status: input.status,
      access_mode: input.accessMode,
      sms_channel_enabled: input.smsChannelEnabled,
      ussd_channel_enabled: input.ussdChannelEnabled,
    })
    .select()
    .single()

  if (error) throw error
  return data as Rider
}

export async function updateRiderAccess(
  riderId: string,
  patch: {
    accessMode?: CreateRiderInput['accessMode']
    smsChannelEnabled?: boolean
    ussdChannelEnabled?: boolean
  },
) {
  const { data, error } = await supabase
    .from('riders')
    .update({
      access_mode: patch.accessMode,
      sms_channel_enabled: patch.smsChannelEnabled,
      ussd_channel_enabled: patch.ussdChannelEnabled,
    })
    .eq('id', riderId)
    .select()
    .single()

  if (error) throw error
  return data as Rider
}

export async function updateRiderStatus(riderId: string, status: RiderStatus) {
  const { data, error } = await supabase
    .from('riders')
    .update({ status })
    .eq('id', riderId)
    .select()
    .single()

  if (error) throw error
  return data as Rider
}

export async function fetchCompanyPlanUsage(companyId: string): Promise<CompanyPlanUsage> {
  const { data: company, error: companyError } = await supabase
    .from('companies')
    .select('id, status, sms_credits, subscription_id')
    .eq('id', companyId)
    .single()

  if (companyError) throw companyError

  const { count, error: countError } = await supabase
    .from('riders')
    .select('*', { count: 'exact', head: true })
    .eq('company_id', companyId)

  if (countError) throw countError

  const { data: sub, error: subError } = await supabase
    .from('subscriptions')
    .select('name, max_riders')
    .eq('id', company.subscription_id)
    .single()

  if (subError) throw subError

  return {
    company_id: company.id,
    status: company.status,
    sms_credits: company.sms_credits,
    rider_count: count ?? 0,
    max_riders: sub.max_riders,
    plan_name: sub.name,
  }
}
