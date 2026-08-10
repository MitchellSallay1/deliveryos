import { useMemo } from 'react'
import { Link } from 'react-router-dom'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/Card'
import { MapSurface } from '@/components/maps/MapSurface'
import { WidgetError } from '@/components/dashboard/WidgetError'
import { PlanUpgradeNotice } from '@/components/dashboard/PlanUpgradeNotice'
import { useRiderLocationsLive } from '@/hooks/use-field-ops'
import { friendlyDashboardError, isGpsNotEnabledError } from '@/lib/dashboard-metrics'
import type { MapMarker, MapViewport } from '@/lib/maps/types'
import { DEFAULT_VIEWPORT } from '@/lib/maps/types'

export function DashboardLiveMapCard({ companyId }: { companyId: string }) {
  const { data: riders = [], isLoading, error, refetch } = useRiderLocationsLive(companyId, true)

  const markers: MapMarker[] = useMemo(
    () =>
      riders.map((r) => ({
        id: r.rider_id,
        latitude: r.latitude,
        longitude: r.longitude,
        label: `${r.rider_name} (${r.rider_code}) · ${r.tracking_state}`,
        kind: 'rider' as const,
      })),
    [riders],
  )

  const viewport: MapViewport = useMemo(() => {
    if (markers[0]) {
      return { center: { latitude: markers[0].latitude, longitude: markers[0].longitude }, zoom: 12 }
    }
    return DEFAULT_VIEWPORT
  }, [markers])

  return (
    <Card>
      <CardHeader className="flex-row items-center justify-between pb-2">
        <div>
          <CardTitle className="text-base">Live map</CardTitle>
          <CardDescription>Realtime rider positions</CardDescription>
        </div>
        <Link to="/live-map" className="shrink-0 text-xs font-medium text-[var(--color-primary)] hover:underline">
          Full map
        </Link>
      </CardHeader>
      <CardContent>
        {error ? (
          isGpsNotEnabledError(error) ? (
            <PlanUpgradeNotice message="Live GPS tracking is not included in your current plan." />
          ) : (
            <WidgetError message={friendlyDashboardError(error)} onRetry={() => void refetch()} />
          )
        ) : (
          <>
            <MapSurface markers={markers} viewport={viewport} className="h-[280px] w-full rounded-lg" />
            {!isLoading && riders.length === 0 && (
              <p className="mt-2 text-center text-xs text-[var(--color-muted)]">
                No live rider locations right now.
              </p>
            )}
          </>
        )}
      </CardContent>
    </Card>
  )
}
