import { useEffect, useState } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { PhoneOtpFlow } from '@/components/PhoneOtpFlow'
import { completeRiderPhoneSignup } from '@/services/auth-service'
import { riderRegisterSchema } from '@/utils/auth-schemas'
import { resolvePostAuthPath } from '@/lib/post-auth-navigation'
import { fetchAuthContext } from '@/hooks/use-auth-context'
import { useAuth } from '@/hooks/use-auth'
import { isRiderLinked } from '@/lib/post-auth-navigation'

export function RegisterRiderPage() {
  const navigate = useNavigate()
  const [search] = useSearchParams()
  const inviteFromUrl = search.get('invite') ?? ''
  const { user, loading: authLoading, context, contextLoading, refreshContext } = useAuth()
  const [error, setError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)
  const [verified, setVerified] = useState(false)

  useEffect(() => {
    if (inviteFromUrl) {
      sessionStorage.setItem('deliveryos_rider_invite', inviteFromUrl)
    }
  }, [inviteFromUrl])

  useEffect(() => {
    if (authLoading || contextLoading) return
    if (!user) return
    if (isRiderLinked(context)) {
      navigate('/my-jobs', { replace: true })
      return
    }
    setVerified(true)
  }, [user, authLoading, context, contextLoading, navigate])

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    setError(null)
    const fd = new FormData(e.currentTarget)
    const parsed = riderRegisterSchema.safeParse({
      fullName: fd.get('fullName'),
    })
    if (!parsed.success) {
      setError(parsed.error.issues[0]?.message ?? 'Invalid form')
      return
    }
    setSubmitting(true)
    try {
      await completeRiderPhoneSignup(parsed.data.fullName)
      await refreshContext()
      const ctx = await fetchAuthContext(user!.id)
      navigate(resolvePostAuthPath(user!, ctx), { replace: true })
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Registration failed')
    } finally {
      setSubmitting(false)
    }
  }

  if (authLoading || contextLoading) {
    return <p className="text-sm text-[var(--color-muted)]">Loading…</p>
  }

  if (!user || !verified) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Register as a rider</CardTitle>
          <CardDescription>
            Verify the phone number your dispatcher registered for you.
            {inviteFromUrl ? (
              <span className="mt-1 block text-teal-800">Invite code: {inviteFromUrl.toUpperCase()}</span>
            ) : null}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <PhoneOtpFlow onVerified={async () => {
            await refreshContext()
            setVerified(true)
          }} />
          <p className="mt-4 text-center text-sm text-[var(--color-muted)]">
            <Link to="/register" className="text-[var(--color-primary)] hover:underline">
              Back
            </Link>
          </p>
        </CardContent>
      </Card>
    )
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Your name</CardTitle>
        <CardDescription>Then link your rider profile with your invite code.</CardDescription>
      </CardHeader>
      <CardContent>
        <form className="grid gap-3" onSubmit={onSubmit}>
          {error && <p className="text-sm text-red-600">{error}</p>}
          <div className="space-y-2">
            <Label htmlFor="fullName">Full name</Label>
            <Input id="fullName" name="fullName" required disabled={submitting} />
          </div>
          <Button type="submit" className="w-full" disabled={submitting}>
            {submitting ? 'Continuing…' : 'Continue to link rider'}
          </Button>
        </form>
      </CardContent>
    </Card>
  )
}
