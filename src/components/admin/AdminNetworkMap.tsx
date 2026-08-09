import { useState } from 'react'
import { LeafletMap } from '@/components/maps/LeafletMap'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { useAdminMapPoints } from '@/hooks/use-admin-platform'
import { DEFAULT_VIEWPORT } from '@/lib/maps/types'
import type { MapMarker } from '@/lib/maps/types'

export function AdminNetworkMap() {
  const [companyId] = useState<string | undefined>()
  const { data, isLoading } = useAdminMapPoints(companyId, true)

  const riders = (data?.riders ?? []) as Array<{
    latitude: number
    longitude: number
    company_name: string
    rider_id: string
  }>

  const markers: MapMarker[] = riders.map((r) => ({
    id: r.rider_id,
    latitude: r.latitude,
    longitude: r.longitude,
    label: `${r.company_name} · rider`,
    kind: 'rider',
  }))

  return (
    <Card>
      <CardHeader>
        <CardTitle>Network map</CardTitle>
        <p className="text-sm text-[var(--color-muted)]">
          Rider positions only. Customer addresses are not plotted.
        </p>
      </CardHeader>
      <CardContent>
        {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
        <LeafletMap markers={markers} viewport={DEFAULT_VIEWPORT} className="h-[480px] w-full rounded-xl border" />
        <p className="mt-2 text-xs text-[var(--color-muted)]">
          {(data?.deliveries as unknown[])?.length ?? 0} active deliveries in list (not geocoded on map).
        </p>
      </CardContent>
    </Card>
  )
}
