import { supabase } from '@/lib/supabase/client'
import type { CompanyPlanUsage } from '@/types/fleet'

export type CompanySettings = {
  id: string
  name: string
  slug: string
  phone: string
  email: string
  address: string | null
  status: string
  sms_credits: number
  allow_smartphone_riders: boolean
  allow_button_phone_riders: boolean
  enable_rider_sms: boolean
  enable_rider_ussd: boolean
  require_otp_button_phone_delivery: boolean
  subscription: {
    name: string
    slug: string
    max_riders: number
    max_deliveries_per_month: number | null
    price_lrd_cents: number
  }
}

export async function fetchCompanySettings(companyId: string): Promise<CompanySettings> {
  const { data, error } = await supabase
    .from('companies')
    .select(
      `id, name, slug, phone, email, address, status, sms_credits,
      allow_smartphone_riders, allow_button_phone_riders, enable_rider_sms,
      enable_rider_ussd, require_otp_button_phone_delivery,
      subscriptions(name, slug, max_riders, max_deliveries_per_month, price_lrd_cents)`,
    )
    .eq('id', companyId)
    .single()

  if (error) throw error

  const subRaw = data.subscriptions as
    | CompanySettings['subscription']
    | CompanySettings['subscription'][]
    | null
  const subscription = Array.isArray(subRaw) ? subRaw[0] : subRaw

  if (!subscription) throw new Error('Subscription not found')

  return {
    id: data.id,
    name: data.name,
    slug: data.slug,
    phone: data.phone,
    email: data.email,
    address: data.address,
    status: data.status,
    sms_credits: data.sms_credits,
    allow_smartphone_riders: data.allow_smartphone_riders ?? true,
    allow_button_phone_riders: data.allow_button_phone_riders ?? true,
    enable_rider_sms: data.enable_rider_sms ?? true,
    enable_rider_ussd: data.enable_rider_ussd ?? true,
    require_otp_button_phone_delivery: data.require_otp_button_phone_delivery ?? false,
    subscription,
  }
}

export async function updateCompanySettings(
  companyId: string,
  patch: {
    name?: string
    phone?: string
    email?: string
    address?: string | null
  },
) {
  const { data, error } = await supabase
    .from('companies')
    .update(patch)
    .eq('id', companyId)
    .select('id')
    .single()

  if (error) throw error
  return data
}

export async function updateCompanyRiderChannelSettings(
  companyId: string,
  settings: {
    allow_smartphone_riders?: boolean
    allow_button_phone_riders?: boolean
    enable_rider_sms?: boolean
    enable_rider_ussd?: boolean
    require_otp_button_phone_delivery?: boolean
  },
) {
  const { data, error } = await supabase.rpc('update_company_rider_channel_settings', {
    p_company_id: companyId,
    p_settings: settings,
  })
  if (error) throw error
  return data
}

export async function updateMyProfile(patch: { full_name?: string; phone?: string | null }) {
  const { data: session } = await supabase.auth.getSession()
  const userId = session.session?.user?.id
  if (!userId) throw new Error('Not signed in')

  const { data, error } = await supabase
    .from('profiles')
    .update(patch)
    .eq('id', userId)
    .select()
    .single()

  if (error) throw error
  return data
}

export type PaymentListRow = {
  id: string
  company_id: string
  delivery_id: string
  amount_lrd_cents: number
  status: string
  collected_at: string | null
  deposited_at: string | null
  created_at: string
  deliveries: {
    tracking_code: string
    customer_name: string
  } | {
    tracking_code: string
    customer_name: string
  }[] | null
}

export async function listCompanyPayments(companyId: string) {
  const { data, error } = await supabase
    .from('payments')
    .select(
      'id, company_id, delivery_id, amount_lrd_cents, status, collected_at, deposited_at, created_at, deliveries(tracking_code, customer_name)',
    )
    .eq('company_id', companyId)
    .order('created_at', { ascending: false })
    .limit(100)

  if (error) throw error
  return (data ?? []) as PaymentListRow[]
}

export async function markPaymentDeposited(paymentId: string) {
  const { data, error } = await supabase.rpc('mark_payment_deposited', {
    p_payment_id: paymentId,
  })
  if (error) throw error
  return data
}

export async function fetchCompanyPlanUsageExtended(companyId: string): Promise<
  CompanyPlanUsage & {
    max_deliveries_per_month: number | null
    price_lrd_cents: number
  }
> {
  const settings = await fetchCompanySettings(companyId)
  const { count, error } = await supabase
    .from('riders')
    .select('*', { count: 'exact', head: true })
    .eq('company_id', companyId)

  if (error) throw error

  return {
    company_id: settings.id,
    status: settings.status,
    sms_credits: settings.sms_credits,
    rider_count: count ?? 0,
    max_riders: settings.subscription.max_riders,
    plan_name: settings.subscription.name,
    max_deliveries_per_month: settings.subscription.max_deliveries_per_month,
    price_lrd_cents: settings.subscription.price_lrd_cents,
  }
}
