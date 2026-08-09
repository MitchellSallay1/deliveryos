import { useEffect, useRef, useState } from 'react'
import { cn } from '@/lib/utils'

const STAGES = [
  { key: 'created', label: 'Order created' },
  { key: 'assigned', label: 'Rider assigned' },
  { key: 'accepted', label: 'Accepted' },
  { key: 'picked_up', label: 'Picked up' },
  { key: 'in_transit', label: 'In transit' },
  { key: 'delivered', label: 'Delivered' },
]

export function MarketingDispatchFlow() {
  const ref = useRef<HTMLDivElement>(null)
  const [active, setActive] = useState(0)

  useEffect(() => {
    const el = ref.current
    if (!el) return
    const obs = new IntersectionObserver(
      ([entry]) => {
        if (!entry?.isIntersecting) return
        const ratio = entry.intersectionRatio
        const step = Math.min(STAGES.length - 1, Math.floor(ratio * STAGES.length * 1.2))
        setActive(step)
      },
      { threshold: Array.from({ length: 11 }, (_, i) => i / 10) },
    )
    obs.observe(el)
    return () => obs.disconnect()
  }, [])

  return (
    <div ref={ref} className="relative min-h-[280px]">
      <div className="absolute left-4 top-0 bottom-0 w-px bg-zinc-200 md:left-1/2" aria-hidden />
      <ol className="space-y-8">
        {STAGES.map((s, i) => (
          <li
            key={s.key}
            className={cn(
              'relative flex flex-col md:flex-row md:items-center',
              i % 2 === 0 ? 'md:flex-row' : 'md:flex-row-reverse',
            )}
          >
            <span
              className={cn(
                'absolute left-4 z-10 h-3 w-3 -translate-x-1/2 rounded-full border-2 md:left-1/2',
                i <= active ? 'border-[var(--color-accent)] bg-[var(--color-accent)]' : 'border-zinc-300 bg-white',
              )}
            />
            <div className={cn('ml-10 md:ml-0 md:w-1/2', i % 2 === 0 ? 'md:pr-12 md:text-right' : 'md:pl-12')}>
              <p className={cn('text-lg font-medium', i <= active ? 'text-zinc-900' : 'text-zinc-400')}>{s.label}</p>
              {i === active && (
                <p className="mt-1 text-sm text-zinc-500">Tracking · notifications · POD · COD</p>
              )}
            </div>
          </li>
        ))}
      </ol>
    </div>
  )
}
