import { useState } from 'react'
import { Link, useLocation } from 'react-router-dom'
import { ChevronDown } from 'lucide-react'
import { cn } from '@/lib/utils'
import { ADMIN_NAV_GROUPS } from '@/lib/admin-nav'

export function AdminSidebar() {
  const { pathname } = useLocation()
  const [openGroups, setOpenGroups] = useState<Record<string, boolean>>(() =>
    Object.fromEntries(ADMIN_NAV_GROUPS.map((g) => [g.id, true])),
  )

  return (
    <nav className="flex-1 space-y-1 overflow-y-auto p-3" aria-label="Platform admin">
      {ADMIN_NAV_GROUPS.map((group) => {
        const expanded = openGroups[group.id] !== false
        return (
          <div key={group.id} className="pb-2">
            <button
              type="button"
              className="flex w-full items-center justify-between rounded-md px-2 py-1.5 text-[10px] font-semibold uppercase tracking-wider text-slate-500 hover:text-slate-300"
              onClick={() => setOpenGroups((s) => ({ ...s, [group.id]: !expanded }))}
              aria-expanded={expanded}
            >
              {group.label}
              <ChevronDown className={cn('h-3 w-3 transition-transform', expanded && 'rotate-180')} />
            </button>
            {expanded && (
              <ul className="mt-1 space-y-0.5">
                {group.items.map(({ to, label, icon: Icon, end }) => {
                  const active = end ? pathname === to : pathname === to || pathname.startsWith(`${to}/`)
                  return (
                    <li key={to}>
                      <Link
                        to={to}
                        className={cn(
                          'flex items-center gap-2 rounded-lg px-3 py-2 text-sm transition-colors',
                          active
                            ? 'bg-[var(--color-accent)]/20 text-white'
                            : 'text-slate-300 hover:bg-white/5 hover:text-white',
                        )}
                      >
                        <Icon className="h-4 w-4 shrink-0" aria-hidden />
                        <span className="truncate">{label}</span>
                      </Link>
                    </li>
                  )
                })}
              </ul>
            )}
          </div>
        )
      })}
      <Link
        to="/dashboard"
        className="mt-2 block rounded-lg px-3 py-2 text-sm text-slate-400 hover:bg-white/5 hover:text-white"
      >
        ← Company workspace
      </Link>
    </nav>
  )
}
