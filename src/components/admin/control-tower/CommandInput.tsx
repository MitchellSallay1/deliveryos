import { cn } from '@/lib/utils'

/** Dark text input for admin search/filter bars. */
export function CommandInput({ className, ...props }: React.InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      className={cn(
        'h-9 w-full rounded-lg border border-white/10 bg-white/[0.03] px-3 text-sm text-zinc-100 outline-none placeholder:text-zinc-600 focus:border-[#FFCB05]/40 focus:ring-1 focus:ring-[#FFCB05]/30',
        className,
      )}
      {...props}
    />
  )
}

/** Dark select for admin filter/action forms. */
export function CommandSelect({ className, ...props }: React.SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select
      className={cn(
        'h-9 w-full rounded-lg border border-white/10 bg-white/[0.03] px-2.5 text-sm text-zinc-100 outline-none focus:border-[#FFCB05]/40 focus:ring-1 focus:ring-[#FFCB05]/30 [&>option]:bg-[#131316] [&>option]:text-zinc-100',
        className,
      )}
      {...props}
    />
  )
}
