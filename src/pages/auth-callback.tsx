import { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { supabase } from '@/lib/supabase/client'
import { resolvePostAuthPath } from '@/lib/post-auth-navigation'
import { completePendingOnboarding, OnboardingError } from '@/services/onboarding-service'
import { fetchAuthContext } from '@/hooks/use-auth-context'
import { useAuth } from '@/hooks/use-auth'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'

type CallbackState = 'processing' | 'completing' | 'done' | 'error'

export function AuthCallbackPage() {
  const navigate = useNavigate()
  const { refreshContext } = useAuth()
  const [state, setState] = useState<CallbackState>('processing')
  const [message, setMessage] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false

    async function run() {
      try {
        const params = new URLSearchParams(window.location.search)
        const code = params.get('code')
        if (code) {
          const { error } = await supabase.auth.exchangeCodeForSession(code)
          if (error) throw error
        }

        let session = (await supabase.auth.getSession()).data.session
        for (let attempt = 0; !session && attempt < 24; attempt += 1) {
          await new Promise((r) => setTimeout(r, 250))
          session = (await supabase.auth.getSession()).data.session
        }

        if (!session?.user) {
          if (!cancelled) {
            setState('error')
            setMessage(
              'This confirmation link is invalid or expired. Sign in or register again to continue.',
            )
          }
          return
        }

        if (!cancelled) setState('completing')

        const onboarding = await completePendingOnboarding()
        if (onboarding.status === 'pending_metadata_missing') {
          if (!cancelled) navigate('/setup', { replace: true })
          return
        }

        await refreshContext()
        const ctx = await fetchAuthContext(session.user.id)
        if (!cancelled) {
          setState('done')
          navigate(resolvePostAuthPath(session.user, ctx), { replace: true })
        }
      } catch (err) {
        if (cancelled) return
        setState('error')
        if (err instanceof OnboardingError) {
          setMessage(err.message)
        } else if (err instanceof Error) {
          setMessage(err.message)
        } else {
          setMessage('Could not finish sign-in. Try again from the login page.')
        }
      }
    }

    void run()
    return () => {
      cancelled = true
    }
  }, [navigate, refreshContext])

  return (
    <Card>
      <CardHeader>
        <CardTitle>
          {state === 'error' ? 'Sign-in problem' : state === 'completing' ? 'Completing setup' : 'Finishing sign-in'}
        </CardTitle>
        <CardDescription>
          {state === 'processing' && 'Processing your link…'}
          {state === 'completing' && 'DeliveryOS is finishing your workspace…'}
          {state === 'done' && 'Redirecting…'}
          {state === 'error' && (message ?? 'Something went wrong.')}
        </CardDescription>
      </CardHeader>
      {state === 'error' && (
        <CardContent className="flex flex-col gap-3">
          <Link to="/login">
            <Button type="button" variant="outline" className="w-full">
              Go to sign in
            </Button>
          </Link>
          <Link to="/register">
            <Button type="button" className="w-full">
              Register again
            </Button>
          </Link>
        </CardContent>
      )}
    </Card>
  )
}
