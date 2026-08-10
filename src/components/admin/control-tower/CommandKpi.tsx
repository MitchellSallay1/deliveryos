import type { LucideIcon } from 'lucide-react'
import { cn } from '@/lib/utils'
import { STATUS_COLOR_CLASSES, type StatusColor } from '@/lib/admin-control-tower'

export function CommandKpi({
  label,
  value,
  hint,
  icon: Icon,
  loading,
  color,
  className,
}: {
  label: string
  value: string
  hint?: string
  icon?: LucideIcon
  loading?: boolean
  /** Optional accent — a thin left border + icon tint. Omit for neutral KPIs. */
  color?: StatusColor
  className?: string
}) {
  const accent = color ? STATUS_COLOR_CLASSES[color] : null
  const borderAccentClass: Record<StatusColor, string> = {
    green: 'border-l-emerald-400',
    amber: 'border-l-amber-400',
    red: 'border-l-red-400',
    gray: 'border-l-zinc-500',
  }
  return (
    <div
      className={cn(
        'rounded-xl border border-white/[0.08] bg-[#131316] p-4',
        color && cn('border-l-2', borderAccentClass[color]),
        className,
      )}
    >
      <div className="flex items-start justify-between gap-2">
        <p className="text-[11px] font-medium uppercase tracking-wide text-zinc-500">{label}</p>
        {Icon && (
          <span className={cn('rounded-md p-1.5', accent ? accent.bg : 'bg-white/5')}>
            <Icon className={cn('h-3.5 w-3.5', accent ? accent.text : 'text-zinc-400')} aria-hidden />
          </span>
        )}
      </div>
      {loading ? (
        <div className="mt-2.5 h-8 w-20 animate-pulse rounded bg-white/5" />
      ) : (
        <p className="mt-1.5 text-2xl font-semibold tabular-nums tracking-tight text-white">{value}</p>
      )}
      {hint && !loading && <p className="mt-1 truncate text-[11px] text-zinc-500">{hint}</p>}
    </div>
  )
}
