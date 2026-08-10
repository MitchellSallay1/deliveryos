import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { MapSurface } from '@/components/maps/MapSurface'
import { WidgetError } from '@/components/dashboard/WidgetError'
import { PlanUpgradeNotice } from '@/components/dashboard/PlanUpgradeNotice'
import { useAuth } from '@/hooks/use-auth'
import { useRiderLocationsLive } from '@/hooks/use-field-ops'
import { friendlyDashboardError, isGpsNotEnabledError } from '@/lib/dashboard-metrics'
import type { MapMarker, MapViewport } from '@/lib/maps/types'
import { DEFAULT_VIEWPORT } from '@/lib/maps/types'
import { useMemo } from 'react'

export function LiveMapPage() {
  const { context } = useAuth()
  const companyId = context?.activeCompanyId ?? null
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
      return { center: { latitude: markers[0].latitude, longitude: markers[0].longitude }, zoom: 13 }
    }
    return DEFAULT_VIEWPORT
  }, [markers])

  return (
    <div className="space-y-4">
      <div>
        <h2 className="text-xl font-semibold">Live map</h2>
        <p className="text-sm text-[var(--color-muted)]">
          Realtime rider positions for your company (GPS plan required).
        </p>
      </div>
      {error ? (
        <Card>
          <CardContent className="pt-6">
            {isGpsNotEnabledError(error) ? (
              <PlanUpgradeNotice message="Live GPS tracking is not included in your current plan." />
            ) : (
              <WidgetError message={friendlyDashboardError(error)} onRetry={() => void refetch()} />
            )}
          </CardContent>
        </Card>
      ) : (
        <>
          <MapSurface markers={markers} viewport={viewport} className="h-[min(70vh,520px)] w-full" />
          <Card>
            <CardHeader>
              <CardTitle>Active riders</CardTitle>
              <CardDescription>Updates via Supabase Realtime — no polling.</CardDescription>
            </CardHeader>
            <CardContent className="space-y-2 text-sm">
              {isLoading && <p className="text-[var(--color-muted)]">Loading…</p>}
              {riders.map((r) => (
                <div key={r.rider_id} className="flex flex-wrap justify-between gap-2 border-b py-2">
                  <span>
                    {r.rider_name} · {r.rider_code}
                  </span>
                  <span className="text-[var(--color-muted)]">
                    {r.delivery_status ?? r.rider_status} ·{' '}
                    {new Date(r.recorded_at).toLocaleTimeString()}
                  </span>
                </div>
              ))}
              {!isLoading && riders.length === 0 && (
                <p className="text-[var(--color-muted)]">No live locations right now.</p>
              )}
            </CardContent>
          </Card>
        </>
      )}
    </div>
  )
}
