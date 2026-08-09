import { supabase } from '@/lib/supabase/client'

export type AdminCompany = {
  id: string
  name: string
  email: string
  phone: string
  status: string
  sms_credits: number
  subscription_id: string
  subscriptions: { name: string; slug: string } | { name: string; slug: string }[] | null
}

export async function fetchPlatformAnalytics() {
  const { data, error } = await supabase.rpc('get_platform_analytics')
  if (error) throw error
  return data as {
    companies_total: number
    companies_active: number
    companies_pending: number
    deliveries_today: number
    sms_sent: number
  }
}

export async function listAllCompanies() {
  const { data, error } = await supabase
    .from('companies')
    .select('id, name, email, phone, status, sms_credits, subscription_id, subscriptions(name, slug)')
    .order('created_at', { ascending: false })

  if (error) throw error
  return (data ?? []) as AdminCompany[]
}

export async function setCompanyStatus(companyId: string, status: 'pending' | 'active' | 'suspended') {
  const { error } = await supabase.rpc('admin_set_company_status', {
    p_company_id: companyId,
    p_status: status,
  })
  if (error) throw error
}

export async function adminTopUpSms(companyId: string, amount: number) {
  const { data, error } = await supabase.rpc('admin_add_sms_credits', {
    p_company_id: companyId,
    p_amount: amount,
    p_reason: 'admin_top_up',
  })
  if (error) throw error
  return data as number
}
