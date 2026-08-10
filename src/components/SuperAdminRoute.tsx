import { Navigate, Outlet } from 'react-router-dom'
import { useAuth } from '@/hooks/use-auth'
import { superAdminRouteDecision } from '@/lib/admin-control-tower'

export function SuperAdminRoute() {
  const { user, loading, contextLoading, context } = useAuth()

  const decision = superAdminRouteDecision({
    loading,
    contextLoading,
    isAuthenticated: !!user,
    activeRole: context?.activeRole,
  })

  if (decision === 'loading') {
    return (
      <div className="flex min-h-screen items-center justify-center text-sm text-[var(--color-muted)]">
        Loading…
      </div>
    )
  }

  if (decision === 'redirect-login') {
    return <Navigate to="/login" replace />
  }

  if (decision === 'redirect-dashboard') {
    return <Navigate to="/dashboard" replace />
  }

  return <Outlet />
}
