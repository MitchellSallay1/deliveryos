import { useParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { supabase } from '@/lib/supabase/client'

export function VehicleDetailPage() {
  const { id } = useParams()
  const { data: vehicle, isLoading } = useQuery({
    queryKey: ['vehicle', id],
    queryFn: async () => {
      const { data, error } = await supabase.from('vehicles').select('*').eq('id', id!).maybeSingle()
      if (error) throw error
      return data as Record<string, unknown> | null
    },
    enabled: !!id,
  })

  const { data: maintenance = [] } = useQuery({
    queryKey: ['vehicle-maintenance', id],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('vehicle_maintenance_records')
        .select('*')
        .eq('vehicle_id', id!)
        .order('performed_at', { ascending: false })
        .limit(10)
      if (error) throw error
      return (data ?? []) as Record<string, unknown>[]
    },
    enabled: !!id,
  })

  if (isLoading) return <p className="text-sm text-[var(--color-muted)]">Loading…</p>
  if (!vehicle) return <p className="text-sm text-red-600">Vehicle not found</p>

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle>{String(vehicle.vehicle_code)}</CardTitle>
        </CardHeader>
        <CardContent className="text-sm">
          <p>
            {String(vehicle.make ?? '')} {String(vehicle.model ?? '')} ·{' '}
            {String(vehicle.registration_number ?? '—')}
          </p>
          <p className="text-[var(--color-muted)]">
            Odometer: {String(vehicle.odometer)} · Status: {String(vehicle.status)}
          </p>
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>Maintenance history</CardTitle>
        </CardHeader>
        <CardContent className="text-sm">
          <ul>
            {maintenance.map((m: Record<string, unknown>) => (
              <li key={String(m.id)} className="border-b py-2">
                {String(m.maintenance_type)} · {new Date(String(m.performed_at)).toLocaleDateString()}
              </li>
            ))}
            {!maintenance.length && <li className="text-[var(--color-muted)]">No records yet.</li>}
          </ul>
        </CardContent>
      </Card>
    </div>
  )
}
