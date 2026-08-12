import { useState } from 'react'
import { Outlet, useLocation } from 'react-router-dom'
import { LogOut, Menu, X } from 'lucide-react'
import { adminPageTitle } from '@/lib/admin-nav'
import { Button } from '@/components/ui/Button'
import { useAuth } from '@/hooks/use-auth'
import { AdminSidebar } from '@/components/admin/AdminSidebar'
import { AdminGlobalSearch } from '@/components/admin/AdminGlobalSearch'
import { BrandLogo } from '@/components/brand/BrandLogo'
import { cn } from '@/lib/utils'
import { InstallButton } from '@/components/pwa/InstallButton'

export function AdminLayout() {
  const { pathname } = useLocation()
  const { signOut, user } = useAuth()
  const title = adminPageTitle(pathname)
  const [mobileNavOpen, setMobileNavOpen] = useState(false)

  return (
    <div className="admin-shell flex min-h-screen bg-[#0a0a0b] text-zinc-100">
      {/* Mobile/tablet nav overlay */}
      {mobileNavOpen && (
        <div
          className="fixed inset-0 z-40 bg-black/60 lg:hidden"
          onClick={() => setMobileNavOpen(false)}
          aria-hidden
        />
      )}
      <aside
        className={cn(
          'fixed inset-y-0 left-0 z-50 flex w-72 shrink-0 -translate-x-full flex-col border-r border-white/[0.08] bg-[#0d0d0f] transition-transform duration-200 lg:relative lg:w-64 lg:translate-x-0',
          mobileNavOpen && 'translate-x-0',
        )}
      >
        <div className="flex items-center justify-between gap-2 border-b border-white/[0.08] p-5">
          <div>
            <BrandLogo variant="light" />
            <p className="mt-2 text-[10px] font-semibold uppercase tracking-wider text-zinc-500">
              Platform control tower
            </p>
          </div>
          <button
            type="button"
            className="rounded-lg p-1.5 text-zinc-400 hover:bg-white/5 lg:hidden"
            onClick={() => setMobileNavOpen(false)}
            aria-label="Close navigation"
          >
            <X className="h-4 w-4" />
          </button>
        </div>
        <AdminSidebar onNavigate={() => setMobileNavOpen(false)} />
        <div className="border-t border-white/[0.08] p-4">
          <p className="truncate text-xs text-zinc-500">{user?.phone ?? user?.email}</p>
          <Button
            variant="ghost"
            size="sm"
            className="mt-2 w-full justify-start gap-2 text-zinc-400 hover:bg-white/5 hover:text-white"
            onClick={() => void signOut()}
          >
            <LogOut className="h-4 w-4" />
            Sign out
          </Button>
        </div>
      </aside>
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="sticky top-0 z-30 flex flex-wrap items-center gap-3 border-b border-white/[0.08] bg-[#0a0a0b]/95 px-4 py-3 backdrop-blur sm:px-6">
          <button
            type="button"
            className="rounded-lg p-2 text-zinc-400 hover:bg-white/5 lg:hidden"
            onClick={() => setMobileNavOpen(true)}
            aria-label="Open navigation"
          >
            <Menu className="h-5 w-5" />
          </button>
          <h1 className="shrink-0 text-base font-semibold tracking-tight text-white">{title}</h1>
          <AdminGlobalSearch />
          <InstallButton label="Install app" variant="ghost" size="sm" showIcon={false} className="ml-auto text-zinc-400 hover:text-white" />
        </header>
        <main className="flex-1 overflow-x-hidden p-4 sm:p-6">
          <Outlet />
        </main>
      </div>
    </div>
  )
}
