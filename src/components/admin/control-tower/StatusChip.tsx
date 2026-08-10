import { cn } from '@/lib/utils'
import { STATUS_COLOR_CLASSES, statusColorFor, type StatusColor } from '@/lib/admin-control-tower'

/**
 * The one status-color primitive the whole control tower uses. Explicit
 * green/amber/red/gray — gray means "not configured", not "error".
 */
export function StatusChip({
  label,
  color,
  status,
  className,
}: {
  label: string
  /** Provide either an explicit color or a raw status string to derive it from. */
  color?: StatusColor
  status?: string
  className?: string
}) {
  const c = color ?? statusColorFor(status)
  const styles = STATUS_COLOR_CLASSES[c]
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium ring-1 ring-inset',
        styles.bg,
        styles.text,
        styles.ring,
        className,
      )}
    >
      <span className={cn('h-1.5 w-1.5 shrink-0 rounded-full', styles.dot)} aria-hidden />
      {label}
    </span>
  )
}
