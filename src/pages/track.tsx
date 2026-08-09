import { useEffect, useMemo, useState } from 'react'
import { useParams } from 'react-router-dom'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { MapSurface } from '@/components/maps/MapSurface'
import { fetchPublicDeliveryTracking } from '@/services/field-ops-service'
import { parseSupabaseError } from '@/lib/supabase-errors'
import type { MapMarker } from '@/lib/maps/types'
import { statusLabel } from '@/utils/delivery-schemas'

type PublicTracking = {
  tracking_code: string
  status: string
  company_name: string
  pickup_area: string
  destination_area: string
  updated_at: string
  rider_location?: {
    latitude: number
    longitude: number
    recorded_at: string
    approximate: boolean
  } | null
  status_timeline?: { status: string; at: string }[]
}

export function TrackPage() {
  const { code } = useParams()
  const [data, setData] = useState<PublicTracking | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!code) return
    fetchPublicDeliveryTracking(code)
      .then((row) => {
        if (!row) setError('Delivery not found')
        else setData(row as PublicTracking)
      })
      .catch((e) => setError(parseSupabaseError(e)))
  }, [code])

  const markers: MapMarker[] = useMemo(() => {
    if (!data?.rider_location) return []
    return [
      {
        id: 'rider-approx',
        latitude: data.rider_location.latitude,
        longitude: data.rider_location.longitude,
        label: 'Approximate rider location',
        kind: 'approximate',
      },
    ]
  }, [data])

  return (
    <div className="flex min-h-screen items-center justify-center bg-[var(--color-background)] p-4">
      <Card className="w-full max-w-lg">
        <CardHeader>
          <CardTitle>Package tracking</CardTitle>
          <CardDescription>{data?.company_name ?? 'DeliveryOS'}</CardDescription>
        </CardHeader>
        <CardContent className="space-y-3 text-sm">
          {error && <p className="text-red-600">{error}</p>}
          {data && (
            <>
              <p>
                Status: <strong className="capitalize">{statusLabel(data.status)}</strong>
              </p>
              <p className="text-[var(--color-muted)]">Destination area: {data.destination_area}</p>
              {data.rider_location && (
                <>
                  <MapSurface markers={markers} className="h-48 w-full" />
                  <p className="text-xs text-[var(--color-muted)]">
                    Approximate rider position · updated{' '}
                    {new Date(data.rider_location.recorded_at).toLocaleString()}
                  </p>
                </>
              )}
              <ul className="text-xs text-[var(--color-muted)]">
                {(data.status_timeline ?? []).map((s) => (
                  <li key={`${s.status}-${s.at}`}>
                    {statusLabel(s.status)} · {new Date(s.at).toLocaleString()}
                  </li>
                ))}
              </ul>
              <p className="text-xs text-[var(--color-muted)]">Ref: {data.tracking_code}</p>
            </>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
