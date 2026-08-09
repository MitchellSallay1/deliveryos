import { cn } from '@/lib/utils'

type BadgeProps = React.HTMLAttributes<HTMLSpanElement> & {
  variant?: 'default' | 'accent' | 'outline' | 'success' | 'warning' | 'danger'
}

export function Badge({ className, variant = 'default', ...props }: BadgeProps) {
  return (
    <span
      className={cn(
        'inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset',
        variant === 'default' && 'bg-zinc-100 text-zinc-800 ring-zinc-200',
        variant === 'accent' && 'bg-[var(--color-accent)] text-black ring-[#e6b800]',
        variant === 'outline' && 'bg-white text-zinc-700 ring-zinc-200',
        variant === 'success' && 'bg-emerald-50 text-emerald-800 ring-emerald-100',
        variant === 'warning' && 'bg-amber-50 text-amber-900 ring-amber-100',
        variant === 'danger' && 'bg-red-50 text-red-800 ring-red-100',
        className,
      )}
      {...props}
    />
  )
}
