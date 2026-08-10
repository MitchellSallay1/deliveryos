import { useMemo } from 'react'
import { Link } from 'react-router-dom'
import { LeafletMap } from '@/components/maps/LeafletMap'
import {
  CommandCard,
  CommandCardBody,
  CommandCardHeader,
  CommandEmptyState,
  CommandTable,
  CommandTableHead,
  CommandTd,
  CommandTh,
  CommandTr,
  StatusChip,
} from '@/components/admin/control-tower'
import { useAdminMapPoints } from '@/hooks/use-admin-platform'
import { DEFAULT_VIEWPORT } from '@/lib/maps/types'
import type { MapMarker } from '@/lib/maps/types'

type RiderPoint = {
  rider_id: string
  latitude: number
  longitude: number
  status: string
  company_id: string
  company_name: string
}

export function AdminNetworkMap() {
  const { data, isLoading } = useAdminMapPoints(undefined, true)

  const riders = (data?.riders ?? []) as RiderPoint[]
  const activeDeliveries = (data?.deliveries ?? []) as Array<{ id: string; status: string; company_name: string }>

  const markers: MapMarker[] = useMemo(
    () =>
      riders.map((r) => ({
        id: r.rider_id,
        latitude: r.latitude,
        longitude: r.longitude,
        label: `${r.company_name} · ${r.status}`,
        kind: 'rider',
        status: r.status === 'available' ? 'online' : r.status === 'busy' ? 'busy' : 'offline',
      })),
    [riders],
  )

  const onlineCount = riders.filter((r) => r.status === 'available' || r.status === 'busy').length
  const offlineCount = riders.length - onlineCount

  const coverage = useMemo(() => {
    const byCompany = new Map<string, { name: string; riders: number }>()
    for (const r of riders) {
      const existing = byCompany.get(r.company_id)
      if (existing) existing.riders += 1
      else byCompany.set(r.company_id, { name: r.company_name, riders: 1 })
    }
    return Array.from(byCompany.entries())
      .map(([id, v]) => ({ id, ...v }))
      .sort((a, b) => b.riders - a.riders)
  }, [riders])

  return (
    <div className="space-y-4">
      <div className="grid gap-4 xl:grid-cols-4">
        <CommandCard className="xl:col-span-3">
          <CommandCardHeader
            title="Live rider positions"
            description="Last reported location, most recent GPS ping per rider. Customer addresses are never plotted."
          />
          <CommandCardBody className="p-0">
            {isLoading && <p className="p-4 text-sm text-zinc-500">Loading positions…</p>}
            <LeafletMap markers={markers} viewport={DEFAULT_VIEWPORT} className="h-[480px] w-full rounded-b-xl" />
            <div className="flex flex-wrap items-center gap-4 border-t border-white/[0.06] px-4 py-2.5 text-xs text-zinc-400">
              <Legend color="#22c55e" label="Online / available" />
              <Legend color="#f59e0b" label="Busy" />
              <Legend color="#71717a" label="Offline" />
              <span className="ml-auto text-zinc-600">{riders.length} riders with recent location data</span>
            </div>
          </CommandCardBody>
        </CommandCard>

        <div className="space-y-4">
          <CommandCard>
            <CommandCardHeader title="Rider states" />
            <CommandCardBody className="space-y-2">
              <div className="flex items-center justify-between text-sm">
                <StatusChip color="green" label="Online" />
                <span className="font-medium tabular-nums text-zinc-100">{onlineCount}</span>
              </div>
              <div className="flex items-center justify-between text-sm">
                <StatusChip color="gray" label="Offline" />
                <span className="font-medium tabular-nums text-zinc-100">{offlineCount}</span>
              </div>
            </CommandCardBody>
          </CommandCard>

          <CommandCard>
            <CommandCardHeader title="Active deliveries" description="In transit right now" />
            <CommandCardBody>
              <p className="text-3xl font-semibold tabular-nums text-white">{activeDeliveries.length}</p>
              <p className="mt-1 text-xs text-zinc-500">
                Not geocoded — no pickup/destination coordinates are captured yet. Count only.
              </p>
            </CommandCardBody>
          </CommandCard>
        </div>
      </div>

      <CommandCard>
        <CommandCardHeader
          title="Company / branch coverage"
          description="Companies with at least one rider reporting a location"
        />
        {coverage.length === 0 ? (
          <CommandEmptyState label="No rider location data yet." />
        ) : (
          <CommandTable>
            <CommandTableHead>
              <CommandTh>Company</CommandTh>
              <CommandTh className="text-right">Riders on map</CommandTh>
            </CommandTableHead>
            <tbody>
              {coverage.map((c) => (
                <CommandTr key={c.id}>
                  <CommandTd>
                    <Link to={`/admin/companies/${c.id}`} className="hover:text-white hover:underline">
                      {c.name}
                    </Link>
                  </CommandTd>
                  <CommandTd className="text-right font-medium tabular-nums text-zinc-100">{c.riders}</CommandTd>
                </CommandTr>
              ))}
            </tbody>
          </CommandTable>
        )}
      </CommandCard>
    </div>
  )
}

function Legend({ color, label }: { color: string; label: string }) {
  return (
    <span className="flex items-center gap-1.5">
      <span className="h-2.5 w-2.5 rounded-full border border-black/40" style={{ backgroundColor: color }} />
      {label}
    </span>
  )
}
