import { lazy, Suspense } from 'react'
import type { MapMarker, MapViewport } from '@/lib/maps/types'

const LeafletMap = lazy(() =>
  import('@/components/maps/LeafletMap').then((m) => ({ default: m.LeafletMap })),
)

type MapSurfaceProps = {
  markers: MapMarker[]
  viewport?: MapViewport
  className?: string
}

export function MapSurface({ markers, viewport, className }: MapSurfaceProps) {
  return (
    <Suspense
      fallback={
        <div className={className ?? 'h-64 w-full rounded-lg border bg-[var(--color-muted)]/10'} />
      }
    >
      <LeafletMap markers={markers} viewport={viewport} className={className} />
    </Suspense>
  )
}
