import { useState } from 'react'
import {
  CommandCard,
  CommandCardBody,
  CommandCardHeader,
  CommandEmptyState,
  CommandInput,
  CommandKpi,
  CommandPagination,
  CommandSelect,
  CommandTable,
  CommandTableHead,
  CommandTd,
  CommandTh,
  CommandTr,
  SectionHeader,
  StatusChip,
} from '@/components/admin/control-tower'
import {
  useCommerceOrdersPage,
  useCommerceOrdersSummary,
  useCommerceProvidersPage,
  useCommerceReconciliationGaps,
} from '@/hooks/use-commerce-admin'
import { formatLrdFromCents } from '@/utils/delivery-schemas'
import type { StatusColor } from '@/lib/admin-control-tower'

const PAGE = 25

const FULFILLMENT_STATUSES = [
  'awaiting_vendor',
  'vendor_accepted',
  'vendor_rejected',
  'preparing',
  'ready_for_pickup',
  'handed_to_carrier',
  'completed',
  'cancelled',
]

function fulfillmentColor(status: string): StatusColor {
  if (status === 'completed') return 'green'
  if (status === 'vendor_rejected' || status === 'cancelled') return 'red'
  if (status === 'awaiting_vendor') return 'amber'
  return 'gray'
}

function OrdersSection() {
  const [status, setStatus] = useState('')
  const [stuckOnly, setStuckOnly] = useState(false)
  const [search, setSearch] = useState('')
  const [page, setPage] = useState(1)
  const { data: summary, isLoading: summaryLoading } = useCommerceOrdersSummary(24)
  const { data: orders, isLoading: ordersLoading } = useCommerceOrdersPage({
    fulfillmentStatuses: status ? [status] : undefined,
    stuckOnly,
    stuckAfterHours: 24,
    search: search || undefined,
    page,
    pageSize: PAGE,
  })

  const activeCount = summary
    ? FULFILLMENT_STATUSES.filter((s) => !['completed', 'cancelled', 'vendor_rejected'].includes(s)).reduce(
        (sum, s) => sum + (summary.by_status[s] ?? 0),
        0,
      )
    : 0

  return (
    <>
      <div className="grid gap-3 sm:grid-cols-3">
        <CommandKpi label="Active orders" value={String(activeCount)} loading={summaryLoading} />
        <CommandKpi
          label="Stuck (24h+, no progress)"
          value={String(summary?.stuck_count ?? 0)}
          loading={summaryLoading}
          color={summary && summary.stuck_count > 0 ? 'amber' : 'gray'}
        />
        <CommandKpi label="Completed" value={String(summary?.by_status.completed ?? 0)} loading={summaryLoading} color="green" />
      </div>

      <CommandCard>
        <CommandCardHeader
          title="Commerce orders"
          description="Every real order, its fulfillment status, and how long it has sat since its last update."
        />
        <CommandCardBody className="flex flex-wrap gap-2 border-b border-white/[0.06] pb-4">
          <CommandInput
            className="max-w-xs"
            placeholder="Order #, vendor, or customer"
            value={search}
            onChange={(e) => {
              setSearch(e.target.value)
              setPage(1)
            }}
          />
          <CommandSelect
            className="max-w-[220px]"
            value={status}
            onChange={(e) => {
              setStatus(e.target.value)
              setPage(1)
            }}
          >
            <option value="">All statuses</option>
            {FULFILLMENT_STATUSES.map((s) => (
              <option key={s} value={s}>
                {s.replace(/_/g, ' ')}
              </option>
            ))}
          </CommandSelect>
          <label className="flex items-center gap-2 text-sm text-zinc-400">
            <input
              type="checkbox"
              checked={stuckOnly}
              onChange={(e) => {
                setStuckOnly(e.target.checked)
                setPage(1)
              }}
            />
            Stuck only (24h+)
          </label>
        </CommandCardBody>
        {ordersLoading ? (
          <p className="p-4 text-sm text-zinc-500">Loading…</p>
        ) : (orders?.rows ?? []).length === 0 ? (
          <CommandEmptyState label="No orders match this filter." />
        ) : (
          <CommandTable>
            <CommandTableHead>
              <CommandTh>Order</CommandTh>
              <CommandTh>Vendor</CommandTh>
              <CommandTh>Status</CommandTh>
              <CommandTh>Carrier</CommandTh>
              <CommandTh>Total</CommandTh>
              <CommandTh className="text-right">Last update</CommandTh>
            </CommandTableHead>
            <tbody>
              {(orders?.rows ?? []).map((o) => (
                <CommandTr key={o.id}>
                  <CommandTd className="font-medium text-zinc-100">{o.order_number}</CommandTd>
                  <CommandTd>{o.vendor_name}</CommandTd>
                  <CommandTd>
                    <StatusChip color={fulfillmentColor(o.fulfillment_status)} label={o.fulfillment_status.replace(/_/g, ' ')} />
                  </CommandTd>
                  <CommandTd className="text-zinc-400">{o.carrier_name ?? '—'}</CommandTd>
                  <CommandTd className="tabular-nums">{formatLrdFromCents(o.total_lrd_cents)}</CommandTd>
                  <CommandTd className="text-right text-xs text-zinc-500">
                    {o.is_stuck ? (
                      <span className="text-amber-400">{o.hours_since_update}h — stuck</span>
                    ) : (
                      `${o.hours_since_update}h ago`
                    )}
                  </CommandTd>
                </CommandTr>
              ))}
            </tbody>
          </CommandTable>
        )}
        <div className="px-4 pb-4">
          <CommandPagination total={orders?.total ?? 0} page={page} pageSize={PAGE} onPage={setPage} loading={ordersLoading} />
        </div>
      </CommandCard>
    </>
  )
}

function ProvidersSection() {
  const [search, setSearch] = useState('')
  const [page, setPage] = useState(1)
  const { data, isLoading } = useCommerceProvidersPage({ search: search || undefined, page, pageSize: PAGE })

  return (
    <CommandCard>
      <CommandCardHeader
        title="Carrier delivery-pricing readiness"
        description="A carrier only receives Commerce delivery offers once they have explicitly saved pricing — never configured never means free, and the reverse is also true (an intentional 0 is honored)."
      />
      <CommandCardBody className="border-b border-white/[0.06] pb-4">
        <CommandInput
          className="max-w-xs"
          placeholder="Search carriers"
          value={search}
          onChange={(e) => {
            setSearch(e.target.value)
            setPage(1)
          }}
        />
      </CommandCardBody>
      {isLoading ? (
        <p className="p-4 text-sm text-zinc-500">Loading…</p>
      ) : (data?.rows ?? []).length === 0 ? (
        <CommandEmptyState label="No carriers found." />
      ) : (
        <CommandTable>
          <CommandTableHead>
            <CommandTh>Carrier</CommandTh>
            <CommandTh>Pricing</CommandTh>
            <CommandTh>Marketplace</CommandTh>
            <CommandTh>Riders</CommandTh>
            <CommandTh className="text-right">Configured</CommandTh>
          </CommandTableHead>
          <tbody>
            {(data?.rows ?? []).map((p) => (
              <CommandTr key={p.company_id}>
                <CommandTd className="font-medium text-zinc-100">{p.company_name}</CommandTd>
                <CommandTd>
                  {p.delivery_pricing_configured_at ? (
                    <span className="tabular-nums text-zinc-300">{formatLrdFromCents(p.minimum_delivery_fee_lrd_cents)}</span>
                  ) : (
                    <StatusChip color="amber" label="Never configured — 0 Commerce offers" />
                  )}
                </CommandTd>
                <CommandTd>
                  <StatusChip
                    color={p.marketplace_enabled && p.accepting_jobs && !p.admin_marketplace_disabled ? 'green' : 'gray'}
                    label={p.admin_marketplace_disabled ? 'admin disabled' : p.marketplace_enabled && p.accepting_jobs ? 'active' : 'inactive'}
                  />
                </CommandTd>
                <CommandTd className="text-zinc-400">
                  {p.available_riders}/{p.total_riders} available
                </CommandTd>
                <CommandTd className="text-right text-xs text-zinc-500">
                  {p.delivery_pricing_configured_at ? new Date(p.delivery_pricing_configured_at).toLocaleDateString() : '—'}
                </CommandTd>
              </CommandTr>
            ))}
          </tbody>
        </CommandTable>
      )}
      <div className="px-4 pb-4">
        <CommandPagination total={data?.total ?? 0} page={page} pageSize={PAGE} onPage={setPage} loading={isLoading} />
      </div>
    </CommandCard>
  )
}

function ReconciliationSection() {
  const { data, isLoading } = useCommerceReconciliationGaps()

  return (
    <CommandCard>
      <CommandCardHeader
        title="Reconciliation check"
        description="Orders marked paid with no corresponding financial-recognition event — should always be empty. A non-empty result means the recognition trigger failed to fire for that order and needs investigation."
      />
      {isLoading ? (
        <p className="p-4 text-sm text-zinc-500">Checking…</p>
      ) : (data?.rows ?? []).length === 0 ? (
        <CommandEmptyState label="No gaps found — every paid order has a matching financial event." />
      ) : (
        <CommandTable>
          <CommandTableHead>
            <CommandTh>Order</CommandTh>
            <CommandTh>Payment method</CommandTh>
            <CommandTh>Total</CommandTh>
            <CommandTh className="text-right">Last updated</CommandTh>
          </CommandTableHead>
          <tbody>
            {(data?.rows ?? []).map((r) => (
              <CommandTr key={r.id}>
                <CommandTd className="font-medium text-red-400">{r.order_number}</CommandTd>
                <CommandTd className="capitalize text-zinc-400">{r.payment_method.replace(/_/g, ' ')}</CommandTd>
                <CommandTd className="tabular-nums">{formatLrdFromCents(r.total_lrd_cents)}</CommandTd>
                <CommandTd className="text-right text-xs text-zinc-500">{new Date(r.updated_at).toLocaleString()}</CommandTd>
              </CommandTr>
            ))}
          </tbody>
        </CommandTable>
      )}
    </CommandCard>
  )
}

export function AdminCommerceOrdersPage() {
  return (
    <div className="space-y-4">
      <SectionHeader eyebrow="Commerce" title="Commerce operations" className="mb-0" />
      <OrdersSection />
      <ProvidersSection />
      <ReconciliationSection />
    </div>
  )
}
