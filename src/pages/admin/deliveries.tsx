import { useMemo, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import {
  CommandButton,
  CommandCard,
  CommandCardBody,
  CommandDrawer,
  CommandEmptyState,
  CommandInput,
  CommandPagination,
  CommandTable,
  CommandTableHead,
  CommandTd,
  CommandTh,
  CommandTr,
  MetricList,
  MetricRow,
  SectionHeader,
  StatusChip,
} from '@/components/admin/control-tower'
import { formatLrd, statusColorFor } from '@/lib/admin-control-tower'
import { useAdminDeliveriesPage, useAdminDeliveryDetail } from '@/hooks/use-admin-platform'

const PAGE = 25

export function AdminDeliveriesPage() {
  const [params, setParams] = useSearchParams()
  const code = params.get('code') ?? ''
  const [tracking, setTracking] = useState(code)
  const [page, setPage] = useState(1)
  const [selectedId, setSelectedId] = useState<string | null>(null)

  const query = useMemo(
    () => ({ trackingCode: tracking || undefined, limit: PAGE, offset: (page - 1) * PAGE }),
    [tracking, page],
  )
  const { data, isLoading } = useAdminDeliveriesPage(query, true)
  const rows = data?.rows ?? []
  const total = data?.total ?? 0

  return (
    <div className="space-y-4">
      <SectionHeader eyebrow="Deliveries" title="Platform deliveries" className="mb-0" />

      <CommandCard>
        <CommandCardBody className="flex flex-wrap gap-2 border-b border-white/[0.06] pb-4">
          <CommandInput
            className="max-w-xs"
            placeholder="Tracking code"
            value={tracking}
            onChange={(e) => setTracking(e.target.value)}
          />
          <CommandButton
            size="default"
            variant="primary"
            onClick={() => {
              setPage(1)
              if (tracking) setParams({ code: tracking })
            }}
          >
            Search
          </CommandButton>
        </CommandCardBody>
        {isLoading ? (
          <p className="p-4 text-sm text-zinc-500">Loading…</p>
        ) : rows.length === 0 ? (
          <CommandEmptyState label="No deliveries match this search." />
        ) : (
          <CommandTable>
            <CommandTableHead>
              <CommandTh>Tracking</CommandTh>
              <CommandTh>Company</CommandTh>
              <CommandTh>Status</CommandTh>
              <CommandTh>Customer</CommandTh>
              <CommandTh className="text-right">Created</CommandTh>
            </CommandTableHead>
            <tbody>
              {rows.map((r) => (
                <CommandTr key={String(r.id)} onClick={() => setSelectedId(String(r.id))}>
                  <CommandTd className="font-mono text-xs text-zinc-300">{String(r.tracking_code)}</CommandTd>
                  <CommandTd>{String(r.company_name)}</CommandTd>
                  <CommandTd>
                    <StatusChip color={statusColorFor(String(r.status))} label={String(r.status)} />
                  </CommandTd>
                  <CommandTd>{String(r.customer_name)}</CommandTd>
                  <CommandTd className="text-right text-xs text-zinc-500">
                    {new Date(String(r.created_at)).toLocaleString()}
                  </CommandTd>
                </CommandTr>
              ))}
            </tbody>
          </CommandTable>
        )}
        <div className="px-4 pb-4">
          <CommandPagination total={total} page={page} pageSize={PAGE} onPage={setPage} loading={isLoading} />
        </div>
      </CommandCard>

      <DeliveryDetailDrawer id={selectedId} onClose={() => setSelectedId(null)} />
    </div>
  )
}

function DeliveryDetailDrawer({ id, onClose }: { id: string | null; onClose: () => void }) {
  const detail = useAdminDeliveryDetail(id ?? undefined, !!id)
  const data = detail.data as Record<string, unknown> | undefined
  const delivery = data?.delivery as Record<string, unknown> | undefined
  const company = data?.company as Record<string, unknown> | undefined
  const rider = data?.rider as Record<string, unknown> | undefined
  const payment = data?.payment as Record<string, unknown> | undefined
  const timeline = (data?.timeline ?? []) as Array<{ from_status: string | null; to_status: string; created_at: string; note: string | null }>
  const smsEvents = (data?.sms_events ?? []) as Array<{ direction: string; phone: string; credits_used: number; created_at: string }>
  const webhookEvents = (data?.webhook_events ?? []) as Array<{
    event_type: string
    status: string
    attempt_count: number
    last_error: string | null
    created_at: string
  }>

  return (
    <CommandDrawer
      open={!!id}
      onClose={onClose}
      title={delivery ? `Delivery ${String(delivery.tracking_code)}` : 'Delivery inspection'}
      description={company ? String(company.name) : undefined}
    >
      {detail.isLoading && <p className="text-sm text-zinc-500">Loading detail…</p>}
      {delivery && (
        <div className="space-y-5">
          <div className="flex items-center gap-2">
            <StatusChip color={statusColorFor(String(delivery.status))} label={String(delivery.status)} />
            {company && (
              <Link to={`/admin/companies/${company.id}`} className="text-xs text-zinc-400 hover:text-white hover:underline">
                {String(company.name)} →
              </Link>
            )}
          </div>

          <MetricList>
            <MetricRow label="Pickup" value={String(delivery.pickup_business_name)} />
            <MetricRow label="Destination" value={String(delivery.destination_address)} />
            <MetricRow label="Customer" value={String(delivery.customer_name)} hint={String(delivery.customer_phone_masked ?? '')} />
            <MetricRow label="Rider" value={rider ? String(rider.full_name) : 'Unassigned'} />
            <MetricRow label="Fee" value={formatLrd(Number(delivery.delivery_fee_lrd_cents ?? 0))} />
            <MetricRow label="To collect" value={formatLrd(Number(delivery.amount_to_collect_lrd_cents ?? 0))} />
            {payment && <MetricRow label="Payment status" value={String(payment.status ?? '—')} />}
          </MetricList>

          <section>
            <p className="mb-2 text-xs font-medium uppercase tracking-wide text-zinc-500">Status timeline</p>
            {timeline.length === 0 ? (
              <p className="text-sm text-zinc-600">No status changes recorded.</p>
            ) : (
              <ul className="space-y-2">
                {timeline.map((t, i) => (
                  <li key={i} className="flex items-start justify-between gap-3 text-xs">
                    <span className="text-zinc-300">
                      {t.from_status ? `${t.from_status} → ` : ''}
                      {t.to_status}
                    </span>
                    <span className="shrink-0 text-zinc-600">{new Date(t.created_at).toLocaleString()}</span>
                  </li>
                ))}
              </ul>
            )}
          </section>

          <section>
            <p className="mb-2 text-xs font-medium uppercase tracking-wide text-zinc-500">SMS events</p>
            {smsEvents.length === 0 ? (
              <p className="text-sm text-zinc-600">No SMS events for this delivery.</p>
            ) : (
              <ul className="space-y-1.5">
                {smsEvents.map((s, i) => (
                  <li key={i} className="flex items-center justify-between text-xs text-zinc-400">
                    <span className="capitalize">{s.direction}</span>
                    <span>{s.credits_used} credit{s.credits_used === 1 ? '' : 's'}</span>
                    <span className="text-zinc-600">{new Date(s.created_at).toLocaleTimeString()}</span>
                  </li>
                ))}
              </ul>
            )}
          </section>

          <section>
            <p className="mb-2 text-xs font-medium uppercase tracking-wide text-zinc-500">Webhook events</p>
            {webhookEvents.length === 0 ? (
              <p className="text-sm text-zinc-600">No webhook events for this delivery.</p>
            ) : (
              <ul className="space-y-1.5">
                {webhookEvents.map((w, i) => (
                  <li key={i} className="text-xs">
                    <div className="flex items-center justify-between">
                      <span className="text-zinc-300">{w.event_type}</span>
                      <StatusChip color={statusColorFor(w.status)} label={w.status} />
                    </div>
                    {w.last_error && <p className="mt-0.5 text-red-400/80">{w.last_error}</p>}
                  </li>
                ))}
              </ul>
            )}
          </section>
        </div>
      )}
    </CommandDrawer>
  )
}
