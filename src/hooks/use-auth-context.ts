import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase/client'
import type { AuthContext, CompanyRole, Profile } from '@/types/database'

export async function fetchAuthContext(userId: string): Promise<AuthContext> {
  const { data: profile, error: profileError } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', userId)
    .maybeSingle()

  if (profileError) throw profileError

  const { data: membershipsRaw, error: membersError } = await supabase
    .from('company_users')
    .select('id, company_id, user_id, role, is_active, created_at')
    .eq('user_id', userId)
    .eq('is_active', true)

  if (membersError) throw membersError

  const companyIds = [...new Set((membershipsRaw ?? []).map((m) => m.company_id))]
  let companiesById = new Map<string, AuthContext['memberships'][0]['company']>()

  if (companyIds.length > 0) {
    const { data: companies, error: companiesError } = await supabase
      .from('companies')
      .select('id, name, slug, status, business_type')
      .in('id', companyIds)
    if (companiesError) throw companiesError
    companiesById = new Map(
      (companies ?? []).map((c) => [c.id, c as AuthContext['memberships'][0]['company']]),
    )
  }

  const memberships = (membershipsRaw ?? [])
    .map((row) => {
      const company = companiesById.get(row.company_id)
      if (!company) return null
      return {
        id: row.id,
        company_id: row.company_id,
        user_id: row.user_id,
        role: row.role as CompanyRole,
        is_active: row.is_active,
        created_at: row.created_at,
        company,
      }
    })
    .filter((m): m is AuthContext['memberships'][0] => m !== null)

  const storedCompanyId = localStorage.getItem('deliveryos_active_company_id')
  const activeMembership =
    memberships.find((m) => m.company_id === storedCompanyId) ?? memberships[0]

  const p = profile as Profile | null

  return {
    profile: p,
    memberships,
    activeCompanyId: activeMembership?.company_id ?? null,
    activeRole: p?.is_super_admin
      ? 'super_admin'
      : (activeMembership?.role ?? null),
  }
}

export function useAuthContext(userId: string | undefined) {
  return useQuery({
    queryKey: ['auth-context', userId],
    queryFn: () => fetchAuthContext(userId!),
    enabled: !!userId,
    staleTime: 60_000,
  })
}

export function setActiveCompanyId(companyId: string) {
  localStorage.setItem('deliveryos_active_company_id', companyId)
}
