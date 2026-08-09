import { cn } from '@/lib/utils'

type ButtonProps = React.ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: 'default' | 'accent' | 'outline' | 'ghost' | 'destructive'
  size?: 'default' | 'sm' | 'lg'
}

export function Button({
  className,
  variant = 'default',
  size = 'default',
  ...props
}: ButtonProps) {
  return (
    <button
      className={cn(
        'inline-flex items-center justify-center rounded-lg font-medium transition-all duration-150 disabled:pointer-events-none disabled:opacity-50',
        variant === 'default' &&
          'bg-[var(--color-primary)] text-[var(--color-primary-foreground)] hover:opacity-90 shadow-sm',
        variant === 'accent' &&
          'bg-[var(--color-accent)] text-black hover:brightness-95 shadow-sm',
        variant === 'outline' && 'border bg-white hover:bg-zinc-50 shadow-sm',
        variant === 'ghost' && 'hover:bg-zinc-100',
        variant === 'destructive' && 'bg-red-600 text-white hover:bg-red-700',
        size === 'default' && 'h-10 px-4 py-2 text-sm',
        size === 'sm' && 'h-8 px-3 text-xs',
        size === 'lg' && 'h-11 px-6 text-base',
        className,
      )}
      {...props}
    />
  )
}
