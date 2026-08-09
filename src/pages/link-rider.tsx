import { useEffect, useState } from 'react'
import { Navigate, useNavigate } from 'react-router-dom'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { useAuth } from '@/hooks/use-auth'
import { useLinkRiderAccount } from '@/hooks/use-rider-portal'
import { linkRiderSchema } from '@/utils/auth-schemas'
import { isRiderLinked, resolvePostAuthPath } from '@/lib/post-auth-navigation'
import { fetchAuthContext } from '@/hooks/use-auth-context'
import { isRiderPersona } from '@/types/onboarding'
import { parseSupabaseError } from '@/lib/supabase-errors'

export function LinkRiderPage() {
  const navigate = useNavigate()
  const { user, context, loading, contextLoading, refreshContext } = useAuth()
  const linkMutation = useLinkRiderAccount()
  const [error, setError] = useState<string | null>(null)

  const storedInvite =
    typeof sessionStorage !== 'undefined'
      ? sessionStorage.getItem('deliveryos_rider_invite') ?? ''
      : ''

  useEffect(() => {
    if (!loading && !contextLoading && !user) return
    if (user && context && isRiderLinked(context)) {
      navigate('/my-jobs', { replace: true })
    }
  }, [user, context, loading, contextLoading, navigate])

  if (loading || contextLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center text-sm text-[var(--color-muted)]">
        Loading…
      </div>
    )
  }

  if (!user) {
    return <Navigate to="/login" replace />
  }

  if (context && isRiderLinked(context)) {
    return <Navigate to="/my-jobs" replace />
  }

  if (!isRiderPersona(user) && (context?.memberships.length ?? 0) > 0) {
    return <Navigate to="/dashboard" replace />
  }

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    setError(null)
    const fd = new FormData(e.currentTarget)
    const parsed = linkRiderSchema.safeParse({
      riderCode: fd.get('riderCode') || undefined,
      inviteCode: fd.get('inviteCode') || undefined,
    })
    if (!parsed.success) {
      setError(parsed.error.issues[0]?.message ?? 'Invalid form')
      return
    }
    try {
      await linkMutation.mutateAsync({
        riderCode: parsed.data.riderCode,
        inviteCode: parsed.data.inviteCode,
      })
      sessionStorage.removeItem('deliveryos_rider_invite')
      await refreshContext()
      const ctx = await fetchAuthContext(user!.id)
      navigate(resolvePostAuthPath(user!, ctx), { replace: true })
    } catch (err) {
      setError(parseSupabaseError(err))
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-[var(--color-background)] p-4">
      <div className="w-full max-w-md">
        <Card>
          <CardHeader>
            <CardTitle>Link your rider profile</CardTitle>
            <CardDescription>
              Enter the rider ID from your company or the invite code they sent you. Your profile
              phone in Settings must match the rider record when using rider ID only.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <form className="space-y-4" onSubmit={onSubmit}>
              {error && <p className="text-sm text-red-600">{error}</p>}
              <div className="space-y-2">
                <Label htmlFor="inviteCode">Invite code</Label>
                <Input
                  id="inviteCode"
                  name="inviteCode"
                  placeholder="RDR-83KD"
                  defaultValue={storedInvite}
                  disabled={linkMutation.isPending}
                />
              </div>
              <p className="text-center text-xs text-[var(--color-muted)]">or</p>
              <div className="space-y-2">
                <Label htmlFor="riderCode">Rider ID</Label>
                <Input
                  id="riderCode"
                  name="riderCode"
                  placeholder="R001"
                  disabled={linkMutation.isPending}
                />
              </div>
              <Button type="submit" className="w-full" disabled={linkMutation.isPending}>
                {linkMutation.isPending ? 'Linking…' : 'Link'}
              </Button>
            </form>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
