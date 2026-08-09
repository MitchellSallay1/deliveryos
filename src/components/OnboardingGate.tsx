import { Navigate, Outlet } from 'react-router-dom'
import { useEffect, useState } from 'react'
import { useAuth } from '@/hooks/use-auth'
import { completePendingOnboardingIfNeeded } from '@/services/onboarding-service'
import { hasPendingOnboardingMetadata, isRiderPersona } from '@/types/onboarding'

/** Company/merchant workspace provisioning — not for rider personas. */
export function OnboardingGate() {
  const { user, context, contextLoading, refreshContext } = useAuth()
  const [resolving, setResolving] = useState(false)
  const [attempted, setAttempted] = useState(false)

  useEffect(() => {
    if (!user || contextLoading || resolving || attempted) return
    if (context?.profile?.is_super_admin) return
    if (isRiderPersona(user)) return
    if ((context?.memberships.length ?? 0) > 0) return
    if (!hasPendingOnboardingMetadata(user)) return

    setResolving(true)
    void completePendingOnboardingIfNeeded(user)
      .then(() => refreshContext())
      .finally(() => {
        setResolving(false)
        setAttempted(true)
      })
  }, [user, context, contextLoading, resolving, attempted, refreshContext])

  if (isRiderPersona(user)) {
    return <Outlet />
  }

  if (contextLoading || resolving) {
    return (
      <div className="flex min-h-[40vh] items-center justify-center text-sm text-[var(--color-muted)]">
        Completing workspace setup…
      </div>
    )
  }

  if (user && !context?.profile?.is_super_admin && (context?.memberships.length ?? 0) === 0) {
    if (hasPendingOnboardingMetadata(user) && !attempted) {
      return (
        <div className="flex min-h-[40vh] items-center justify-center text-sm text-[var(--color-muted)]">
          Completing workspace setup…
        </div>
      )
    }
    if (!hasPendingOnboardingMetadata(user) || attempted) {
      return <Navigate to="/setup" replace />
    }
  }

  return <Outlet />
}
