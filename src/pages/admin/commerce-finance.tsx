import { useState } from 'react'
import {
  CommandButton,
  CommandCard,
  CommandCardBody,
  CommandCardHeader,
  CommandDrawer,
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
  useAdminCommerceFinanceOverview,
  useAdminCommerceFinancialEvents,
  useCommerceSettlementActions,
  useCommerceSettlements,
} from '@/hooks/use-commerce-finance'
import { parseSupabaseError } from '@/lib/supabase-errors'
import { formatLrdFromCents } from '@/utils/delivery-schemas'
import type { StatusColor } from '@/lib/admin-control-tower'
import type { CommerceSettlement, CommerceSettlementPayeeType, CommerceSettlementStatus } from '@/services/commerce-finance-service'

const PAGE = 25

function settlementColor(status: CommerceSettlementStatus): StatusColor {
  switch (status) {
    case 'settled':
      return 'green'
    case 'pending':
    case 'processing':
      return 'amber'
    case 'failed':
    case 'reversed':
      return 'red'
  }
}

function CreateSettlementForm() {
  const { create } = useCommerceSettlementActions()
  const [payeeType, setPayeeType] = useState<CommerceSettlementPayeeType>('vendor')
  const [payeeCompanyId, setPayeeCompanyId] = useState('')
  const [notes, setNotes] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    setMessage(null)
    try {
      const settlement = await create.mutateAsync({ payeeType, payeeCompanyId: payeeCompanyId.trim(), notes: notes.trim() || undefined })
      setMessage(`Settlement created: ${formatLrdFromCents(settlement.total_amount_lrd_cents)} claimed from unsettled payables.`)
      setPayeeCompanyId('')
      setNotes('')
    } catch (err) {
      setError(parseSupabaseError(err))
    }
  }

  return (
    <CommandCard>
      <CommandCardHeader
        title="Create a settlement"
        description="Claims every currently-unsettled payable for this company into one new settlement. This only records DeliveryOS's intent — no money moves automatically."
      />
      <CommandCardBody>
        <form className="grid gap-3 sm:grid-cols-[160px_1fr_auto]" onSubmit={(e) => void onSubmit(e)}>
          {error && <p className="text-sm text-red-400 sm:col-span-3">{error}</p>}
          {message && <p className="text-sm text-emerald-400 sm:col-span-3">{message}</p>}
          <CommandSelect value={payeeType} onChange={(e) => setPayeeType(e.target.value as CommerceSettlementPayeeType)}>
            <option value="vendor">Vendor</option>
            <option value="carrier">Carrier</option>
          </CommandSelect>
          <CommandInput
            placeholder="Company ID"
            value={payeeCompanyId}
            onChange={(e) => setPayeeCompanyId(e.target.value)}
            required
          />
          <CommandButton type="submit" variant="primary" disabled={create.isPending}>
            {create.isPending ? 'Creating…' : 'Create settlement'}
          </CommandButton>
          <CommandInput
            className="sm:col-span-3"
            placeholder="Notes (optional)"
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
          />
        </form>
      </CommandCardBody>
    </CommandCard>
  )
}

function SettlementDrawer({ settlement, onClose }: { settlement: CommerceSettlement | null; onClose: () => void }) {
  const { markProcessing, recordReference, markCompleted, markFailed, reverse } = useCommerceSettlementActions()
  const [reference, setReference] = useState('')
  const [reason, setReason] = useState('')
  const [error, setError] = useState<string | null>(null)

  async function run(action: () => Promise<unknown>) {
    setError(null)
    try {
      await action()
    } catch (err) {
      setError(parseSupabaseError(err))
    }
  }

  const pending = markProcessing.isPending || recordReference.isPending || markCompleted.isPending || markFailed.isPending || reverse.isPending

  return (
    <CommandDrawer
      open={settlement != null}
      onClose={onClose}
      title={settlement ? formatLrdFromCents(settlement.total_amount_lrd_cents) : 'Settlement'}
      description={settlement ? `${settlement.payee_type} · ${settlement.payee_company_name}` : undefined}
    >
      {settlement && (
        <div className="space-y-4">
          {error && <p className="text-sm text-red-400">{error}</p>}
          <div>
            <p className="text-xs font-medium uppercase tracking-wide text-zinc-500">Status</p>
            <div className="mt-1">
              <StatusChip color={settlementColor(settlement.status)} label={settlement.status} />
            </div>
          </div>
          {settlement.external_reference && (
            <p className="text-sm text-zinc-400">External reference: {settlement.external_reference}</p>
          )}
          {settlement.notes && <p className="text-sm text-zinc-400">Notes: {settlement.notes}</p>}
          {settlement.settled_at && (
            <p className="text-sm text-zinc-400">Settled: {new Date(settlement.settled_at).toLocaleString()}</p>
          )}
          {settlement.failed_at && (
            <p className="text-sm text-zinc-400">Failed: {new Date(settlement.failed_at).toLocaleString()}</p>
          )}
          {settlement.reversed_at && (
            <p className="text-sm text-zinc-400">Reversed: {new Date(settlement.reversed_at).toLocaleString()}</p>
          )}

          {(settlement.status === 'pending' || settlement.status === 'processing') && (
            <>
              <label className="block space-y-1.5">
                <span className="text-xs font-medium uppercase tracking-wide text-zinc-500">
                  Record external/manual reference
                </span>
                <p className="text-xs text-zinc-500">
                  Records that DeliveryOS staff manually sent this money (bank transfer, cash, manual mobile money send).
                  This does not move any money itself.
                </p>
                <CommandInput
                  placeholder="e.g. Bank transfer #1234, or manual MoMo send receipt"
                  value={reference}
                  onChange={(e) => setReference(e.target.value)}
                />
              </label>
              <div className="flex flex-wrap gap-2">
                {settlement.status === 'pending' && (
                  <CommandButton disabled={pending} onClick={() => void run(() => markProcessing.mutateAsync(settlement.id))}>
                    Mark processing
                  </CommandButton>
                )}
                <CommandButton
                  disabled={pending || !reference.trim()}
                  onClick={() => void run(() => recordReference.mutateAsync({ settlementId: settlement.id, externalReference: reference.trim() }))}
                >
                  Save reference
                </CommandButton>
                <CommandButton
                  variant="primary"
                  disabled={pending}
                  onClick={() => void run(() => markCompleted.mutateAsync(settlement.id))}
                >
                  Mark settled (external transfer confirmed)
                </CommandButton>
                <CommandButton
                  variant="destructive"
                  disabled={pending}
                  onClick={() => void run(() => markFailed.mutateAsync({ settlementId: settlement.id, reason: reason.trim() || undefined }))}
                >
                  Mark failed
                </CommandButton>
              </div>
            </>
          )}

          {settlement.status === 'settled' && (
            <>
              <p className="rounded-md bg-amber-50 px-3 py-2 text-xs text-amber-800">
                Reversing retracts DeliveryOS&apos;s record that this settlement was paid — use it when this
                settlement record was wrong or no money actually went out. It does not claw back funds that were
                genuinely sent; if money really did leave and needs to be recovered, handle that outside this
                system and only reverse here once you&apos;ve confirmed the payable should be re-settled.
              </p>
              <label className="block space-y-1.5">
                <span className="text-xs font-medium uppercase tracking-wide text-zinc-500">Reversal reason</span>
                <CommandInput placeholder="Why this settlement is being reversed" value={reason} onChange={(e) => setReason(e.target.value)} />
              </label>
              <CommandButton
                variant="destructive"
                disabled={pending}
                onClick={() => void run(() => reverse.mutateAsync({ settlementId: settlement.id, reason: reason.trim() || undefined }))}
              >
                Reverse settlement (retract paid record)
              </CommandButton>
            </>
          )}

          {(settlement.status === 'failed' || settlement.status === 'reversed') && (
            <p className="text-sm text-zinc-500">
              The payables this settlement claimed have been freed and can be included in a new settlement.
            </p>
          )}
        </div>
      )}
    </CommandDrawer>
  )
}

export function AdminCommerceFinancePage() {
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')
  const [vendorCompanyId, setVendorCompanyId] = useState('')
  const [carrierCompanyId, setCarrierCompanyId] = useState('')
  const overviewFilters = {
    from: from ? new Date(from).toISOString() : undefined,
    to: to ? new Date(to).toISOString() : undefined,
    vendorCompanyId: vendorCompanyId.trim() || undefined,
    carrierCompanyId: carrierCompanyId.trim() || undefined,
  }
  const { data: overview, isLoading: overviewLoading } = useAdminCommerceFinanceOverview(overviewFilters)
  const [settlementStatus, setSettlementStatus] = useState<CommerceSettlementStatus | ''>('')
  const [settlementPayeeCompanyId, setSettlementPayeeCompanyId] = useState('')
  const [settlementPage, setSettlementPage] = useState(1)
  const { data: settlements, isLoading: settlementsLoading } = useCommerceSettlements({
    status: settlementStatus || undefined,
    payeeCompanyId: settlementPayeeCompanyId.trim() || undefined,
    page: settlementPage,
    pageSize: PAGE,
  })
  const [selected, setSelected] = useState<CommerceSettlement | null>(null)

  const [eventsPage, setEventsPage] = useState(1)
  const { data: events, isLoading: eventsLoading } = useAdminCommerceFinancialEvents(eventsPage, PAGE, {
    from: overviewFilters.from,
    to: overviewFilters.to,
    vendorCompanyId: overviewFilters.vendorCompanyId,
  })

  return (
    <div className="space-y-4">
      <SectionHeader eyebrow="Commerce" title="Commerce finance" className="mb-0" />

      <CommandCard>
        <CommandCardBody className="flex flex-wrap items-end gap-3">
          <label className="flex flex-col gap-1 text-xs text-zinc-500">
            From
            <CommandInput type="date" className="w-[160px]" value={from} onChange={(e) => setFrom(e.target.value)} />
          </label>
          <label className="flex flex-col gap-1 text-xs text-zinc-500">
            To
            <CommandInput type="date" className="w-[160px]" value={to} onChange={(e) => setTo(e.target.value)} />
          </label>
          <label className="flex flex-col gap-1 text-xs text-zinc-500">
            Vendor company ID
            <CommandInput
              className="w-[220px]"
              placeholder="All vendors"
              value={vendorCompanyId}
              onChange={(e) => setVendorCompanyId(e.target.value)}
            />
          </label>
          <label className="flex flex-col gap-1 text-xs text-zinc-500">
            Carrier company ID
            <CommandInput
              className="w-[220px]"
              placeholder="All carriers"
              value={carrierCompanyId}
              onChange={(e) => setCarrierCompanyId(e.target.value)}
            />
          </label>
          {(from || to || vendorCompanyId || carrierCompanyId) && (
            <CommandButton
              size="sm"
              onClick={() => {
                setFrom('')
                setTo('')
                setVendorCompanyId('')
                setCarrierCompanyId('')
              }}
            >
              Clear filters
            </CommandButton>
          )}
        </CommandCardBody>
      </CommandCard>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <CommandKpi label="Commerce GMV" value={formatLrdFromCents(overview?.commerce_gmv_lrd_cents ?? 0)} loading={overviewLoading} />
        <CommandKpi label="COD collected" value={formatLrdFromCents(overview?.cod_collected_lrd_cents ?? 0)} loading={overviewLoading} />
        <CommandKpi label="Platform revenue" value={formatLrdFromCents(overview?.platform_revenue_lrd_cents ?? 0)} loading={overviewLoading} color="green" />
        <CommandKpi
          label="Vendor + carrier unsettled"
          value={formatLrdFromCents((overview?.vendor_unsettled_lrd_cents ?? 0) + (overview?.carrier_unsettled_lrd_cents ?? 0))}
          hint={`Vendor ${formatLrdFromCents(overview?.vendor_unsettled_lrd_cents ?? 0)} · Carrier ${formatLrdFromCents(overview?.carrier_unsettled_lrd_cents ?? 0)}`}
          loading={overviewLoading}
          color="amber"
        />
      </div>
      <div className="grid gap-3 sm:grid-cols-5">
        <CommandKpi label="Settlements pending" value={String(overview?.settlements_pending ?? 0)} loading={overviewLoading} />
        <CommandKpi label="Settlements processing" value={String(overview?.settlements_processing ?? 0)} loading={overviewLoading} />
        <CommandKpi label="Settlements completed" value={String(overview?.settlements_completed ?? 0)} loading={overviewLoading} />
        <CommandKpi label="Settlements failed" value={String(overview?.settlements_failed ?? 0)} loading={overviewLoading} color={overview && overview.settlements_failed > 0 ? 'red' : 'gray'} />
        <CommandKpi label="Reversals recorded" value={String(overview?.reversals_count ?? 0)} loading={overviewLoading} />
      </div>

      <CreateSettlementForm />

      <CommandCard>
        <CommandCardHeader title="Settlements" description="Manual/admin-confirmed only — no money is ever sent electronically from here." />
        <CommandCardBody className="flex flex-wrap gap-2 border-b border-white/[0.06] pb-4">
          <CommandSelect
            className="max-w-[220px]"
            value={settlementStatus}
            onChange={(e) => {
              setSettlementStatus(e.target.value as CommerceSettlementStatus | '')
              setSettlementPage(1)
            }}
          >
            <option value="">All statuses</option>
            <option value="pending">Pending</option>
            <option value="processing">Processing</option>
            <option value="settled">Settled</option>
            <option value="failed">Failed</option>
            <option value="reversed">Reversed</option>
          </CommandSelect>
          <CommandInput
            className="max-w-[220px]"
            placeholder="Filter by payee company ID"
            value={settlementPayeeCompanyId}
            onChange={(e) => {
              setSettlementPayeeCompanyId(e.target.value)
              setSettlementPage(1)
            }}
          />
        </CommandCardBody>
        {settlementsLoading ? (
          <p className="p-4 text-sm text-zinc-500">Loading…</p>
        ) : (settlements?.rows ?? []).length === 0 ? (
          <CommandEmptyState label="No settlements match this filter." />
        ) : (
          <CommandTable>
            <CommandTableHead>
              <CommandTh>Payee</CommandTh>
              <CommandTh>Type</CommandTh>
              <CommandTh>Amount</CommandTh>
              <CommandTh>Status</CommandTh>
              <CommandTh>Created</CommandTh>
              <CommandTh className="text-right">Manage</CommandTh>
            </CommandTableHead>
            <tbody>
              {(settlements?.rows ?? []).map((s) => (
                <CommandTr key={s.id}>
                  <CommandTd className="font-medium text-zinc-100">{s.payee_company_name}</CommandTd>
                  <CommandTd className="capitalize text-zinc-400">{s.payee_type}</CommandTd>
                  <CommandTd className="tabular-nums">{formatLrdFromCents(s.total_amount_lrd_cents)}</CommandTd>
                  <CommandTd><StatusChip color={settlementColor(s.status)} label={s.status} /></CommandTd>
                  <CommandTd className="text-zinc-400">{new Date(s.created_at).toLocaleDateString()}</CommandTd>
                  <CommandTd className="text-right">
                    <CommandButton size="sm" onClick={() => setSelected(s)}>Manage</CommandButton>
                  </CommandTd>
                </CommandTr>
              ))}
            </tbody>
          </CommandTable>
        )}
        <div className="px-4 pb-4">
          <CommandPagination total={settlements?.total ?? 0} page={settlementPage} pageSize={PAGE} onPage={setSettlementPage} loading={settlementsLoading} />
        </div>
      </CommandCard>

      <CommandCard>
        <CommandCardHeader title="Financial events" description="Every recognized COD collection and reversal, in order — the raw ledger journal." />
        {eventsLoading ? (
          <p className="p-4 text-sm text-zinc-500">Loading…</p>
        ) : (events?.rows ?? []).length === 0 ? (
          <CommandEmptyState label="No financial events yet." />
        ) : (
          <CommandTable>
            <CommandTableHead>
              <CommandTh>Order</CommandTh>
              <CommandTh>Type</CommandTh>
              <CommandTh>Vendor gross</CommandTh>
              <CommandTh>Platform fee</CommandTh>
              <CommandTh>Recognized</CommandTh>
            </CommandTableHead>
            <tbody>
              {(events?.rows ?? []).map((e) => (
                <CommandTr key={e.id}>
                  <CommandTd className="font-medium text-zinc-100">{e.order_number}</CommandTd>
                  <CommandTd className="capitalize text-zinc-400">{e.event_type.replace(/_/g, ' ')}</CommandTd>
                  <CommandTd className="tabular-nums">{formatLrdFromCents(Number(e.snapshot.vendor_gross_lrd_cents ?? 0))}</CommandTd>
                  <CommandTd className="tabular-nums">
                    {formatLrdFromCents(Number(e.snapshot.vendor_platform_fee_lrd_cents ?? 0) + Number(e.snapshot.carrier_platform_fee_lrd_cents ?? 0))}
                  </CommandTd>
                  <CommandTd className="text-zinc-400">{new Date(e.created_at).toLocaleString()}</CommandTd>
                </CommandTr>
              ))}
            </tbody>
          </CommandTable>
        )}
        <div className="px-4 pb-4">
          <CommandPagination total={events?.total ?? 0} page={eventsPage} pageSize={PAGE} onPage={setEventsPage} loading={eventsLoading} />
        </div>
      </CommandCard>

      <SettlementDrawer settlement={selected} onClose={() => setSelected(null)} />
    </div>
  )
}
