import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { CompanyRole } from '@/types/supabase'
import {
  acceptInvitation,
  createInvitation,
  fetchInvitationPreview,
  fetchInvitations,
  fetchTeam,
  revokeInvitation,
  setMemberActive,
  updateMemberRole,
} from '@/services/team-service'

export function useTeam(companyId: string | null) {
  return useQuery({
    queryKey: ['team', companyId],
    queryFn: () => fetchTeam(companyId!),
    enabled: !!companyId,
  })
}

export function useTeamInvitations(companyId: string | null) {
  return useQuery({
    queryKey: ['team-invitations', companyId],
    queryFn: () => fetchInvitations(companyId!),
    enabled: !!companyId,
  })
}

export function useTeamActions(companyId: string | null) {
  const queryClient = useQueryClient()
  const invalidate = () => {
    void queryClient.invalidateQueries({ queryKey: ['team', companyId] })
    void queryClient.invalidateQueries({ queryKey: ['team-invitations', companyId] })
    void queryClient.invalidateQueries({ queryKey: ['auth-context'] })
  }

  const invite = useMutation({
    mutationFn: ({ phone, role }: { phone: string; role: CompanyRole }) =>
      createInvitation(companyId!, { phone, role }),
    onSuccess: invalidate,
  })

  const revoke = useMutation({
    mutationFn: (invitationId: string) => revokeInvitation(invitationId),
    onSuccess: invalidate,
  })

  const toggleActive = useMutation({
    mutationFn: ({ id, isActive }: { id: string; isActive: boolean }) =>
      setMemberActive(id, isActive),
    onSuccess: invalidate,
  })

  const changeRole = useMutation({
    mutationFn: ({ id, role }: { id: string; role: CompanyRole }) =>
      updateMemberRole(id, role),
    onSuccess: invalidate,
  })

  return { invite, revoke, toggleActive, changeRole }
}

export function useInvitationPreview(token: string | undefined) {
  return useQuery({
    queryKey: ['invitation-preview', token],
    queryFn: () => fetchInvitationPreview(token!),
    enabled: !!token,
    retry: false,
  })
}

export function useAcceptInvitation() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (token: string) => acceptInvitation(token),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['auth-context'] })
    },
  })
}
