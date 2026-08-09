import { useMemo } from 'react'
import { Navigate } from 'react-router-dom'
import { DeliveryPhotoButton } from '@/components/DeliveryPhotoButton'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { useAuth } from '@/hooks/use-auth'
import { useLinkedRiders, useRiderJobs, useRiderTransition } from '@/hooks/use-rider-portal'
import { useRiderGpsTracking } from '@/hooks/use-field-ops'
import { isRiderLinked } from '@/lib/post-auth-navigation'
import {
  formatLrdFromCents,
  NEXT_STATUS,
  statusLabel,
} from '@/utils/delivery-schemas'

export function RiderJobsPage() {
  const { context, user } = useAuth()

  const { data: linked = [], isLoading: linkedLoading } = useLinkedRiders(user?.id)
  const activeRider = useMemo(() => linked[0] ?? null, [linked])

  const { data: jobs = [], isLoading: jobsLoading } = useRiderJobs(activeRider?.id ?? null)
  const activeJob = jobs.find((j) =>
    ['assigned', 'accepted', 'picked_up', 'in_transit'].includes(j.status),
  )
  const gps = useRiderGpsTracking({
    enabled: !!activeRider,
    hasActiveJob: !!activeJob,
    deliveryId: activeJob?.id,
  })
  const transition = useRiderTransition(activeRider?.id ?? null)

  if (!linkedLoading && context && !isRiderLinked(context) && linked.length === 0) {
    return <Navigate to="/link-rider" replace />
  }

  return (
    <div className="mx-auto max-w-lg space-y-4 pb-8">
      <div>
        <h2 className="text-xl font-semibold">My jobs</h2>
        <p className="text-sm text-[var(--color-muted)]">
          Mobile-friendly view for riders on active deliveries.
        </p>
        {!gps.online && (
          <p className="mt-1 text-xs text-amber-700">Offline — status changes queue when online.</p>
        )}
        {gps.trackingState !== 'off' && (
          <p className="mt-1 text-xs text-[var(--color-muted)]">
            GPS: {gps.trackingState.replace('_', ' ')}
            {gps.lastError ? ` · ${gps.lastError}` : ''}
          </p>
        )}
      </div>

      {activeRider && (
        <p className="text-sm text-[var(--color-muted)]">
          Linked as <strong>{activeRider.rider_code}</strong> · {activeRider.full_name}
        </p>
      )}

      {jobsLoading && <p className="text-sm text-[var(--color-muted)]">Loading jobs…</p>}

      {activeRider &&
        jobs.map((job) => {
          const next = NEXT_STATUS[job.status as keyof typeof NEXT_STATUS] ?? []
          const riderActions = next.filter(
            (s) => !['pending', 'assigned', 'cancelled'].includes(s),
          )

          return (
            <Card key={job.id}>
              <CardHeader className="pb-2">
                <CardTitle className="text-base">{job.customer_name}</CardTitle>
                <CardDescription>{job.customer_phone}</CardDescription>
              </CardHeader>
              <CardContent className="space-y-3 text-sm">
                <div>
                  <p className="font-medium">{job.pickup_business_name}</p>
                  <p className="text-[var(--color-muted)]">{job.pickup_address}</p>
                </div>
                <div>
                  <p className="text-xs uppercase text-[var(--color-muted)]">Deliver to</p>
                  <p>{job.destination_address}</p>
                </div>
                <p>
                  COD {formatLrdFromCents(job.amount_to_collect_lrd_cents)} ·{' '}
                  <span className="capitalize">{statusLabel(job.status)}</span>
                </p>
                <div className="flex flex-wrap gap-2">
                  {riderActions.map((s) => (
                    <Button
                      key={s}
                      type="button"
                      size="sm"
                      variant={s === 'failed' ? 'destructive' : 'default'}
                      disabled={transition.isPending}
                      onClick={() =>
                        transition.mutate({ deliveryId: job.id, status: s })
                      }
                    >
                      {statusLabel(s)}
                    </Button>
                  ))}
                </div>
                {['picked_up', 'in_transit', 'delivered'].includes(job.status) && (
                  <DeliveryPhotoButton companyId={job.company_id} deliveryId={job.id} />
                )}
              </CardContent>
            </Card>
          )
        })}

      {activeRider && !jobsLoading && jobs.length === 0 && (
        <Card>
          <CardContent className="py-8 text-center text-sm text-[var(--color-muted)]">
            No active assignments. Wait for dispatch to assign a delivery.
          </CardContent>
        </Card>
      )}
    </div>
  )
}
