import { CheckCircle2, Package, UserCheck } from 'lucide-react'
import { cn } from '@/lib/utils'
import { usePrefersReducedMotion } from '@/hooks/use-prefers-reduced-motion'

export type HeroNotificationCard = {
  icon: typeof Package
  iconClass: string
  title: string
  id: string
  lines: string[]
  demo?: boolean
}

const DEFAULT_CARDS: HeroNotificationCard[] = [
  {
    icon: Package,
    iconClass: 'text-amber-500 bg-amber-50',
    title: 'New Order Received',
    id: '#ORD-9921',
    lines: ['Payment: COD', 'Amount: LRD 3,600'],
    demo: true,
  },
  {
    icon: UserCheck,
    iconClass: 'text-emerald-600 bg-emerald-50',
    title: 'Rider Assigned',
    id: 'James K.',
    lines: ['Heading to pickup'],
    demo: true,
  },
  {
    icon: CheckCircle2,
    iconClass: 'text-emerald-600 bg-emerald-50',
    title: 'Delivered',
    id: '#ORD-9920',
    lines: ['Amount: LRD 2,700'],
    demo: true,
  },
]

/** Short labels for product tour hero bridge */
export const HERO_TOUR_NOTIFICATIONS: HeroNotificationCard[] = [
  {
    icon: Package,
    iconClass: 'text-amber-500 bg-amber-50',
    title: 'New Order',
    id: '#ORD-9921',
    lines: ['COD · LRD 3,600'],
    demo: true,
  },
  {
    icon: UserCheck,
    iconClass: 'text-emerald-600 bg-emerald-50',
    title: 'Rider Assigned',
    id: 'James K.',
    lines: ['En route to pickup'],
    demo: true,
  },
  {
    icon: CheckCircle2,
    iconClass: 'text-emerald-600 bg-emerald-50',
    title: 'Delivered',
    id: '#ORD-9920',
    lines: ['LRD 2,700 collected'],
    demo: true,
  },
]

export function HeroNotificationStack({
  className,
  cards = DEFAULT_CARDS,
  showDemoLabel = true,
}: {
  className?: string
  cards?: HeroNotificationCard[]
  showDemoLabel?: boolean
}) {
  const reduced = usePrefersReducedMotion()

  return (
    <div className={cn('flex flex-col gap-3', className)} aria-hidden>
      {cards.map((card, i) => (
        <div
          key={card.title}
          className={cn(
            'w-[min(240px,72vw)] rounded-xl border border-zinc-100 bg-white px-4 py-3 shadow-[0_12px_40px_rgba(0,0,0,0.35)]',
            !reduced && 'mkt-hero-notify',
          )}
          style={!reduced ? { animationDelay: `${i * 0.15}s` } : undefined}
        >
          <div className="flex gap-3">
            <span className={cn('flex h-9 w-9 shrink-0 items-center justify-center rounded-lg', card.iconClass)}>
              <card.icon className="h-4 w-4" />
            </span>
            <div className="min-w-0">
              <p className="text-sm font-semibold text-zinc-900">{card.title}</p>
              <p className="text-xs font-medium text-zinc-700">{card.id}</p>
              {card.lines.map((l) => (
                <p key={l} className="text-[11px] text-zinc-500">
                  {l}
                </p>
              ))}
            </div>
          </div>
        </div>
      ))}
      {showDemoLabel && <p className="text-[9px] text-zinc-500">Demo notifications</p>}
    </div>
  )
}
