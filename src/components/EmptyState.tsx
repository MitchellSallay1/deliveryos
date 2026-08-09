import { Inbox } from 'lucide-react'
import { Link } from 'react-router-dom'
import { Button } from '@/components/ui/Button'
import { cn } from '@/lib/utils'

type EmptyStateProps = {
  title: string
  description: string
  actionLabel?: string
  actionTo?: string
  onAction?: () => void
  className?: string
}

export function EmptyState({
  title,
  description,
  actionLabel,
  actionTo,
  onAction,
  className,
}: EmptyStateProps) {
  return (
    <div
      className={cn(
        'flex flex-col items-center rounded-xl border border-dashed bg-white px-6 py-12 text-center surface-card',
        className,
      )}
    >
      <span className="flex h-14 w-14 items-center justify-center rounded-full bg-zinc-100 text-zinc-500">
        <Inbox className="h-7 w-7" aria-hidden />
      </span>
      <h3 className="mt-4 text-base font-semibold">{title}</h3>
      <p className="mx-auto mt-2 max-w-md text-sm text-[var(--color-muted)]">{description}</p>
      {actionLabel && actionTo && (
        <Link to={actionTo} className="mt-6">
          <Button variant="accent" type="button">
            {actionLabel}
          </Button>
        </Link>
      )}
      {actionLabel && onAction && !actionTo && (
        <Button variant="accent" type="button" className="mt-6" onClick={onAction}>
          {actionLabel}
        </Button>
      )}
    </div>
  )
}
