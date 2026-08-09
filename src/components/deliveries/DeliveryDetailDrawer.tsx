import { Link } from 'react-router-dom'
import { MapPin, Package, User, Clock } from 'lucide-react'
import type { DeliveryRow, RiderRow } from '@/types/delivery'
import type { DeliveryStatus } from '@/types/supabase'
import { Sheet } from '@/components/ui/Sheet'
import { StatusBadge } from '@/components/ui/StatusBadge'
import { Button } from '@/components/ui/Button'
import { formatLrdFromCents, NEXT_STATUS, statusLabel } from '@/utils/delivery-schemas'
import { DeliveryPhotoButton } from '@/components/DeliveryPhotoButton'

type DeliveryDetailDrawerProps = {
  open: boolean
  onClose: () => void
  delivery: DeliveryRow | null
  companyId: string
  rider?: RiderRow
  canWrite: boolean
  canPhoto: boolean
  onTransition: (id: string, status: DeliveryStatus) => void
}

export function DeliveryDetailDrawer({
  open,
  onClose,
  delivery: d,
  companyId,
  rider,
  canWrite,
  canPhoto,
  onTransition,
}: DeliveryDetailDrawerProps) {
  if (!d) return null

  const next = NEXT_STATUS[d.status as keyof typeof NEXT_STATUS] ?? []

  return (
    <Sheet
      open={open}
      onClose={onClose}
      title={d.customer_name}
      description={`Tracking ${d.tracking_code}`}
    >
      <div className="space-y-6">
        <div className="flex flex-wrap items-center gap-2">
          <StatusBadge status={d.status} />
          <Link
            to={`/track/${d.tracking_code}`}
            target="_blank"
            className="text-sm font-medium text-[var(--color-primary)] underline"
          >
            Public tracking
          </Link>
        </div>

        <section className="rounded-lg border bg-zinc-50/50 p-4">
          <h3 className="flex items-center gap-2 text-sm font-semibold">
            <Clock className="h-4 w-4" aria-hidden />
            Timeline
          </h3>
          <ol className="mt-3 space-y-2 border-l-2 border-zinc-200 pl-4 text-sm">
            <li>
              <span className="font-medium capitalize">{statusLabel(d.status)}</span>
              <span className="ml-2 text-xs text-[var(--color-muted)]">Current</span>
            </li>
          </ol>
        </section>

        <section>
          <h3 className="flex items-center gap-2 text-sm font-semibold">
            <User className="h-4 w-4" aria-hidden />
            Customer
          </h3>
          <p className="mt-1 text-sm">{d.customer_name}</p>
          <p className="text-sm text-[var(--color-muted)]">{d.customer_phone}</p>
        </section>

        <section>
          <h3 className="flex items-center gap-2 text-sm font-semibold">
            <Package className="h-4 w-4" aria-hidden />
            Package &amp; payments
          </h3>
          <p className="mt-1 text-sm">{d.package_description || '—'}</p>
          <p className="mt-2 text-sm">
            COD <strong>{formatLrdFromCents(d.amount_to_collect_lrd_cents)}</strong>
            {' · '}
            Fee {formatLrdFromCents(d.delivery_fee_lrd_cents)}
          </p>
        </section>

        <section>
          <h3 className="flex items-center gap-2 text-sm font-semibold">
            <MapPin className="h-4 w-4" aria-hidden />
            Route
          </h3>
          <p className="mt-1 text-sm font-medium">{d.pickup_business_name}</p>
          <p className="text-xs text-[var(--color-muted)]">{d.pickup_address}</p>
          <p className="mt-2 text-sm">{d.destination_address}</p>
          <div className="mt-3 flex h-32 items-center justify-center rounded-lg border border-dashed bg-zinc-50 text-xs text-[var(--color-muted)]">
            Map preview — open Live map for fleet view
          </div>
        </section>

        {rider && (
          <section>
            <h3 className="text-sm font-semibold">Rider</h3>
            <p className="text-sm">
              {rider.rider_code} · {rider.full_name}
            </p>
            <p className="text-xs text-[var(--color-muted)]">{rider.phone}</p>
          </section>
        )}

        {d.status !== 'pending' && (
          <p className="text-xs text-[var(--color-muted)]">
            Job SMS: {d.rider_job_sms_status ?? '—'}
          </p>
        )}

        {canWrite && next.length > 0 && (
          <div className="flex flex-wrap gap-2 border-t pt-4">
            {next.map((s) => (
              <Button
                key={s}
                type="button"
                size="sm"
                variant={s === 'failed' || s === 'cancelled' ? 'destructive' : 'outline'}
                onClick={() => onTransition(d.id, s)}
              >
                Mark {statusLabel(s)}
              </Button>
            ))}
          </div>
        )}

        {canPhoto && ['picked_up', 'in_transit', 'delivered'].includes(d.status) && (
          <DeliveryPhotoButton companyId={companyId} deliveryId={d.id} />
        )}

        <div className="rounded-lg border border-dashed bg-amber-50/50 p-3 text-xs text-amber-950">
          MTN Mobile Money collection — <strong>Coming soon</strong> (placeholder; no API integration).
        </div>
      </div>
    </Sheet>
  )
}
