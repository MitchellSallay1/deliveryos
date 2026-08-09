import { Link, Outlet, useLocation } from 'react-router-dom'
import {
  LayoutDashboard,
  Truck,
  Users,
  UserCircle,
  BarChart3,
  Bell,
  LogOut,
  Settings,
  Smartphone,
  UsersRound,
  MapPin,
  Boxes,
  Store,
  Network,
  CreditCard,
  Menu,
} from 'lucide-react'
import { useState } from 'react'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/Button'
import { useAuth } from '@/hooks/use-auth'
import {
  can,
  isNavVisibleForBusinessType,
  ROUTE_PERMISSIONS,
  type Permission,
} from '@/lib/rbac'
import type { CompanyBusinessType } from '@/services/marketplace-service'
import { TrialStatusBanner } from '@/components/TrialStatusBanner'
import { BrandLogo, PoweredByPartner } from '@/components/brand/BrandLogo'
import { Badge } from '@/components/ui/Badge'

const nav: {
  to: string
  label: string
  icon: React.ComponentType<{ className?: string }>
  permission: Permission
}[] = [
  { to: '/dashboard', label: 'Dashboard', icon: LayoutDashboard, permission: 'page:dashboard' },
  { to: '/deliveries', label: 'Deliveries', icon: Truck, permission: 'page:deliveries' },
  { to: '/merchant/requests', label: 'Delivery requests', icon: Store, permission: 'page:merchant-requests' },
  { to: '/marketplace/jobs', label: 'Marketplace jobs', icon: Network, permission: 'page:marketplace-jobs' },
  { to: '/marketplace/providers', label: 'Providers', icon: Users, permission: 'page:marketplace-providers' },
  { to: '/live-map', label: 'Live map', icon: MapPin, permission: 'page:live-map' },
  { to: '/operations', label: 'Operations', icon: Boxes, permission: 'page:operations' },
  { to: '/riders', label: 'Riders', icon: Users, permission: 'page:riders' },
  { to: '/customers', label: 'Customers', icon: UserCircle, permission: 'page:customers' },
  { to: '/reports', label: 'Reports', icon: BarChart3, permission: 'page:reports' },
  { to: '/billing', label: 'Billing', icon: CreditCard, permission: 'page:billing' },
  { to: '/notifications', label: 'Notifications', icon: Bell, permission: 'page:notifications' },
  { to: '/team', label: 'Team', icon: UsersRound, permission: 'page:team' },
  { to: '/my-jobs', label: 'My jobs', icon: Smartphone, permission: 'page:my-jobs' },
  { to: '/settings', label: 'Settings', icon: Settings, permission: 'page:settings' },
]

function NavLinks({
  pathname,
  visibleNav,
  onNavigate,
}: {
  pathname: string
  visibleNav: typeof nav
  onNavigate?: () => void
}) {
  return (
    <>
      {visibleNav.map(({ to, label, icon: Icon }) => {
        const active = pathname === to || pathname.startsWith(`${to}/`)
        return (
          <Link
            key={to}
            to={to}
            onClick={onNavigate}
            className={cn(
              'flex items-center gap-2 rounded-lg px-3 py-2 text-sm font-medium transition-colors',
              active
                ? 'bg-white/10 text-white ring-1 ring-white/10'
                : 'text-zinc-400 hover:bg-white/5 hover:text-white',
            )}
          >
            <Icon className={cn('h-4 w-4', active && 'text-[var(--color-sidebar-accent)]')} aria-hidden />
            {label}
          </Link>
        )
      })}
    </>
  )
}

export function DashboardLayout() {
  const { pathname } = useLocation()
  const { context, signOut, user } = useAuth()
  const [mobileOpen, setMobileOpen] = useState(false)
  const role = context?.activeRole ?? null

  const businessType = (context?.memberships.find((m) => m.company_id === context?.activeCompanyId)
    ?.company.business_type ?? 'logistics_provider') as CompanyBusinessType

  const visibleNav = nav.filter(
    (item) =>
      can(role, item.permission) && isNavVisibleForBusinessType(item.permission, businessType),
  )

  const companyName =
    context?.memberships.find((m) => m.company_id === context.activeCompanyId)
      ?.company.name ?? 'Workspace'

  const headerTitle =
    nav.find((n) => pathname === n.to || pathname.startsWith(`${n.to}/`))?.label ??
    (ROUTE_PERMISSIONS[pathname] ? 'DeliveryOS' : 'DeliveryOS')

  const phoneLabel = user?.phone ?? user?.email ?? 'Signed in'

  return (
    <div className="flex min-h-screen bg-[var(--color-background)]">
      <aside className="hidden w-64 shrink-0 flex-col bg-[var(--color-sidebar)] text-[var(--color-sidebar-foreground)] lg:flex">
        <div className="border-b border-white/10 p-5">
          <BrandLogo variant="light" />
          <p className="mt-4 truncate text-sm font-semibold text-white">{companyName}</p>
          <Badge variant="accent" className="mt-2 capitalize">
            {role?.replace(/_/g, ' ') ?? 'member'}
          </Badge>
        </div>
        <nav className="flex-1 space-y-1 overflow-y-auto p-3">
          {role === 'super_admin' && (
            <Link
              to="/admin"
              className="mb-2 flex items-center gap-2 rounded-lg border border-[var(--color-sidebar-accent)]/30 px-3 py-2 text-sm text-[var(--color-sidebar-accent)] hover:bg-white/5"
            >
              Platform admin
            </Link>
          )}
          <NavLinks pathname={pathname} visibleNav={visibleNav} />
        </nav>
        <div className="border-t border-white/10 p-4">
          <PoweredByPartner className="mb-3 justify-start text-zinc-500" />
          <p className="truncate text-xs text-zinc-500">{phoneLabel}</p>
          <Button
            variant="ghost"
            size="sm"
            className="mt-2 w-full justify-start gap-2 text-zinc-400 hover:bg-white/5 hover:text-white"
            onClick={() => void signOut()}
          >
            <LogOut className="h-4 w-4" aria-hidden />
            Sign out
          </Button>
        </div>
      </aside>

      {mobileOpen && (
        <div className="fixed inset-0 z-40 lg:hidden">
          <button type="button" className="absolute inset-0 bg-black/50" aria-label="Close menu" onClick={() => setMobileOpen(false)} />
          <aside className="relative flex h-full w-72 flex-col bg-[var(--color-sidebar)] p-4 text-white">
            <BrandLogo variant="light" />
            <nav className="mt-4 flex-1 space-y-1 overflow-y-auto">
              <NavLinks pathname={pathname} visibleNav={visibleNav} onNavigate={() => setMobileOpen(false)} />
            </nav>
          </aside>
        </div>
      )}

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="sticky top-0 z-30 flex items-center justify-between border-b bg-white/90 px-4 py-3 backdrop-blur-md lg:px-8">
          <div className="flex items-center gap-3">
            <Button
              type="button"
              variant="ghost"
              size="sm"
              className="lg:hidden"
              aria-label="Open navigation"
              onClick={() => setMobileOpen(true)}
            >
              <Menu className="h-5 w-5" />
            </Button>
            <div>
              <h1 className="text-lg font-semibold tracking-tight">{headerTitle}</h1>
              <p className="hidden text-xs text-[var(--color-muted)] sm:block">{companyName}</p>
            </div>
          </div>
          <PoweredByPartner className="hidden sm:flex" />
        </header>
        <main className="flex-1 p-4 lg:p-8">
          <TrialStatusBanner />
          <Outlet />
        </main>
      </div>
    </div>
  )
}
