import { Navigate } from 'react-router-dom'
import { useAuth } from '@/hooks/use-auth'
import { resolvePostAuthPath } from '@/lib/post-auth-navigation'
import { fetchAuthContext } from '@/hooks/use-auth-context'
import { useEffect, useState } from 'react'
import { HomePage } from '@/pages/marketing/home'

/** `/` — landing for guests; app home for signed-in users. */
export function MarketingRootPage() {
  const { user, loading, contextLoading, context } = useAuth()
  const [dest, setDest] = useState<string | null>(null)

  useEffect(() => {
    if (loading || contextLoading || !user) return
    if (context) {
      setDest(resolvePostAuthPath(user, context))
      return
    }
    let cancelled = false
    void fetchAuthContext(user.id).then((ctx) => {
      if (!cancelled) setDest(resolvePostAuthPath(user, ctx))
    })
    return () => {
      cancelled = true
    }
  }, [user, loading, contextLoading, context])

  if (loading || contextLoading) {
    return (
      <div className="flex min-h-[50vh] items-center justify-center text-sm text-zinc-500">Loading…</div>
    )
  }

  if (user && dest) {
    return <Navigate to={dest} replace />
  }

  if (user) {
    return (
      <div className="flex min-h-[50vh] items-center justify-center text-sm text-zinc-500">Opening your workspace…</div>
    )
  }

  return <HomePage />
}
