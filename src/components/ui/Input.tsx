import { cn } from '@/lib/utils'

export function Input({ className, ...props }: React.ComponentProps<'input'>) {
  return (
    <input
      className={cn(
        'flex h-10 w-full rounded-lg border bg-white px-3 py-2 text-sm outline-none ring-[var(--color-primary)] focus:ring-2',
        className,
      )}
      {...props}
    />
  )
}
