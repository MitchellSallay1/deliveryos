import type { LucideIcon } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Skeleton } from '@/components/ui/Skeleton'

type KpiCardProps = {
  label: string
  value: string
  hint?: string
  icon?: LucideIcon
  trend?: string
  loading?: boolean
  className?: string
}

export function KpiCard({ label, value, hint, icon: Icon, trend, loading, className }: KpiCardProps) {
  return (
    <div
      className={cn(
        'rounded-xl border bg-[var(--color-card)] p-5 transition-shadow hover:shadow-md surface-card animate-fade-in',
        className,
      )}
    >
      <div className="flex items-start justify-between gap-2">
        <p className="text-xs font-medium uppercase tracking-wide text-[var(--color-muted)]">{label}</p>
        {Icon && (
          <span className="rounded-lg bg-zinc-100 p-2 text-zinc-700">
            <Icon className="h-4 w-4" aria-hidden />
          </span>
        )}
      </div>
      {loading ? (
        <Skeleton className="mt-3 h-9 w-20" />
      ) : (
        <p className="mt-2 text-3xl font-semibold tabular-nums tracking-tight">{value}</p>
      )}
      {(hint || trend) && !loading && (
        <p className="mt-1 text-xs text-[var(--color-muted)]">{trend ?? hint}</p>
      )}
    </div>
  )
}
