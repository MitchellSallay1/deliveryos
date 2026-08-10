import { useEffect } from 'react'
import { MapContainer, Marker, Popup, TileLayer, useMap } from 'react-leaflet'
import L from 'leaflet'
import type { MapMarker, MapViewport } from '@/lib/maps/types'
import { DEFAULT_VIEWPORT } from '@/lib/maps/types'
import 'leaflet/dist/leaflet.css'

const icon = L.icon({
  iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
  iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
  shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
  iconSize: [25, 41],
  iconAnchor: [12, 41],
})

const STATUS_DOT_COLOR: Record<NonNullable<MapMarker['status']>, string> = {
  online: '#22c55e',
  busy: '#f59e0b',
  offline: '#71717a',
}

/** Lightweight colored-dot marker for status-aware maps (e.g. admin rider clusters) — no extra image assets. */
function statusDivIcon(status: NonNullable<MapMarker['status']>) {
  const color = STATUS_DOT_COLOR[status]
  return L.divIcon({
    className: '',
    html: `<span style="display:block;width:14px;height:14px;border-radius:9999px;background:${color};border:2px solid rgba(0,0,0,0.5);box-shadow:0 0 0 2px rgba(255,255,255,0.15)"></span>`,
    iconSize: [14, 14],
    iconAnchor: [7, 7],
  })
}

function Recenter({ viewport }: { viewport: MapViewport }) {
  const map = useMap()
  useEffect(() => {
    map.setView([viewport.center.latitude, viewport.center.longitude], viewport.zoom)
  }, [map, viewport.center.latitude, viewport.center.longitude, viewport.zoom])
  return null
}

export function LeafletMap({
  markers,
  viewport = DEFAULT_VIEWPORT,
  className,
}: {
  markers: MapMarker[]
  viewport?: MapViewport
  className?: string
}) {
  return (
    <MapContainer
      center={[viewport.center.latitude, viewport.center.longitude]}
      zoom={viewport.zoom}
      scrollWheelZoom
      className={className ?? 'h-64 w-full rounded-lg border z-0'}
    >
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      <Recenter viewport={viewport} />
      {markers.map((m) => (
        <Marker key={m.id} position={[m.latitude, m.longitude]} icon={m.status ? statusDivIcon(m.status) : icon}>
          {m.label ? <Popup>{m.label}</Popup> : null}
        </Marker>
      ))}
    </MapContainer>
  )
}
