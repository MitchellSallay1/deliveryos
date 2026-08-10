import type { ReactNode } from 'react'
import { cn } from '@/lib/utils'

/** Dark card shell used throughout the control tower. */
export function CommandCard({
  children,
  className,
}: {
  children: ReactNode
  className?: string
}) {
  return (
    <div
      className={cn(
        'rounded-xl border border-white/[0.08] bg-[#131316] shadow-[0_1px_0_rgba(255,255,255,0.03)_inset]',
        className,
      )}
    >
      {children}
    </div>
  )
}

export function CommandCardHeader({
  title,
  description,
  action,
  className,
}: {
  title?: ReactNode
  description?: ReactNode
  action?: ReactNode
  className?: string
}) {
  return (
    <div className={cn('flex items-start justify-between gap-3 border-b border-white/[0.06] px-4 py-3', className)}>
      <div className="min-w-0">
        {title && <h3 className="text-sm font-semibold text-zinc-100">{title}</h3>}
        {description && <p className="mt-0.5 text-xs text-zinc-500">{description}</p>}
      </div>
      {action && <div className="shrink-0">{action}</div>}
    </div>
  )
}

export function CommandCardBody({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={cn('p-4', className)}>{children}</div>
}

/** Section-level header for grouping cards (e.g. "PLATFORM STATUS"). Not a card itself. */
export function SectionHeader({
  eyebrow,
  title,
  action,
  className,
}: {
  eyebrow?: string
  title?: ReactNode
  action?: ReactNode
  className?: string
}) {
  return (
    <div className={cn('mb-3 flex items-center justify-between gap-3', className)}>
      <div>
        {eyebrow && (
          <p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-zinc-500">{eyebrow}</p>
        )}
        {title && <h2 className="mt-0.5 text-base font-semibold text-zinc-100">{title}</h2>}
      </div>
      {action}
    </div>
  )
}
