import { cn } from '@/lib/utils'

type TabsProps = {
  value: string
  onValueChange: (v: string) => void
  items: { value: string; label: string }[]
  className?: string
}

export function Tabs({ value, onValueChange, items, className }: TabsProps) {
  return (
    <div
      role="tablist"
      aria-label="Sections"
      className={cn('flex flex-wrap gap-1 rounded-lg border bg-zinc-50/80 p-1', className)}
    >
      {items.map((item) => (
        <button
          key={item.value}
          type="button"
          role="tab"
          aria-selected={value === item.value}
          className={cn(
            'rounded-md px-3 py-1.5 text-sm font-medium transition-colors',
            value === item.value
              ? 'bg-white text-[var(--color-foreground)] shadow-sm'
              : 'text-[var(--color-muted)] hover:text-[var(--color-foreground)]',
          )}
          onClick={() => onValueChange(item.value)}
        >
          {item.label}
        </button>
      ))}
    </div>
  )
}

export function TabPanel({
  value,
  active,
  children,
  className,
}: {
  value: string
  active: string
  children: React.ReactNode
  className?: string
}) {
  if (value !== active) return null
  return (
    <div role="tabpanel" className={cn('animate-fade-in pt-4', className)}>
      {children}
    </div>
  )
}
