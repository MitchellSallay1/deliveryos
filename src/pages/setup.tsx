import { useEffect, useMemo, useState } from 'react'
import { Navigate, useNavigate } from 'react-router-dom'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { useAuth } from '@/hooks/use-auth'
import { fetchAuthContext } from '@/hooks/use-auth-context'
import { resolvePostAuthPath, shouldBlockCompanySetup } from '@/lib/post-auth-navigation'
import {
  createWorkspaceForAuthenticatedUser,
  OnboardingError,
} from '@/services/onboarding-service'
import { getSetupFormDefaults } from '@/types/onboarding'
import { setupWorkspaceSchema } from '@/utils/auth-schemas'

/** Authenticated user without a company — create workspace (not a new auth account). */
export function SetupPage() {
  const navigate = useNavigate()
  const { user, loading, context, contextLoading, refreshContext } = useAuth()
  const [error, setError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)

  const defaults = useMemo(() => getSetupFormDefaults(user), [user])

  useEffect(() => {
    if (loading || contextLoading || !user) return
    if (context?.profile?.is_super_admin) {
      navigate('/admin', { replace: true })
      return
    }
    if ((context?.memberships.length ?? 0) > 0) {
      navigate(resolvePostAuthPath(user, context!), { replace: true })
    }
  }, [user, loading, context, contextLoading, navigate])

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

  if (shouldBlockCompanySetup(user)) {
    return <Navigate to="/link-rider" replace />
  }

  if (context?.profile?.is_super_admin) {
    return <Navigate to="/admin" replace />
  }

  if ((context?.memberships.length ?? 0) > 0) {
    return <Navigate to="/dashboard" replace />
  }

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    setError(null)
    const fd = new FormData(e.currentTarget)
    const parsed = setupWorkspaceSchema.safeParse({
      companyName: fd.get('companyName'),
      businessType: fd.get('businessType'),
      companyPhone: fd.get('companyPhone') || undefined,
      companyEmail: fd.get('companyEmail') || undefined,
    })
    if (!parsed.success) {
      setError(parsed.error.issues[0]?.message ?? 'Invalid form')
      return
    }

    setSubmitting(true)
    try {
      await createWorkspaceForAuthenticatedUser(
        {
          companyName: parsed.data.companyName,
          businessType: parsed.data.businessType,
          companyPhone: parsed.data.companyPhone,
          companyEmail: parsed.data.companyEmail,
        },
        user!.email,
      )
      await refreshContext()
      const ctx = await fetchAuthContext(user!.id)
      navigate(resolvePostAuthPath(user!, ctx), { replace: true })
    } catch (err) {
      setError(
        err instanceof OnboardingError
          ? err.message
          : err instanceof Error
            ? err.message
            : 'Could not create workspace',
      )
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-[var(--color-background)] p-4">
      <div className="w-full max-w-md">
        <Card>
          <CardHeader>
            <CardTitle>Create your workspace</CardTitle>
            <CardDescription>
              You are signed in as <strong>{user.email}</strong>. Add your company details to start
              using DeliveryOS.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <form className="grid gap-3" onSubmit={onSubmit} key={user.id}>
              {error && <p className="text-sm text-red-600">{error}</p>}
              <div className="space-y-2">
                <Label htmlFor="companyName">Company name</Label>
                <Input
                  id="companyName"
                  name="companyName"
                  required
                  disabled={submitting}
                  defaultValue={defaults.companyName}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="businessType">Business type</Label>
                <select
                  id="businessType"
                  name="businessType"
                  className="w-full rounded-md border px-3 py-2 text-sm"
                  defaultValue={defaults.businessType}
                  required
                  disabled={submitting}
                >
                  <option value="logistics_provider">Delivery / courier company</option>
                  <option value="merchant">Online seller / merchant</option>
                  <option value="hybrid">Both (own riders + external providers)</option>
                </select>
              </div>
              <div className="space-y-2">
                <Label htmlFor="companyPhone">Company phone (optional)</Label>
                <Input
                  id="companyPhone"
                  name="companyPhone"
                  disabled={submitting}
                  defaultValue={defaults.companyPhone}
                  placeholder="+231…"
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="companyEmail">Company email (optional)</Label>
                <Input
                  id="companyEmail"
                  name="companyEmail"
                  type="email"
                  disabled={submitting}
                  defaultValue={defaults.companyEmail}
                  placeholder={user.email ?? 'billing@company.com'}
                />
              </div>
              <Button type="submit" className="w-full" disabled={submitting}>
                {submitting ? 'Creating workspace…' : 'Create workspace'}
              </Button>
            </form>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
