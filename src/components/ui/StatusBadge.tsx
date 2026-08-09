import { cn } from '@/lib/utils'
import { statusStyle } from '@/design-system/delivery-status'

export function StatusBadge({ status, className }: { status: string; className?: string }) {
  const s = statusStyle(status)
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-medium capitalize ring-1 ring-inset',
        s.badge,
        className,
      )}
    >
      <span className={cn('h-1.5 w-1.5 rounded-full', s.dot)} aria-hidden />
      {s.label}
    </span>
  )
}
