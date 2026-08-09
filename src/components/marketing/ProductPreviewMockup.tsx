import { Link } from 'react-router-dom'
import { KpiCard } from '@/components/ui/KpiCard'
import { StatusBadge } from '@/components/ui/StatusBadge'
import { Truck, Users, Package } from 'lucide-react'

/** Static product preview using real app UI primitives — no tenant data. */
export function ProductPreviewMockup() {
  return (
    <div className="relative overflow-hidden rounded-2xl border border-zinc-200 bg-zinc-50 p-4 shadow-2xl ring-1 ring-black/5 sm:p-6">
      <div className="mb-4 flex items-center justify-between border-b border-zinc-200 pb-3">
        <div>
          <p className="text-xs font-medium uppercase tracking-wide text-zinc-500">Operations center</p>
          <p className="text-sm font-semibold text-zinc-900">Live deliveries</p>
        </div>
        <span className="rounded-full bg-emerald-100 px-2 py-0.5 text-xs font-medium text-emerald-800">Realtime</span>
      </div>
      <div className="grid gap-3 sm:grid-cols-3">
        <KpiCard label="Today" value="24" icon={Truck} className="!p-4 !shadow-none" />
        <KpiCard label="Active riders" value="8" icon={Users} className="!p-4 !shadow-none" />
        <KpiCard label="Pending" value="5" icon={Package} className="!p-4 !shadow-none" />
      </div>
      <div className="mt-4 space-y-2 rounded-xl border bg-white p-3">
        {[
          { name: 'Customer A.', code: 'TRK-DEMO-001', status: 'in_transit' },
          { name: 'Customer B.', code: 'TRK-DEMO-002', status: 'assigned' },
        ].map((row) => (
          <div key={row.code} className="flex items-center justify-between gap-2 text-sm">
            <div>
              <p className="font-medium text-zinc-900">{row.name}</p>
              <p className="text-xs text-zinc-500">{row.code}</p>
            </div>
            <StatusBadge status={row.status} />
          </div>
        ))}
      </div>
      <p className="mt-3 text-center text-[10px] text-zinc-400">Illustrative preview — not live data</p>
      <Link to="/register" className="mt-3 block text-center text-xs font-medium text-zinc-600 underline">
        Open your workspace
      </Link>
    </div>
  )
}
