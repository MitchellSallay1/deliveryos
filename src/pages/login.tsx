import { useState } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { PhoneOtpFlow } from '@/components/PhoneOtpFlow'
import { completePendingOnboardingIfNeeded, OnboardingError } from '@/services/onboarding-service'
import { fetchAuthContext } from '@/hooks/use-auth-context'
import { useAuth } from '@/hooks/use-auth'
import { resolvePostAuthPath } from '@/lib/post-auth-navigation'
import { safeInternalRedirect } from '@/lib/safe-redirect'
import { supabase } from '@/lib/supabase/client'

export function LoginPage() {
  const navigate = useNavigate()
  const [search] = useSearchParams()
  const redirectAfterLogin = safeInternalRedirect(search.get('redirect'))
  const { refreshContext } = useAuth()
  const [error, setError] = useState<string | null>(null)

  async function afterOtp() {
    setError(null)
    try {
      await refreshContext()
      const { data } = await supabase.auth.getSession()
      const user = data.session?.user
      if (!user) throw new Error('Sign in failed')

      try {
        await completePendingOnboardingIfNeeded(user)
      } catch (onboardingErr) {
        if (onboardingErr instanceof OnboardingError) {
          setError(onboardingErr.message)
          return
        }
        throw onboardingErr
      }

      await refreshContext()
      if (redirectAfterLogin) {
        navigate(redirectAfterLogin, { replace: true })
        return
      }
      const ctx = await fetchAuthContext(user.id)
      navigate(resolvePostAuthPath(user, ctx), { replace: true })
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Sign in failed')
    }
  }

  return (
    <Card className="border-zinc-200/80 shadow-lg">
      <CardHeader className="text-center sm:text-left">
        <CardTitle className="text-2xl">DeliveryOS</CardTitle>
        <CardDescription>Sign in with your mobile number</CardDescription>
      </CardHeader>
      <CardContent>
        {error && <p className="mb-3 text-sm text-red-600">{error}</p>}
        <PhoneOtpFlow
          title="Sign in"
          submitLabel="Send verification code"
          onVerified={afterOtp}
        />
        <p className="mt-4 text-center text-sm text-[var(--color-muted)]">
          New here?{' '}
          <Link to="/register" className="text-[var(--color-primary)] hover:underline">
            Choose how you use DeliveryOS
          </Link>
        </p>
      </CardContent>
    </Card>
  )
}
