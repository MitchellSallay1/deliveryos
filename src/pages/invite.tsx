import { useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { useAuth } from '@/hooks/use-auth'
import { useAcceptInvitation, useInvitationPreview } from '@/hooks/use-team'
import { parseSupabaseError } from '@/lib/supabase-errors'
import { defaultHomeForRole } from '@/lib/rbac'
import { normalizePhoneE164, phoneMatchesMsisdn } from '@/lib/phone'

export function InvitePage() {
  const { token } = useParams()
  const navigate = useNavigate()
  const { user, context } = useAuth()
  const { data: preview, error: previewError, isLoading } = useInvitationPreview(token)
  const accept = useAcceptInvitation()
  const [error, setError] = useState<string | null>(null)

  const invitedPhone = preview?.invite_phone ?? null
  const userPhone = user?.phone ? normalizePhoneE164(user.phone) : null
  const phoneMatches =
    invitedPhone && userPhone ? phoneMatchesMsisdn(invitedPhone, userPhone) : false
  const emailMatches =
    preview?.email && user?.email
      ? user.email.toLowerCase() === preview.email.toLowerCase()
      : false
  const canAccept = Boolean(user && (phoneMatches || emailMatches))

  async function onAccept() {
    if (!token) return
    setError(null)
    try {
      const result = await accept.mutateAsync(token)
      localStorage.setItem('deliveryos_active_company_id', result.company_id)
      navigate(defaultHomeForRole(context?.activeRole ?? result.role))
    } catch (err) {
      setError(parseSupabaseError(err))
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-[var(--color-background)] p-4">
      <Card className="w-full max-w-md">
        <CardHeader>
          <CardTitle>Join workspace</CardTitle>
          <CardDescription>DeliveryOS team invitation</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4 text-sm">
          {isLoading && <p className="text-[var(--color-muted)]">Loading invitation…</p>}
          {previewError && (
            <p className="text-red-600">{parseSupabaseError(previewError)}</p>
          )}
          {preview && (
            <>
              <p>
                You are invited to <strong>{preview.company_name}</strong> as{' '}
                <strong className="capitalize">{preview.role.replace(/_/g, ' ')}</strong>.
              </p>
              {invitedPhone ? (
                <p className="text-[var(--color-muted)]">Phone: {invitedPhone}</p>
              ) : preview.email ? (
                <p className="text-[var(--color-muted)]">Email: {preview.email}</p>
              ) : null}
              {!user && (
                <p>
                  <Link to={`/login?redirect=/invite/${token}`} className="text-[var(--color-primary)] underline">
                    Sign in with your phone
                  </Link>{' '}
                  using the invited number to accept.
                </p>
              )}
              {user && !canAccept && (
                <p className="text-amber-700">
                  Sign out and sign in with the invited phone number
                  {invitedPhone ? ` (${invitedPhone})` : ''} to accept.
                </p>
              )}
              {canAccept && (
                <Button type="button" className="w-full" disabled={accept.isPending} onClick={() => void onAccept()}>
                  {accept.isPending ? 'Joining…' : 'Accept invitation'}
                </Button>
              )}
            </>
          )}
          {error && <p className="text-red-600">{error}</p>}
        </CardContent>
      </Card>
    </div>
  )
}
