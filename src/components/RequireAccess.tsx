import { Navigate, Outlet, useLocation } from 'react-router-dom'
import { useAuth } from '@/hooks/use-auth'
import { can, defaultHomeForRole, ROUTE_PERMISSIONS, type Permission } from '@/lib/rbac'

type RequireAccessProps = {
  permission?: Permission
  pathPermission?: boolean
  children?: React.ReactNode
}

export function RequireAccess({
  permission,
  pathPermission = true,
  children,
}: RequireAccessProps) {
  const { context, loading, contextLoading } = useAuth()
  const { pathname } = useLocation()
  const role = context?.activeRole ?? null

  if (loading || contextLoading) {
    return (
      <div className="flex min-h-[40vh] items-center justify-center text-sm text-[var(--color-muted)]">
        Loading workspace…
      </div>
    )
  }

  const required =
    permission ??
    (pathPermission
      ? (ROUTE_PERMISSIONS[pathname] ??
          (pathname.startsWith('/operations')
            ? ('page:operations' as Permission)
            : pathname.startsWith('/merchant')
              ? ('page:merchant-requests' as Permission)
              : pathname.startsWith('/marketplace')
                ? ('page:marketplace-jobs' as Permission)
                : pathname.startsWith('/vendor')
                  ? ('page:vendor' as Permission)
                  : undefined))
      : undefined)

  if (required && !can(role, required)) {
    return <Navigate to={defaultHomeForRole(role)} replace state={{ denied: required }} />
  }

  return children ? <>{children}</> : <Outlet />
}
