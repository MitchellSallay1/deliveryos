import { StatusBadge } from '@/components/ui/StatusBadge'
import { cn } from '@/lib/utils'

const DEMO = {
  code: 'TRK-DEMO-1042',
  customer: 'Sample customer',
  pickup: 'Sinkor',
  destination: 'Paynesville',
  fee: 'LRD 350',
}

export function MarketingDeliveryCard({
  status,
  className,
  compact,
  style,
}: {
  status: string
  className?: string
  compact?: boolean
  style?: React.CSSProperties
}) {
  return (
    <div
      style={style}
      className={cn(
        'mkt-panel p-4 shadow-lg ring-1 ring-black/5',
        compact ? 'text-xs' : 'text-sm',
        className,
      )}
      aria-label="Sample delivery card"
    >
      <div className="flex items-start justify-between gap-2">
        <div>
          <p className="font-semibold text-zinc-900">{DEMO.customer}</p>
          <p className="font-mono text-[10px] text-zinc-500">{DEMO.code}</p>
        </div>
        <StatusBadge status={status} />
      </div>
      {!compact && (
        <>
          <p className="mt-3 text-zinc-600">
            {DEMO.pickup} → {DEMO.destination}
          </p>
          <p className="mt-2 text-xs text-zinc-500">Fee {DEMO.fee} · Demo data</p>
        </>
      )}
    </div>
  )
}
