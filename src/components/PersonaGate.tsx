import { Navigate, Outlet, useLocation } from 'react-router-dom'
import { useAuth } from '@/hooks/use-auth'
import { defaultHomeForRole } from '@/lib/rbac'
import { isCompanyWorkspaceUser, isRiderLinked } from '@/lib/post-auth-navigation'
import { isRiderPersona } from '@/types/onboarding'

const RIDER_PATHS = ['/my-jobs', '/rider/profile', '/link-rider']
const COMPANY_PREFIX_BLOCK_FOR_RIDER = [
  '/dashboard',
  '/deliveries',
  '/riders',
  '/customers',
  '/reports',
  '/billing',
  '/settings',
  '/team',
  '/operations',
  '/merchant',
  '/marketplace',
  '/notifications',
  '/live-map',
]

/** Routes authenticated users to the correct shell (company vs rider). */
export function PersonaGate() {
  const { user, context, loading, contextLoading } = useAuth()
  const { pathname } = useLocation()

  if (loading || contextLoading) {
    return (
      <div className="flex min-h-[40vh] items-center justify-center text-sm text-[var(--color-muted)]">
        Loading…
      </div>
    )
  }

  if (!user) {
    return <Navigate to="/login" replace />
  }

  const riderPersona = isRiderPersona(user)
  const linked = isRiderLinked(context)
  const role = context?.activeRole ?? null
  const isRiderSession = riderPersona || role === 'rider'

  if (riderPersona && !linked && pathname !== '/link-rider') {
    return <Navigate to="/link-rider" replace />
  }

  if (isRiderSession && linked) {
    const onRiderRoute = RIDER_PATHS.some((p) => pathname === p || pathname.startsWith(`${p}/`))
    const onBlockedCompanyRoute = COMPANY_PREFIX_BLOCK_FOR_RIDER.some(
      (p) => pathname === p || pathname.startsWith(`${p}/`),
    )
    if (onBlockedCompanyRoute) {
      return <Navigate to="/my-jobs" replace />
    }
    if (!onRiderRoute && pathname !== '/link-rider') {
      return <Navigate to="/my-jobs" replace />
    }
  }

  if (!isRiderSession && isCompanyWorkspaceUser(context) && pathname.startsWith('/link-rider')) {
    return <Navigate to={defaultHomeForRole(role)} replace />
  }

  return <Outlet />
}
