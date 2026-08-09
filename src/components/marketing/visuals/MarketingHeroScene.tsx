import { useEffect, useState } from 'react'
import { MarketingControlTower } from '@/components/marketing/visuals/MarketingControlTower'
import { MarketingDeliveryCard } from '@/components/marketing/visuals/MarketingDeliveryCard'
import { MarketingCodPanel } from '@/components/marketing/visuals/MarketingCodPanel'
import { usePrefersReducedMotion } from '@/hooks/use-prefers-reduced-motion'
import { cn } from '@/lib/utils'

const STATUS_CYCLE = ['assigned', 'picked_up', 'in_transit', 'delivered'] as const

export function MarketingHeroScene() {
  const reduced = usePrefersReducedMotion()
  const [idx, setIdx] = useState(0)
  const status = STATUS_CYCLE[idx]!

  useEffect(() => {
    if (reduced) return
    const t = window.setInterval(() => setIdx((i) => (i + 1) % STATUS_CYCLE.length), 4200)
    return () => window.clearInterval(t)
  }, [reduced])

  return (
    <div className="relative mx-auto aspect-[4/3] max-w-xl lg:max-w-none lg:aspect-auto lg:min-h-[420px]" aria-hidden>
      <div className="absolute inset-0 rounded-3xl bg-gradient-to-br from-zinc-200/40 via-transparent to-[var(--color-accent)]/10" />
      <div className="absolute left-1/2 top-8 w-[92%] max-w-md -translate-x-1/2 lg:left-auto lg:top-6 lg:w-[min(100%,520px)] lg:translate-x-0 lg:right-0">
        <MarketingControlTower deliveryStatus={status} className="mkt-animate-float" />
      </div>
      <MarketingDeliveryCard
        status={status}
        className={cn(
          'absolute left-0 top-[38%] z-10 w-[min(240px,55%)] mkt-animate-float shadow-2xl',
          !reduced && 'transition-transform duration-700',
        )}
        style={!reduced ? { animationDelay: '0.8s' } : undefined}
      />
      <div
        className="absolute bottom-8 left-[8%] z-10 w-[min(200px,48%)] rounded-2xl border border-zinc-200/80 bg-white/95 p-3 shadow-xl backdrop-blur-md mkt-animate-float"
        style={{ animationDelay: '1.2s' }}
      >
        <p className="text-[10px] font-semibold uppercase tracking-wider text-zinc-500">Rider · demo</p>
        <p className="mt-1 text-sm font-medium text-zinc-900">En route · Paynesville</p>
        <div className="mt-2 flex items-center gap-2">
          <span className="relative flex h-8 w-8 items-center justify-center rounded-full bg-[var(--color-accent)]/30">
            <span className="absolute h-full w-full rounded-full bg-[var(--color-accent)]/40 mkt-animate-pulse-soft" />
            <span className="relative h-2 w-2 rounded-full bg-[var(--color-accent)]" />
          </span>
          <span className="text-xs text-zinc-600">GPS sample</span>
        </div>
      </div>
      <div className="absolute bottom-4 right-0 z-10 w-[min(220px,52%)]">
        <MarketingCodPanel compact />
      </div>
      <div
        className={cn(
          'absolute right-[6%] top-[22%] z-20 max-w-[200px] rounded-xl border border-zinc-200 bg-white px-3 py-2 shadow-lg transition-all duration-500',
          status === 'delivered' ? 'translate-y-0 opacity-100' : 'translate-y-2 opacity-0 pointer-events-none',
        )}
      >
        <p className="text-xs font-medium text-zinc-900">Delivery completed</p>
        <p className="text-[10px] text-zinc-500">Demo notification</p>
      </div>
    </div>
  )
}
