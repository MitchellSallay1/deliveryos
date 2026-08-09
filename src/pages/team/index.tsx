import { useState } from 'react'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { useAccess } from '@/hooks/use-access'
import { useAuth } from '@/hooks/use-auth'
import { useTeam, useTeamActions, useTeamInvitations } from '@/hooks/use-team'
import { parseSupabaseError } from '@/lib/supabase-errors'
import type { CompanyRole } from '@/types/supabase'

const INVITE_ROLES: CompanyRole[] = ['dispatcher', 'support_staff', 'rider']

export function TeamPage() {
  const { context } = useAuth()
  const companyId = context?.activeCompanyId ?? null
  const { can } = useAccess()

  const { data: members = [], isLoading } = useTeam(companyId)
  const { data: invitations = [] } = useTeamInvitations(companyId)
  const { invite, revoke, toggleActive, changeRole } = useTeamActions(companyId)

  const [phone, setPhone] = useState('')
  const [role, setRole] = useState<CompanyRole>('dispatcher')
  const [error, setError] = useState<string | null>(null)
  const [lastLink, setLastLink] = useState<string | null>(null)

  if (!companyId) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Team</CardTitle>
          <CardDescription>Select a workspace to manage team members.</CardDescription>
        </CardHeader>
      </Card>
    )
  }

  if (!can('page:team')) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Team</CardTitle>
          <CardDescription>You do not have access to team management.</CardDescription>
        </CardHeader>
      </Card>
    )
  }

  async function onInvite(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    setLastLink(null)
    try {
      const result = await invite.mutateAsync({ phone, role })
      const origin = window.location.origin
      setLastLink(`${origin}/invite/${result.token}`)
      setPhone('')
    } catch (err) {
      setError(parseSupabaseError(err))
    }
  }

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      {can('page:team:manage') && (
        <Card>
          <CardHeader>
            <CardTitle>Invite teammate</CardTitle>
            <CardDescription>Share the invite link or ask them to sign in with the invited phone number.</CardDescription>
          </CardHeader>
          <CardContent>
            <form className="flex flex-col gap-3 sm:flex-row sm:items-end" onSubmit={onInvite}>
              <div className="flex-1 space-y-2">
                <Label htmlFor="phone">Mobile number</Label>
                <Input
                  id="phone"
                  type="tel"
                  inputMode="tel"
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  placeholder="+231 88 …"
                  required
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="role">Role</Label>
                <select
                  id="role"
                  className="h-10 rounded-md border px-3 text-sm"
                  value={role}
                  onChange={(e) => setRole(e.target.value as CompanyRole)}
                >
                  {INVITE_ROLES.map((r) => (
                    <option key={r} value={r}>
                      {r.replace(/_/g, ' ')}
                    </option>
                  ))}
                </select>
              </div>
              <Button type="submit" disabled={invite.isPending}>
                Create invite
              </Button>
            </form>
            {lastLink && (
              <p className="mt-3 break-all text-xs text-teal-800">
                Invite link: <a href={lastLink}>{lastLink}</a>
              </p>
            )}
            {error && <p className="mt-2 text-sm text-red-600">{error}</p>}
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader>
          <CardTitle>Pending invitations</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2 text-sm">
          {invitations.length === 0 && (
            <p className="text-[var(--color-muted)]">No pending invitations.</p>
          )}
          {invitations.map((inv) => (
            <div key={inv.id} className="flex flex-wrap items-center justify-between gap-2 border-b py-2">
              <div>
                <div>{inv.invite_phone ?? inv.email ?? '—'}</div>
                <div className="text-xs capitalize text-[var(--color-muted)]">{inv.role.replace(/_/g, ' ')}</div>
              </div>
              {can('page:team:manage') && (
                <Button
                  type="button"
                  size="sm"
                  variant="outline"
                  onClick={() => revoke.mutate(inv.id)}
                >
                  Revoke
                </Button>
              )}
            </div>
          ))}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Members</CardTitle>
        </CardHeader>
        <CardContent>
          {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
          <table className="w-full text-left text-sm">
            <thead>
              <tr className="border-b text-xs uppercase text-[var(--color-muted)]">
                <th className="py-2">User</th>
                <th className="py-2">Role</th>
                <th className="py-2">Status</th>
                {can('page:team:manage') && <th className="py-2">Actions</th>}
              </tr>
            </thead>
            <tbody>
              {members.map((m) => (
                <tr key={m.id} className="border-b">
                  <td className="py-2">
                    <div>{m.full_name ?? '—'}</div>
                    <div className="text-xs text-[var(--color-muted)]">{m.email}</div>
                  </td>
                  <td className="py-2">
                    {can('page:team:manage') ? (
                      <select
                        className="h-8 rounded-md border px-2 text-xs capitalize"
                        value={m.role}
                        onChange={(e) =>
                          changeRole.mutate({ id: m.id, role: e.target.value as CompanyRole })
                        }
                      >
                        {(['company_owner', ...INVITE_ROLES] as CompanyRole[]).map((r) => (
                          <option key={r} value={r}>
                            {r.replace(/_/g, ' ')}
                          </option>
                        ))}
                      </select>
                    ) : (
                      <span className="capitalize">{m.role.replace(/_/g, ' ')}</span>
                    )}
                  </td>
                  <td className="py-2">{m.is_active ? 'Active' : 'Disabled'}</td>
                  {can('page:team:manage') && (
                    <td className="py-2">
                      <Button
                        type="button"
                        size="sm"
                        variant="outline"
                        onClick={() => toggleActive.mutate({ id: m.id, isActive: !m.is_active })}
                      >
                        {m.is_active ? 'Disable' : 'Enable'}
                      </Button>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </CardContent>
      </Card>
    </div>
  )
}
