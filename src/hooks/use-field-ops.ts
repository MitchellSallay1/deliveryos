import { useEffect, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase/client'
import {
  fetchCompanyRiderLocations,
  fetchOperationalAnalytics,
  fetchRiderPerformance,
  listDeliveryZones,
} from '@/services/field-ops-service'

export function useRiderLocationsLive(companyId: string | null, enabled: boolean) {
  const qc = useQueryClient()
  const query = useQuery({
    queryKey: ['rider-locations', companyId],
    queryFn: () => fetchCompanyRiderLocations(companyId!),
    enabled: !!companyId && enabled,
    refetchInterval: false,
  })

  useEffect(() => {
    if (!companyId || !enabled) return

    const channel = supabase
      .channel(`rider-locations:${companyId}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'rider_locations',
          filter: `company_id=eq.${companyId}`,
        },
        () => {
          void qc.invalidateQueries({ queryKey: ['rider-locations', companyId] })
        },
      )
      .subscribe()

    return () => {
      void supabase.removeChannel(channel)
    }
  }, [companyId, enabled, qc])

  return query
}

export function useDeliveryZones(companyId: string | null) {
  return useQuery({
    queryKey: ['delivery-zones', companyId],
    queryFn: () => listDeliveryZones(companyId!),
    enabled: !!companyId,
  })
}

export function useOperationalAnalytics(companyId: string | null, days = 30) {
  return useQuery({
    queryKey: ['operational-analytics', companyId, days],
    queryFn: () => fetchOperationalAnalytics(companyId!, days),
    enabled: !!companyId,
  })
}

export function useRiderPerformance(companyId: string | null, days = 30) {
  return useQuery({
    queryKey: ['rider-performance', companyId, days],
    queryFn: () => fetchRiderPerformance(companyId!, days),
    enabled: !!companyId,
  })
}

export type TrackingState = 'off' | 'available' | 'active_delivery' | 'paused'

export function useRiderGpsTracking(options: {
  enabled: boolean
  hasActiveJob: boolean
  deliveryId?: string | null
}) {
  const [trackingState, setTrackingState] = useState<TrackingState>('off')
  const [lastError, setLastError] = useState<string | null>(null)
  const [online, setOnline] = useState(
    typeof navigator !== 'undefined' ? navigator.onLine : true,
  )

  useEffect(() => {
    const on = () => setOnline(true)
    const off = () => setOnline(false)
    window.addEventListener('online', on)
    window.addEventListener('offline', off)
    return () => {
      window.removeEventListener('online', on)
      window.removeEventListener('offline', off)
    }
  }, [])

  useEffect(() => {
    if (!options.enabled || !options.hasActiveJob) {
      setTrackingState('off')
      return
    }

    if (!navigator.geolocation) {
      setLastError('Geolocation not supported')
      return
    }

    setTrackingState('active_delivery')
    const watchId = navigator.geolocation.watchPosition(
      (pos) => {
        setLastError(null)
        void import('@/services/field-ops-service').then(({ recordRiderLocation }) =>
          recordRiderLocation({
            latitude: pos.coords.latitude,
            longitude: pos.coords.longitude,
            accuracy: pos.coords.accuracy,
            heading: pos.coords.heading ?? undefined,
            speed: pos.coords.speed ?? undefined,
            trackingState: 'active_delivery',
            deliveryId: options.deliveryId,
          }).catch((e) => {
            setLastError(e instanceof Error ? e.message : 'Location upload failed')
          }),
        )
      },
      (err) => setLastError(err.message),
      { enableHighAccuracy: true, maximumAge: 15_000, timeout: 20_000 },
    )

    return () => {
      navigator.geolocation.clearWatch(watchId)
      setTrackingState('off')
    }
  }, [options.enabled, options.hasActiveJob, options.deliveryId])

  return { trackingState, lastError, online }
}
