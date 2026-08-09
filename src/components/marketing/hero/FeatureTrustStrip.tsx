import {
  Globe,
  Lock,
  MapPin,
  Network,
  Smartphone,
  Wallet,
} from 'lucide-react'

const ITEMS = [
  { icon: Smartphone, title: 'Smartphone + Button Phone', sub: 'Built for every rider.' },
  { icon: MapPin, title: 'Real-time Tracking', sub: 'Live visibility across every delivery.' },
  { icon: Wallet, title: 'COD Reconciliation', sub: 'Know where every dollar goes.' },
  { icon: Network, title: 'Delivery Network', sub: 'Your riders. Our network.' },
  { icon: Globe, title: 'API & Integrations', sub: 'Connect what matters.' },
  { icon: Lock, title: 'Enterprise Security', sub: 'Your data. You control.' },
]

export function FeatureTrustStrip() {
  return (
    <div className="relative z-30 -mt-16 mx-auto max-w-[1320px] px-4 sm:px-6 lg:-mt-20 lg:px-8">
      <div className="rounded-2xl border border-zinc-100 bg-white px-4 py-8 shadow-[0_24px_60px_rgba(0,0,0,0.12)] sm:px-8 lg:py-10">
        <div className="grid grid-cols-2 gap-6 md:grid-cols-3 lg:grid-cols-6 lg:gap-4">
          {ITEMS.map(({ icon: Icon, title, sub }) => (
            <div key={title} className="flex flex-col items-center text-center lg:items-start lg:text-left">
              <Icon className="h-6 w-6 text-zinc-800" strokeWidth={1.5} aria-hidden />
              <p className="mt-3 text-xs font-semibold leading-snug text-zinc-900 sm:text-sm">{title}</p>
              <p className="mt-1 text-[11px] leading-snug text-zinc-500">{sub}</p>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
