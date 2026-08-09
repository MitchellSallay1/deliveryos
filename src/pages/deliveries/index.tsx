import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { PageHeader } from '@/components/ui/PageHeader'
import { Tabs } from '@/components/ui/Tabs'
import { StatusBadge } from '@/components/ui/StatusBadge'
import { DeliveryKanbanBoard } from '@/components/deliveries/DeliveryKanbanBoard'
import { DeliveryDetailDrawer } from '@/components/deliveries/DeliveryDetailDrawer'
import { KpiSkeletonGrid } from '@/components/ui/Skeleton'
import { useAccess } from '@/hooks/use-access'
import { useAuth } from '@/hooks/use-auth'
import {
  useAssignRider,
  useCreateDelivery,
  useCustomers,
  useDeliveries,
  useResendRiderJobSms,
  useRiders,
  useTransitionDelivery,
} from '@/hooks/use-deliveries'
import type { DeliveryRow, RiderRow } from '@/types/delivery'
import type { DeliveryStatus } from '@/types/supabase'
import { DeliveryPhotoButton } from '@/components/DeliveryPhotoButton'
import { parseSupabaseError } from '@/lib/supabase-errors'
import {
  createDeliverySchema,
  formatLrdFromCents,
  NEXT_STATUS,
  statusLabel,
} from '@/utils/delivery-schemas'
import { isButtonPhoneCapable } from '@/utils/rider-schemas'

export function DeliveriesPage() {
  const { context } = useAuth()
  const { can } = useAccess()
  const companyId = context?.activeCompanyId ?? null
  const companyStatus = context?.memberships.find((m) => m.company_id === companyId)?.company
    .status

  const [page, setPage] = useState(1)
  const [search, setSearch] = useState('')
  const [searchDraft, setSearchDraft] = useState('')
  const [view, setView] = useState<'board' | 'table'>('board')
  const [selectedId, setSelectedId] = useState<string | null>(null)

  const pageSize = view === 'board' ? 100 : 25
  const { data, isLoading, error } = useDeliveries(companyId, { page, pageSize, search })
  const deliveries = data?.rows ?? []
  const total = data?.total ?? 0
  const totalPages = Math.max(1, Math.ceil(total / (data?.pageSize ?? 25)))

  const { data: riders = [] } = useRiders(companyId)
  const { data: customers = [] } = useCustomers(companyId)

  const createMutation = useCreateDelivery(companyId)
  const assignMutation = useAssignRider(companyId)
  const resendSmsMutation = useResendRiderJobSms(companyId)
  const transitionMutation = useTransitionDelivery(companyId)

  const [formError, setFormError] = useState<string | null>(null)
  const [formNotice, setFormNotice] = useState<string | null>(null)
  const [assignDraft, setAssignDraft] = useState<Record<string, string>>({})

  const canWrite = can('page:deliveries:write')

  const riderMap = useMemo(() => {
    const m = new Map<string, RiderRow>()
    for (const r of riders) m.set(r.id, r)
    return m
  }, [riders])

  const selectedDelivery = deliveries.find((d) => d.id === selectedId) ?? null

  async function onCreate(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const form = e.currentTarget
    setFormError(null)
    if (!canWrite) return
    const fd = new FormData(form)
    const customerId = String(fd.get('customerId') || '')
    const selected = customers.find((c) => c.id === customerId)

    const parsed = createDeliverySchema.safeParse({
      pickupBusinessName: fd.get('pickupBusinessName'),
      pickupAddress: fd.get('pickupAddress'),
      customerName: selected?.full_name ?? fd.get('customerName'),
      customerPhone: selected?.phone ?? fd.get('customerPhone'),
      destinationAddress: fd.get('destinationAddress') || selected?.address,
      packageDescription: fd.get('packageDescription') || undefined,
      amountToCollectLrd: fd.get('amountToCollectLrd'),
      deliveryFeeLrd: fd.get('deliveryFeeLrd'),
      customerId: customerId || undefined,
    })

    if (!parsed.success) {
      setFormError(parsed.error.issues[0]?.message ?? 'Invalid form')
      return
    }

    try {
      await createMutation.mutateAsync(parsed.data)
      form.reset()
      setPage(1)
    } catch (err) {
      setFormError(parseSupabaseError(err))
    }
  }

  async function onAssign(deliveryId: string) {
    if (!canWrite) return
    const riderId = assignDraft[deliveryId]
    if (!riderId) {
      setFormError('Select a rider to assign')
      return
    }
    setFormError(null)
    setFormNotice(null)
    try {
      const row = await assignMutation.mutateAsync({ deliveryId, riderId })
      const rider = riderMap.get(riderId)
      if (rider && isButtonPhoneCapable(rider.access_mode ?? 'smartphone')) {
        const sms = (row as DeliveryRow).rider_job_sms_status
        if (sms === 'failed') {
          setFormNotice('Rider assigned, but job SMS failed to queue. Use Resend SMS on the delivery row.')
        } else if (sms === 'sent') {
          setFormNotice('Rider assigned. They will receive this job by SMS.')
        }
      }
    } catch (err) {
      setFormError(parseSupabaseError(err))
    }
  }

  async function onTransition(deliveryId: string, status: DeliveryStatus) {
    if (!canWrite) return
    setFormError(null)
    try {
      await transitionMutation.mutateAsync({ deliveryId, status })
    } catch (err) {
      setFormError(parseSupabaseError(err))
    }
  }

  if (!companyId) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>No workspace</CardTitle>
          <CardDescription>Join or register a company to manage deliveries.</CardDescription>
        </CardHeader>
      </Card>
    )
  }

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader
        title="Live operations"
        description="Kanban board with realtime updates · assign and transition using existing dispatch rules."
      />

      {companyStatus !== 'active' && (
        <div className="rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
          Company status is <strong>{companyStatus}</strong>. Dispatch actions are blocked in the
          database until the workspace is active.
        </div>
      )}

      {canWrite && (
      <Card>
        <CardHeader>
          <CardTitle>New delivery</CardTitle>
          <CardDescription>
            Created via <code className="text-xs">create_delivery</code> RPC — tracking code and
            history are server-side.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form className="grid gap-4 md:grid-cols-2" onSubmit={onCreate}>
            {formError && <p className="text-sm text-red-600 md:col-span-2">{formError}</p>}
            <Field label="Pickup business" name="pickupBusinessName" required />
            <Field label="Pickup address" name="pickupAddress" required />
            <div className="space-y-2">
              <Label htmlFor="customerId">Saved customer</Label>
              <select
                id="customerId"
                name="customerId"
                className="flex h-10 w-full rounded-lg border bg-white px-3 text-sm"
                defaultValue=""
              >
                <option value="">Manual entry</option>
                {customers.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.full_name} ({c.phone})
                  </option>
                ))}
              </select>
            </div>
            <Field label="Customer name" name="customerName" />
            <Field label="Customer phone" name="customerPhone" />
            <Field label="Destination" name="destinationAddress" required className="md:col-span-2" />
            <Field label="Package" name="packageDescription" className="md:col-span-2" />
            <Field label="COD (LRD)" name="amountToCollectLrd" type="number" defaultValue="0" />
            <Field label="Delivery fee (LRD)" name="deliveryFeeLrd" type="number" defaultValue="500" />
            <div className="md:col-span-2">
              <Button type="submit" disabled={createMutation.isPending}>
                {createMutation.isPending ? 'Creating…' : 'Create delivery'}
              </Button>
            </div>
          </form>
        </CardContent>
      </Card>
      )}

      <Card>
        <CardHeader className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <CardTitle>Operations board</CardTitle>
            <CardDescription>
              Realtime via Supabase · {total} deliveries
            </CardDescription>
          </div>
          <Tabs
            value={view}
            onValueChange={(v) => {
              setView(v as 'board' | 'table')
              setPage(1)
            }}
            items={[
              { value: 'board', label: 'Kanban' },
              { value: 'table', label: 'Table' },
            ]}
          />
        </CardHeader>
        <CardContent className="overflow-x-auto">
          <form
            className="mb-4 flex flex-wrap gap-2"
            onSubmit={(e) => {
              e.preventDefault()
              setSearch(searchDraft)
              setPage(1)
            }}
          >
            <Input
              placeholder="Search tracking, customer…"
              value={searchDraft}
              onChange={(e) => setSearchDraft(e.target.value)}
              className="max-w-xs"
            />
            <Button type="submit" variant="outline" size="sm">
              Search
            </Button>
          </form>
          {formError && <p className="mb-2 text-sm text-red-600">{formError}</p>}
          {formNotice && <p className="mb-2 text-sm text-emerald-800">{formNotice}</p>}
          {isLoading && view === 'board' && <KpiSkeletonGrid count={3} />}
          {isLoading && view === 'table' && (
            <p className="text-sm text-[var(--color-muted)]">Loading…</p>
          )}
          {error && (
            <p className="text-sm text-red-600">{parseSupabaseError(error)}</p>
          )}
          {view === 'board' && !isLoading && (
            <DeliveryKanbanBoard
              deliveries={deliveries}
              riderMap={riderMap}
              onSelect={(d) => setSelectedId(d.id)}
              onMove={(id, status) => void onTransition(id, status)}
            />
          )}
          {view === 'table' && (
          <table className="w-full min-w-[720px] text-left text-sm">
            <thead className="sticky top-0 z-10 bg-white">
              <tr className="border-b text-xs uppercase tracking-wide text-[var(--color-muted)]">
                <th className="py-2 pr-2">Customer</th>
                <th className="py-2 pr-2">Route</th>
                <th className="py-2 pr-2">Money</th>
                <th className="py-2 pr-2">Status</th>
                <th className="py-2">Actions</th>
              </tr>
            </thead>
            <tbody>
              {deliveries.map((d) => (
                <DeliveryRowItem
                  key={d.id}
                  companyId={companyId!}
                  delivery={d}
                  canWrite={canWrite}
                  canPhoto={can('action:photo:upload')}
                  riderLabel={
                    d.rider_id ? riderMap.get(d.rider_id)?.rider_code ?? '—' : '—'
                  }
                  assignDraft={assignDraft[d.id] ?? ''}
                  onAssignDraftChange={(v) =>
                    setAssignDraft((prev) => ({ ...prev, [d.id]: v }))
                  }
                  riders={riders}
                  riderMap={riderMap}
                  onAssign={() => onAssign(d.id)}
                  onResendSms={(id) => {
                    setFormError(null)
                    void resendSmsMutation
                      .mutateAsync(id)
                      .then((ok) =>
                        setFormNotice(ok ? 'Job SMS queued again.' : 'Could not queue SMS (credits or plan).'),
                      )
                      .catch((err) => setFormError(parseSupabaseError(err)))
                  }}
                  onTransition={onTransition}
                  onOpenDetail={() => setSelectedId(d.id)}
                />
              ))}
              {!isLoading && deliveries.length === 0 && (
                <tr>
                  <td colSpan={5} className="py-6 text-center text-[var(--color-muted)]">
                    No deliveries yet.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
          )}
          {view === 'table' && (
          <div className="mt-4 flex items-center justify-between text-sm">
            <span className="text-[var(--color-muted)]">
              Page {page} of {totalPages}
            </span>
            <div className="flex gap-2">
              <Button
                type="button"
                size="sm"
                variant="outline"
                disabled={page <= 1}
                onClick={() => setPage((p) => p - 1)}
              >
                Previous
              </Button>
              <Button
                type="button"
                size="sm"
                variant="outline"
                disabled={page >= totalPages}
                onClick={() => setPage((p) => p + 1)}
              >
                Next
              </Button>
            </div>
          </div>
          )}
        </CardContent>
      </Card>

      <DeliveryDetailDrawer
        open={selectedId != null}
        onClose={() => setSelectedId(null)}
        delivery={selectedDelivery}
        companyId={companyId!}
        rider={selectedDelivery?.rider_id ? riderMap.get(selectedDelivery.rider_id) : undefined}
        canWrite={canWrite}
        canPhoto={can('action:photo:upload')}
        onTransition={onTransition}
      />
    </div>
  )
}

function Field({
  label,
  name,
  className,
  ...props
}: {
  label: string
  name: string
  className?: string
} & React.ComponentProps<'input'>) {
  return (
    <div className={`space-y-2 ${className ?? ''}`}>
      <Label htmlFor={name}>{label}</Label>
      <Input id={name} name={name} {...props} />
    </div>
  )
}

function DeliveryRowItem({
  companyId,
  delivery: d,
  canWrite,
  canPhoto,
  riderLabel,
  assignDraft,
  onAssignDraftChange,
  riders,
  riderMap,
  onAssign,
  onResendSms,
  onTransition,
  onOpenDetail,
}: {
  companyId: string
  delivery: DeliveryRow
  canWrite: boolean
  canPhoto: boolean
  riderLabel: string
  assignDraft: string
  onAssignDraftChange: (v: string) => void
  riders: RiderRow[]
  riderMap: Map<string, RiderRow>
  onAssign: () => void
  onResendSms: (deliveryId: string) => void
  onTransition: (id: string, status: DeliveryStatus) => void
  onOpenDetail?: () => void
}) {
  const next = NEXT_STATUS[d.status as keyof typeof NEXT_STATUS] ?? []
  const draftRider = assignDraft ? riderMap.get(assignDraft) : undefined
  const assignedRider = d.rider_id ? riderMap.get(d.rider_id) : undefined
  const buttonRider =
    draftRider && isButtonPhoneCapable(draftRider.access_mode ?? 'smartphone')
      ? draftRider
      : assignedRider && isButtonPhoneCapable(assignedRider.access_mode ?? 'smartphone')
        ? assignedRider
        : null

  return (
    <tr className="border-b align-top transition-colors hover:bg-zinc-50/80">
      <td className="py-3 pr-2">
        <button type="button" className="text-left" onClick={onOpenDetail}>
          <div className="font-medium">{d.customer_name}</div>
          <div className="text-xs text-[var(--color-muted)]">{d.customer_phone}</div>
        </button>
        <Link
          to={`/track/${d.tracking_code}`}
          className="text-xs text-[var(--color-primary)] hover:underline"
          target="_blank"
        >
          {d.tracking_code}
        </Link>
      </td>
      <td className="py-3 pr-2">
        <div>{d.pickup_business_name}</div>
        <div className="text-xs text-[var(--color-muted)]">{d.pickup_address}</div>
        <div className="text-xs">→ {d.destination_address}</div>
      </td>
      <td className="py-3 pr-2 text-xs">
        <div>COD {formatLrdFromCents(d.amount_to_collect_lrd_cents)}</div>
        <div className="text-[var(--color-muted)]">
          Fee {formatLrdFromCents(d.delivery_fee_lrd_cents)}
        </div>
      </td>
      <td className="py-3 pr-2">
        <StatusBadge status={d.status} />
        <div className="mt-1 text-xs text-[var(--color-muted)]">Rider {riderLabel}</div>
        {buttonRider && d.status !== 'pending' && (
          <div className="mt-1 text-xs text-teal-800">
            SMS job notify: {d.rider_job_sms_status ?? '—'}
            {d.rider_job_sms_status === 'failed' && canWrite && (
              <Button
                type="button"
                size="sm"
                variant="outline"
                className="ml-2 h-6 px-2"
                onClick={() => onResendSms(d.id)}
              >
                Resend SMS
              </Button>
            )}
          </div>
        )}
      </td>
      <td className="py-3">
        {canWrite && d.status === 'pending' && (
          <div className="flex flex-wrap items-center gap-1">
            <select
              className="h-8 rounded-md border px-2 text-xs"
              value={assignDraft}
              onChange={(e) => onAssignDraftChange(e.target.value)}
            >
              <option value="">Rider…</option>
              {riders
                .filter((r) => r.status !== 'suspended')
                .map((r) => (
                  <option key={r.id} value={r.id}>
                    {r.rider_code} · {r.full_name}
                  </option>
                ))}
            </select>
            <Button type="button" size="sm" onClick={onAssign}>
              Assign
            </Button>
            {draftRider && isButtonPhoneCapable(draftRider.access_mode ?? 'smartphone') && (
              <span className="text-xs text-teal-800">Rider will receive this job by SMS.</span>
            )}
          </div>
        )}
        {canWrite && (
        <div className="mt-1 flex flex-wrap gap-1">
          {next.map((s) => (
            <Button
              key={s}
              type="button"
              size="sm"
              variant={s === 'failed' || s === 'cancelled' ? 'destructive' : 'outline'}
              onClick={() => onTransition(d.id, s)}
            >
              {statusLabel(s)}
            </Button>
          ))}
        </div>
        )}
        {canPhoto && ['picked_up', 'in_transit', 'delivered'].includes(d.status) && (
          <DeliveryPhotoButton companyId={companyId} deliveryId={d.id} />
        )}
      </td>
    </tr>
  )
}
