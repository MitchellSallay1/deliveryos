import { Navigate, Outlet } from 'react-router-dom'
import { useAuth } from '@/hooks/use-auth'

export function SuperAdminRoute() {
  const { user, loading, contextLoading, context } = useAuth()

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

  if (context?.activeRole !== 'super_admin') {
    return <Navigate to="/dashboard" replace />
  }

  return <Outlet />
}
