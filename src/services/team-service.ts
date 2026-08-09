import { supabase } from '@/lib/supabase/client'
import { normalizePhoneE164 } from '@/lib/phone'
import type { CompanyRole } from '@/types/supabase'

export type TeamMember = {
  id: string
  user_id: string
  role: CompanyRole
  is_active: boolean
  created_at: string
  email: string
  full_name: string | null
}

export type PendingInvitation = {
  id: string
  email: string | null
  invite_phone: string | null
  role: CompanyRole
  token: string
  expires_at: string
  created_at: string
  revoked_at: string | null
  accepted_at: string | null
}

export type CreateInvitationResult = {
  id: string
  token: string
  email: string | null
  invite_phone: string | null
  role: CompanyRole
  expires_at: string
}

export async function fetchTeam(companyId: string) {
  const { data, error } = await supabase.rpc('list_company_team', {
    p_company_id: companyId,
  })
  if (error) throw error
  return (data ?? []) as TeamMember[]
}

export async function fetchInvitations(companyId: string) {
  const { data, error } = await supabase.rpc('list_company_invitations', {
    p_company_id: companyId,
  })
  if (error) throw error
  return (data ?? []) as PendingInvitation[]
}

export async function createInvitation(
  companyId: string,
  input: { phone: string; role: CompanyRole; email?: string },
) {
  const { data, error } = await supabase.rpc('create_company_invitation', {
    p_company_id: companyId,
    p_role: input.role,
    p_email: input.email?.trim() || null,
    p_phone: normalizePhoneE164(input.phone),
  })
  if (error) throw error
  return data as CreateInvitationResult
}

export async function revokeInvitation(invitationId: string) {
  const { error } = await supabase.rpc('revoke_company_invitation', {
    p_invitation_id: invitationId,
  })
  if (error) throw error
}

export async function acceptInvitation(token: string) {
  const { data, error } = await supabase.rpc('accept_company_invitation', {
    p_token: token,
  })
  if (error) throw error
  return data as { company_id: string; role: CompanyRole }
}

export async function fetchInvitationPreview(token: string) {
  const { data, error } = await supabase.rpc('get_invitation_by_token', {
    p_token: token,
  })
  if (error) throw error
  return data as {
    email: string | null
    invite_phone: string | null
    role: CompanyRole
    company_name: string
    expires_at: string
  }
}

export async function setMemberActive(membershipId: string, isActive: boolean) {
  const { data, error } = await supabase.rpc('set_company_member_active', {
    p_membership_id: membershipId,
    p_is_active: isActive,
  })
  if (error) throw error
  return data
}

export async function updateMemberRole(membershipId: string, role: CompanyRole) {
  const { data, error } = await supabase.rpc('update_company_member_role', {
    p_membership_id: membershipId,
    p_role: role,
  })
  if (error) throw error
  return data
}
