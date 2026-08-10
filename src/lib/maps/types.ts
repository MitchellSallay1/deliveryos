/** Provider-neutral map types (Leaflet today, Google Maps later). */

export type MapCoordinate = {
  latitude: number
  longitude: number
}

export type MapMarker = MapCoordinate & {
  id: string
  label?: string
  kind?: 'rider' | 'pickup' | 'destination' | 'approximate'
  /** Optional — when set, renders a colored status dot instead of the default pin. Backward compatible: omit to keep the default marker. */
  status?: 'online' | 'busy' | 'offline'
}

export type MapViewport = {
  center: MapCoordinate
  zoom: number
}

export type MapProvider = 'leaflet' | 'google'

export const DEFAULT_VIEWPORT: MapViewport = {
  center: { latitude: 6.3156, longitude: -10.8074 },
  zoom: 12,
}
