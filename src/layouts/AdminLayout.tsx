import { Outlet } from 'react-router-dom'
import { LogOut } from 'lucide-react'
import { adminPageTitle } from '@/lib/admin-nav'
import { useLocation } from 'react-router-dom'
import { Button } from '@/components/ui/Button'
import { useAuth } from '@/hooks/use-auth'
import { AdminSidebar } from '@/components/admin/AdminSidebar'
import { AdminGlobalSearch } from '@/components/admin/AdminGlobalSearch'
import { BrandLogo } from '@/components/brand/BrandLogo'

export function AdminLayout() {
  const { pathname } = useLocation()
  const { signOut, user } = useAuth()
  const title = adminPageTitle(pathname)

  return (
    <div className="flex min-h-screen bg-[var(--color-background)]">
      <aside className="flex w-64 shrink-0 flex-col border-r border-white/10 bg-slate-950 text-slate-100">
        <div className="border-b border-white/10 p-5">
          <BrandLogo variant="light" />
          <p className="mt-2 text-[10px] font-semibold uppercase tracking-wider text-slate-500">
            Platform control tower
          </p>
        </div>
        <AdminSidebar />
        <div className="border-t border-white/10 p-4">
          <p className="truncate text-xs text-slate-400">{user?.phone ?? user?.email}</p>
          <Button
            variant="ghost"
            size="sm"
            className="mt-2 w-full justify-start gap-2 text-slate-300 hover:text-white"
            onClick={() => void signOut()}
          >
            <LogOut className="h-4 w-4" />
            Sign out
          </Button>
        </div>
      </aside>
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="sticky top-0 z-40 flex flex-wrap items-center gap-4 border-b bg-white/95 px-6 py-4 backdrop-blur">
          <h1 className="text-lg font-semibold tracking-tight">{title}</h1>
          <AdminGlobalSearch />
        </header>
        <main className="flex-1 p-6">
          <Outlet />
        </main>
      </div>
    </div>
  )
}
