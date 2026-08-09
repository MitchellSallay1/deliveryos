import { KpiCard } from '@/components/ui/KpiCard'
import { MarketingDeliveryCard } from '@/components/marketing/visuals/MarketingDeliveryCard'
import { Package, Radio, Users } from 'lucide-react'
import { cn } from '@/lib/utils'

/** Large control tower panel — demo KPIs only */
export function MarketingControlTower({
  className,
  deliveryStatus = 'in_transit',
  dark,
}: {
  className?: string
  deliveryStatus?: string
  dark?: boolean
}) {
  return (
    <div
      className={cn(
        'overflow-hidden rounded-2xl border p-5 sm:p-6',
        dark ? 'mkt-grid-bg border-white/10 bg-zinc-950 text-white mkt-glow' : 'mkt-panel shadow-xl',
        className,
      )}
    >
      <div className="flex items-center justify-between gap-2 border-b border-inherit pb-4 opacity-90">
        <div>
          <p className="text-[10px] font-semibold uppercase tracking-widest text-zinc-500">Control tower</p>
          <p className={cn('text-sm font-semibold', dark ? 'text-white' : 'text-zinc-900')}>Live operations</p>
        </div>
        <span className="flex items-center gap-1.5 rounded-full bg-emerald-500/15 px-2 py-0.5 text-[10px] font-medium text-emerald-400">
          <span className="h-1.5 w-1.5 rounded-full bg-emerald-400 mkt-animate-pulse-soft" />
          Demo
        </span>
      </div>
      <div className="mt-4 grid gap-3 sm:grid-cols-3">
        <KpiCard label="Today" value="18" icon={Package} className="!p-3 !shadow-none !text-left" />
        <KpiCard label="Riders" value="6" icon={Users} className="!p-3 !shadow-none" />
        <KpiCard label="In transit" value="4" icon={Radio} className="!p-3 !shadow-none" />
      </div>
      <div className="mt-4 space-y-2">
        <MarketingDeliveryCard status={deliveryStatus} />
        <MarketingDeliveryCard status="assigned" compact />
      </div>
      <p className="mt-3 text-center text-[10px] text-zinc-500">Illustrative workspace preview</p>
    </div>
  )
}
