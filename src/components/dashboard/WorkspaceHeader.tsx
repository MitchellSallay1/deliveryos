import { Link } from 'react-router-dom'
import { Bell, ChevronDown, Plus } from 'lucide-react'
import { Button } from '@/components/ui/Button'
import { greetingForHour } from '@/lib/dashboard-metrics'
import type { AuthContext } from '@/types/supabase'

type WorkspaceHeaderProps = {
  context: AuthContext
  companyId: string
  companyName: string
  planName?: string
  companyStatus?: string
  canCreateDelivery: boolean
  onSwitchCompany: (companyId: string) => void
}

export function WorkspaceHeader({
  context,
  companyId,
  companyName,
  planName,
  companyStatus,
  canCreateDelivery,
  onSwitchCompany,
}: WorkspaceHeaderProps) {
  const firstName = (context.profile?.full_name ?? '').trim().split(/\s+/)[0] || null
  const greeting = greetingForHour(new Date().getHours())

  return (
    <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight text-[var(--color-foreground)]">
          {greeting}
          {firstName ? `, ${firstName}` : ''}
        </h1>
        <p className="mt-1 text-sm text-[var(--color-muted)]">
          Here&apos;s what&apos;s happening with your operations today.
        </p>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        {context.memberships.length > 1 && (
          <div className="relative">
            <select
              aria-label="Switch workspace"
              value={companyId}
              onChange={(e) => onSwitchCompany(e.target.value)}
              className="h-9 appearance-none rounded-lg border bg-white pl-3 pr-8 text-sm font-medium text-[var(--color-foreground)] outline-none focus:ring-2 focus:ring-[var(--color-primary)]"
            >
              {context.memberships.map((m) => (
                <option key={m.company_id} value={m.company_id}>
                  {m.company.name}
                </option>
              ))}
            </select>
            <ChevronDown className="pointer-events-none absolute right-2 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-[var(--color-muted)]" aria-hidden />
          </div>
        )}

        {(planName || companyStatus) && (
          <span className="hidden items-center gap-1.5 rounded-lg border bg-white px-3 py-1.5 text-xs font-medium text-[var(--color-muted)] sm:inline-flex">
            {companyName}
            {planName && <span className="text-[var(--color-foreground)]">· {planName}</span>}
          </span>
        )}

        <Link
          to="/notifications"
          aria-label="Notifications"
          className="flex h-9 w-9 items-center justify-center rounded-lg border bg-white text-[var(--color-muted)] transition-colors hover:bg-zinc-50 hover:text-[var(--color-foreground)]"
        >
          <Bell className="h-4 w-4" aria-hidden />
        </Link>

        {canCreateDelivery && (
          <Link to="/deliveries">
            <Button type="button" variant="accent">
              <Plus className="mr-1.5 h-4 w-4" aria-hidden />
              Create delivery
            </Button>
          </Link>
        )}
      </div>
    </div>
  )
}
