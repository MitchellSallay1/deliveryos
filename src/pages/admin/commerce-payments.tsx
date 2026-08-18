import { useState } from 'react'
import {
  CommandButton,
  CommandCard,
  CommandEmptyState,
  CommandPagination,
  CommandTable,
  CommandTableHead,
  CommandTd,
  CommandTh,
  CommandTr,
  SectionHeader,
  StatusChip,
} from '@/components/admin/control-tower'
import { useAdminPaymentAttemptsPage } from '@/hooks/use-admin-platform'
import { adminReconcilePaymentAttempt } from '@/services/admin-platform-service'
import { formatLrdFromCents } from '@/utils/delivery-schemas'

const PAGE = 50

const STATE_COLOR: Record<string, 'gray' | 'amber' | 'green' | 'red'> = {
  created: 'gray',
  requesting: 'amber',
  pending: 'amber',
  successful: 'green',
  failed: 'red',
  unknown: 'red',
}

function ReconcileForm({ attemptId, onDone }: { attemptId: string; onDone: () => void }) {
  const [notes, setNotes] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function resolve(resolution: 'confirmed_successful' | 'confirmed_failed' | 'still_unresolved') {
    setBusy(true)
    setError(null)
    try {
      await adminReconcilePaymentAttempt(attemptId, resolution, notes || undefined)
      onDone()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to reconcile.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="flex flex-col gap-2 rounded-lg border border-zinc-800 bg-zinc-950/60 p-3">
      <p className="text-xs text-zinc-500">
        Only use this after independently verifying the true outcome with WinAggregator/MTN out of band — this never
        contacts the provider itself.
      </p>
      <textarea
        className="min-h-16 rounded-md border border-zinc-800 bg-zinc-900 px-2 py-1 text-xs text-zinc-200"
        placeholder="Verification notes (e.g. WinAggregator support ticket #, confirmed reference id)"
        value={notes}
        onChange={(e) => setNotes(e.target.value)}
      />
      {error && <p className="text-xs text-red-400">{error}</p>}
      <div className="flex flex-wrap gap-2">
        <CommandButton variant="outline" disabled={busy} onClick={() => void resolve('confirmed_successful')}>
          Confirm successful
        </CommandButton>
        <CommandButton variant="outline" disabled={busy} onClick={() => void resolve('confirmed_failed')}>
          Confirm failed
        </CommandButton>
        <CommandButton variant="outline" disabled={busy} onClick={() => void resolve('still_unresolved')}>
          Save note only
        </CommandButton>
      </div>
    </div>
  )
}

export function AdminCommercePaymentsPage() {
  const [page, setPage] = useState(1)
  const [stateFilter, setStateFilter] = useState<string[] | undefined>(undefined)
  const [marginAnomalyOnly, setMarginAnomalyOnly] = useState(false)
  const [expanded, setExpanded] = useState<string | null>(null)
  const { data, isLoading, refetch } = useAdminPaymentAttemptsPage({
    state: stateFilter,
    limit: PAGE,
    offset: (page - 1) * PAGE,
    marginAnomalyOnly,
  })
  const rows = data?.rows ?? []
  const total = data?.total ?? 0

  const filters: { label: string; value: string[] | undefined }[] = [
    { label: 'All', value: undefined },
    { label: 'Needs attention', value: ['pending', 'unknown', 'requesting'] },
    { label: 'Successful', value: ['successful'] },
    { label: 'Failed', value: ['failed'] },
  ]

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <SectionHeader eyebrow="Commerce" title="MTN MoMo payment attempts" className="mb-0" />
        <div className="flex flex-wrap gap-2">
          {filters.map((f) => (
            <CommandButton
              key={f.label}
              variant={JSON.stringify(f.value) === JSON.stringify(stateFilter) ? 'primary' : 'outline'}
              onClick={() => {
                setStateFilter(f.value)
                setPage(1)
              }}
            >
              {f.label}
            </CommandButton>
          ))}
          <CommandButton
            variant={marginAnomalyOnly ? 'primary' : 'outline'}
            onClick={() => {
              setMarginAnomalyOnly((v) => !v)
              setPage(1)
            }}
          >
            Margin anomaly
          </CommandButton>
        </div>
      </div>
      <p className="text-xs text-zinc-500">
        "Margin anomaly" flags successful transactions where the provider's processing fee exceeded platform
        commission on that transaction — a financial review item, not a payment-uncertainty signal (those show up
        under "Needs attention" instead).
      </p>

      <CommandCard>
        {isLoading ? (
          <p className="p-4 text-sm text-zinc-500">Loading…</p>
        ) : rows.length === 0 ? (
          <CommandEmptyState label="No payment attempts in this view." />
        ) : (
          <CommandTable>
            <CommandTableHead>
              <CommandTh>Order</CommandTh>
              <CommandTh>Company</CommandTh>
              <CommandTh>Phone</CommandTh>
              <CommandTh>Amount</CommandTh>
              <CommandTh>State</CommandTh>
              <CommandTh>Provider status</CommandTh>
              <CommandTh>Reconciliation</CommandTh>
              <CommandTh>Margin</CommandTh>
              <CommandTh className="text-right">Created</CommandTh>
            </CommandTableHead>
            <tbody>
              {rows.map((r) => (
                <>
                  <CommandTr
                    key={r.id}
                    className="cursor-pointer"
                    onClick={() => setExpanded(expanded === r.id ? null : r.id)}
                  >
                    <CommandTd className="font-mono text-xs">{r.order_number ?? '—'}</CommandTd>
                    <CommandTd>{r.company_name ?? '—'}</CommandTd>
                    <CommandTd className="font-mono text-xs">{r.payer_msisdn_masked}</CommandTd>
                    <CommandTd className="tabular-nums">{formatLrdFromCents(r.gross_amount_cents)}</CommandTd>
                    <CommandTd>
                      <StatusChip color={STATE_COLOR[r.state] ?? 'gray'} label={r.state} />
                    </CommandTd>
                    <CommandTd className="text-xs text-zinc-500">
                      {r.raw_provider_status ?? '—'} {r.http_status ? `(HTTP ${r.http_status})` : ''}
                    </CommandTd>
                    <CommandTd>
                      <StatusChip
                        color={r.reconciliation_state === 'needs_reconciliation' ? 'amber' : 'gray'}
                        label={r.reconciliation_state.replace(/_/g, ' ')}
                      />
                    </CommandTd>
                    <CommandTd>
                      {r.margin_anomaly ? <StatusChip color="amber" label="anomaly" /> : <span className="text-xs text-zinc-600">—</span>}
                    </CommandTd>
                    <CommandTd className="text-right text-xs text-zinc-500">
                      {new Date(r.created_at).toLocaleString()}
                    </CommandTd>
                  </CommandTr>
                  {expanded === r.id && r.reconciliation_state === 'needs_reconciliation' && (
                    <tr>
                      <td colSpan={9} className="p-3">
                        <ReconcileForm
                          attemptId={r.id}
                          onDone={() => {
                            setExpanded(null)
                            void refetch()
                          }}
                        />
                      </td>
                    </tr>
                  )}
                </>
              ))}
            </tbody>
          </CommandTable>
        )}
        <div className="px-4 pb-4">
          <CommandPagination total={total} page={page} pageSize={PAGE} onPage={setPage} loading={isLoading} />
        </div>
      </CommandCard>
    </div>
  )
}
