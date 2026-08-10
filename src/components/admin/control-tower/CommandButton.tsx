import { cn } from '@/lib/utils'

export type CommandButtonProps = React.ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: 'primary' | 'outline' | 'ghost' | 'destructive'
  size?: 'sm' | 'default'
}

/** Dark button used throughout the admin-only control tower — never touches the shared tenant Button component. */
export function CommandButton({ className, variant = 'outline', size = 'default', ...props }: CommandButtonProps) {
  return (
    <button
      type="button"
      className={cn(
        'inline-flex items-center justify-center gap-1.5 rounded-lg font-medium transition disabled:pointer-events-none disabled:opacity-50',
        variant === 'primary' && 'bg-[#FFCB05] text-black hover:brightness-95',
        variant === 'outline' && 'border border-white/10 bg-white/[0.03] text-zinc-300 hover:bg-white/[0.06]',
        variant === 'ghost' && 'text-zinc-400 hover:bg-white/5 hover:text-white',
        variant === 'destructive' && 'border border-red-400/30 bg-red-400/[0.08] text-red-300 hover:bg-red-400/[0.15]',
        size === 'default' && 'h-9 px-3.5 text-xs',
        size === 'sm' && 'h-7 px-2.5 text-[11px]',
        className,
      )}
      {...props}
    />
  )
}
