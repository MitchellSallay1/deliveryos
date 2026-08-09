import {
  BarChart3,
  Bell,
  ChevronDown,
  LayoutGrid,
  MapPin,
  Package,
  Settings,
  Store,
  Truck,
  Users,
  Wallet,
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { usePrefersReducedMotion } from '@/hooks/use-prefers-reduced-motion'

const NAV = [
  { icon: LayoutGrid, label: 'Overview', active: true },
  { icon: Package, label: 'Deliveries' },
  { icon: Truck, label: 'Riders' },
  { icon: Users, label: 'Customers' },
  { icon: MapPin, label: 'Tracking' },
  { icon: Wallet, label: 'Finance' },
  { icon: Truck, label: 'Fleet' },
  { icon: Store, label: 'Marketplace' },
  { icon: BarChart3, label: 'Reports' },
  { icon: Settings, label: 'Settings' },
]

const KPIS = [
  { label: 'Deliveries Today', value: '1,248', delta: '+12%' },
  { label: 'In Transit', value: '432', delta: '+5%' },
  { label: 'Completed', value: '816', delta: '+18%' },
  { label: 'COD Collected', value: 'LRD 1.2M', delta: '+8%' },
]

const RECENT = [
  { id: '#ORD-9921', status: 'In Transit', color: 'text-orange-400' },
  { id: '#ORD-9920', status: 'Delivered', color: 'text-emerald-400' },
  { id: '#ORD-9919', status: 'Picked Up', color: 'text-violet-400' },
  { id: '#ORD-9918', status: 'Assigned', color: 'text-sky-400' },
]

function FakeMap() {
  const reduced = usePrefersReducedMotion()
  return (
    <div className="relative h-full min-h-[140px] overflow-hidden rounded-lg bg-[#0d0f12]">
      <svg className="absolute inset-0 h-full w-full opacity-40" aria-hidden>
        <defs>
          <pattern id="grid" width="24" height="24" patternUnits="userSpaceOnUse">
            <path d="M 24 0 L 0 0 0 24" fill="none" stroke="#333" strokeWidth="0.5" />
          </pattern>
        </defs>
        <rect width="100%" height="100%" fill="url(#grid)" />
        <path
          d="M20 120 Q80 80 140 100 T260 60"
          fill="none"
          stroke="#FFCB05"
          strokeWidth="2"
          strokeDasharray="4 4"
          className={!reduced ? 'mkt-route-pulse' : undefined}
        />
      </svg>
      <span className="absolute left-[30%] top-[40%] h-2 w-2 rounded-full bg-[#FFCB05] shadow-[0_0_12px_#FFCB05]" />
      <span className="absolute left-[55%] top-[55%] h-2 w-2 rounded-full bg-orange-400" />
      <span className="absolute right-[20%] top-[35%] rounded bg-black/60 px-2 py-0.5 text-[9px] text-zinc-300">Live Map · demo</span>
    </div>
  )
}

export function HeroControlTower({
  className,
  prominent,
}: {
  className?: string
  /** Slightly larger shadow and scale for marketing hero compositions */
  prominent?: boolean
}) {
  const reduced = usePrefersReducedMotion()

  return (
    <div
      className={cn(
        'overflow-hidden rounded-2xl border border-white/10 bg-[#121417] text-zinc-200 shadow-[0_32px_80px_rgba(0,0,0,0.55)]',
        prominent &&
          'border-white/15 shadow-[0_48px_120px_rgba(0,0,0,0.72)] ring-1 ring-[#FFCB05]/15 lg:min-h-[500px]',
        !reduced && 'mkt-hero-float',
        className,
      )}
      aria-label="DeliveryOS control tower preview"
    >
      <div
        className={cn(
          'flex min-h-[420px] sm:min-h-[480px]',
          prominent && 'sm:min-h-[500px] lg:min-h-[520px]',
        )}
      >
        <aside className="hidden w-12 shrink-0 flex-col items-center gap-3 border-r border-white/5 bg-[#0f1114] py-4 sm:flex lg:w-14">
          {NAV.map(({ icon: Icon, label, active }) => (
            <span
              key={label}
              title={label}
              className={cn(
                'flex h-8 w-8 items-center justify-center rounded-lg',
                active ? 'bg-[#FFCB05]/20 text-[#FFCB05]' : 'text-zinc-500',
              )}
            >
              <Icon className="h-4 w-4" />
            </span>
          ))}
        </aside>
        <div className="min-w-0 flex-1 p-3 sm:p-4">
          <div className="flex flex-wrap items-center justify-between gap-2 border-b border-white/5 pb-3">
            <div>
              <p className="text-sm font-semibold text-white">Good morning, Admin</p>
              <button type="button" className="mt-0.5 flex items-center gap-1 text-[10px] text-zinc-500">
                Monrovia HQ <ChevronDown className="h-3 w-3" />
              </button>
            </div>
            <div className="flex items-center gap-2">
              <Bell className="h-4 w-4 text-zinc-500" />
              <span className="h-7 w-7 rounded-full bg-zinc-700" />
            </div>
          </div>
          <div className="mt-3 grid grid-cols-2 gap-2 lg:grid-cols-4">
            {KPIS.map((k) => (
              <div key={k.label} className="rounded-lg border border-white/5 bg-[#181A1D] px-2 py-2 sm:px-3">
                <p className="text-[9px] uppercase tracking-wide text-zinc-500">{k.label}</p>
                <p className="text-sm font-semibold tabular-nums text-white sm:text-base">{k.value}</p>
                <p className="text-[10px] text-emerald-400">{k.delta} demo</p>
              </div>
            ))}
          </div>
          <div className="mt-3 grid gap-2 lg:grid-cols-5">
            <div className="lg:col-span-3">
              <p className="mb-1 text-[10px] font-medium uppercase tracking-wide text-zinc-500">Live Map</p>
              <FakeMap />
            </div>
            <div className="lg:col-span-2">
              <p className="mb-1 text-[10px] font-medium uppercase tracking-wide text-zinc-500">Recent Deliveries</p>
              <ul className="space-y-1.5 rounded-lg border border-white/5 bg-[#181A1D] p-2">
                {RECENT.map((r) => (
                  <li key={r.id} className="flex justify-between text-[11px]">
                    <span className="font-mono text-zinc-400">{r.id}</span>
                    <span className={cn('font-medium', r.color)}>{r.status}</span>
                  </li>
                ))}
              </ul>
            </div>
          </div>
          <div className="mt-2 grid gap-2 sm:grid-cols-2">
            <div className="rounded-lg border border-white/5 bg-[#181A1D] p-2">
              <p className="text-[10px] text-zinc-500">Deliveries Trend</p>
              <svg viewBox="0 0 200 48" className="mt-1 h-12 w-full text-[#FFCB05]" aria-hidden>
                <polyline
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2"
                  points="0,40 30,35 60,28 90,32 120,18 150,22 180,8 200,12"
                />
              </svg>
            </div>
            <div className="rounded-lg border border-white/5 bg-[#181A1D] p-2">
              <p className="text-[10px] text-zinc-500">Rider Status · 256 total</p>
              <div className="mt-2 flex items-center gap-3">
                <div className="relative h-12 w-12 rounded-full border-4 border-[#FFCB05] border-r-emerald-500 border-b-orange-400 border-l-zinc-600" />
                <div className="text-[10px] text-zinc-400">
                  <p>Online 142</p>
                  <p>Busy 68</p>
                  <p>Offline 46</p>
                </div>
              </div>
            </div>
          </div>
          <p className="mt-2 text-center text-[9px] text-zinc-600">Marketing preview · sample data only</p>
        </div>
      </div>
    </div>
  )
}
