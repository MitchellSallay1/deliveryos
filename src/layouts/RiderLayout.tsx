import { Link, Outlet, useLocation } from 'react-router-dom'
import { History, LogOut, Smartphone, User, WifiOff } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/Button'
import { useAuth } from '@/hooks/use-auth'
import { BrandLogo, PoweredByPartner } from '@/components/brand/BrandLogo'

const nav = [
  { to: '/my-jobs', label: 'Jobs', icon: Smartphone },
  { to: '/rider/profile', label: 'Profile', icon: User },
]

export function RiderLayout() {
  const { pathname } = useLocation()
  const { signOut, user, context } = useAuth()

  const companyName =
    context?.memberships.find((m) => m.role === 'rider')?.company.name ?? 'Rider'

  const phoneLabel = user?.phone ?? user?.email ?? 'Signed in'

  return (
    <div className="flex min-h-screen flex-col bg-[var(--color-background)] md:flex-row">
      <aside className="hidden border-r bg-[var(--color-sidebar)] text-[var(--color-sidebar-foreground)] md:flex md:w-56 md:flex-col">
        <div className="p-4">
          <BrandLogo variant="light" showPartner={false} />
          <p className="mt-3 font-semibold text-white">{companyName}</p>
          <p className="text-xs text-zinc-500">Rider app</p>
        </div>
        <nav className="flex flex-col gap-1 p-2">
          {nav.map(({ to, label, icon: Icon }) => (
            <Link
              key={to}
              to={to}
              className={cn(
                'flex items-center gap-2 rounded-lg px-3 py-2 text-sm font-medium',
                pathname === to ? 'bg-white/10 text-white' : 'text-zinc-400 hover:bg-white/5',
              )}
            >
              <Icon className="h-4 w-4" aria-hidden />
              {label}
            </Link>
          ))}
          <span className="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-zinc-600">
            <History className="h-4 w-4" aria-hidden />
            History (soon)
          </span>
        </nav>
        <div className="mt-auto border-t border-white/10 p-4">
          <PoweredByPartner className="mb-2 justify-start text-zinc-600" />
          <p className="truncate text-xs text-zinc-500">{phoneLabel}</p>
          <Button
            variant="ghost"
            size="sm"
            className="mt-2 w-full justify-start gap-2 text-zinc-400"
            onClick={() => void signOut()}
          >
            <LogOut className="h-4 w-4" aria-hidden />
            Sign out
          </Button>
        </div>
      </aside>

      <div className="flex min-h-0 flex-1 flex-col">
        <div className="flex items-center justify-between border-b bg-white px-4 py-3 md:hidden">
          <BrandLogo showPartner={false} />
          <PoweredByPartner />
        </div>

        <div className="hidden items-center gap-2 border-b border-amber-200 bg-amber-50 px-4 py-2 text-xs text-amber-950 md:flex">
          <WifiOff className="h-3.5 w-3.5" aria-hidden />
          Offline mode banner — connectivity status only (no logic change)
        </div>

        <main className="flex-1 overflow-y-auto p-4 pb-24 md:p-6 md:pb-6">
          <Outlet />
        </main>

        <nav
          className="fixed bottom-0 left-0 right-0 z-20 flex border-t bg-white/95 backdrop-blur md:hidden"
          aria-label="Rider navigation"
        >
          {nav.map(({ to, label, icon: Icon }) => {
            const active = pathname === to
            return (
              <Link
                key={to}
                to={to}
                className={cn(
                  'flex flex-1 flex-col items-center gap-1 py-3 text-[10px] font-medium',
                  active ? 'text-[var(--color-primary)]' : 'text-[var(--color-muted)]',
                )}
              >
                <Icon className={cn('h-6 w-6', active && 'text-[var(--color-accent)]')} aria-hidden />
                {label}
              </Link>
            )
          })}
        </nav>
      </div>
    </div>
  )
}
