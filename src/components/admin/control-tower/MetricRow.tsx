import type { ReactNode } from 'react'
import { cn } from '@/lib/utils'

/** Label/value row for dense stat lists inside a CommandCard. */
export function MetricRow({
  label,
  value,
  hint,
  className,
}: {
  label: ReactNode
  value: ReactNode
  hint?: ReactNode
  className?: string
}) {
  return (
    <div className={cn('flex items-center justify-between gap-3 py-2 text-sm', className)}>
      <span className="text-zinc-500">{label}</span>
      <span className="flex items-center gap-2 font-medium tabular-nums text-zinc-100">
        {value}
        {hint && <span className="text-xs font-normal text-zinc-600">{hint}</span>}
      </span>
    </div>
  )
}

export function MetricList({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={cn('divide-y divide-white/[0.05]', className)}>{children}</div>
}
