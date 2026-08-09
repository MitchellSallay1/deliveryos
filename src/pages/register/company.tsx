import { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { PhoneOtpFlow } from '@/components/PhoneOtpFlow'
import { finalizeOwnerWorkspaceAfterOtp } from '@/services/auth-service'
import { companyRegisterSchema } from '@/utils/auth-schemas'
import { resolveAuthenticatedRegisterRedirect, resolvePostAuthPath } from '@/lib/post-auth-navigation'
import { fetchAuthContext } from '@/hooks/use-auth-context'
import { useAuth } from '@/hooks/use-auth'
import { isRiderPersona } from '@/types/onboarding'

export function RegisterCompanyPage() {
  const navigate = useNavigate()
  const { user, loading: authLoading, context, contextLoading, refreshContext } = useAuth()
  const [error, setError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)
  const [verified, setVerified] = useState(false)

  useEffect(() => {
    if (authLoading || contextLoading) return
    if (!user) return
    if (isRiderPersona(user)) {
      navigate(resolveAuthenticatedRegisterRedirect(user, context), { replace: true })
      return
    }
    if ((context?.memberships.length ?? 0) > 0 || context?.profile?.is_super_admin) {
      navigate(resolveAuthenticatedRegisterRedirect(user, context), { replace: true })
      return
    }
    setVerified(true)
  }, [user, authLoading, context, contextLoading, navigate])

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    setError(null)
    const fd = new FormData(e.currentTarget)
    const parsed = companyRegisterSchema.safeParse({
      businessType: 'logistics_provider',
      companyName: fd.get('companyName'),
      companyPhone: fd.get('companyPhone'),
      companyEmail: fd.get('companyEmail') ?? '',
      fullName: fd.get('fullName'),
    })
    if (!parsed.success) {
      setError(parsed.error.issues[0]?.message ?? 'Invalid form')
      return
    }
    setSubmitting(true)
    try {
      const result = await finalizeOwnerWorkspaceAfterOtp(parsed.data)
      await refreshContext()
      const ctx = await fetchAuthContext(result.user.id)
      navigate(resolvePostAuthPath(result.user, ctx), { replace: true })
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
          <CardTitle>Register your delivery company</CardTitle>
          <CardDescription>Verify your phone to start your 7-day trial</CardDescription>
        </CardHeader>
        <CardContent>
          <PhoneOtpFlow
            submitLabel="Send verification code"
            onVerified={async () => {
              await refreshContext()
              setVerified(true)
            }}
          />
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
        <CardTitle>Company details</CardTitle>
        <CardDescription>7-day trial · dispatch, riders, and tracking</CardDescription>
      </CardHeader>
      <CardContent>
        <form className="grid gap-3" onSubmit={onSubmit}>
          {error && <p className="text-sm text-red-600">{error}</p>}
          <Field label="Company name" name="companyName" required disabled={submitting} />
          <div className="grid grid-cols-2 gap-3">
            <Field label="Company phone" name="companyPhone" required disabled={submitting} />
            <Field
              label="Company email (optional)"
              name="companyEmail"
              type="email"
              disabled={submitting}
            />
          </div>
          <Field label="Your name" name="fullName" required disabled={submitting} />
          <Button type="submit" className="w-full" disabled={submitting}>
            {submitting ? 'Creating workspace…' : 'Create workspace'}
          </Button>
          <p className="text-center text-sm text-[var(--color-muted)]">
            <Link to="/register" className="text-[var(--color-primary)] hover:underline">
              Back
            </Link>
          </p>
        </form>
      </CardContent>
    </Card>
  )
}

function Field(props: React.ComponentProps<typeof Input> & { label: string; name: string }) {
  const { label, name, ...rest } = props
  return (
    <div className="space-y-2">
      <Label htmlFor={name}>{label}</Label>
      <Input id={name} name={name} {...rest} />
    </div>
  )
}
