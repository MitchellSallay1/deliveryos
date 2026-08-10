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
} from '@/components/admin/control-tower'
import { useBillingPaymentsPage } from '@/hooks/use-billing'
import { downloadCsv, rowsToCsv } from '@/utils/csv-export'
import { formatLrdFromCents } from '@/utils/delivery-schemas'

const PAGE = 25

export function AdminPaymentsPage() {
  const [page, setPage] = useState(1)
  const { data, isLoading } = useBillingPaymentsPage(null, page, true)
  const rows = (data?.rows ?? []) as Record<string, unknown>[]
  const total = data?.total ?? 0

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <SectionHeader eyebrow="Billing" title="Subscription payments" className="mb-0" />
        <CommandButton
          variant="outline"
          onClick={() =>
            downloadCsv(
              'subscription-payments.csv',
              rowsToCsv(rows, ['company_name', 'amount_cents', 'payment_method', 'reference', 'paid_at']),
            )
          }
        >
          Export CSV
        </CommandButton>
      </div>

      <CommandCard>
        {isLoading ? (
          <p className="p-4 text-sm text-zinc-500">Loading…</p>
        ) : rows.length === 0 ? (
          <CommandEmptyState label="No payments recorded yet." />
        ) : (
          <CommandTable>
            <CommandTableHead>
              <CommandTh>Company</CommandTh>
              <CommandTh>Amount</CommandTh>
              <CommandTh>Method</CommandTh>
              <CommandTh>Reference</CommandTh>
              <CommandTh className="text-right">Paid</CommandTh>
            </CommandTableHead>
            <tbody>
              {rows.map((r) => (
                <CommandTr key={String(r.id)}>
                  <CommandTd>{String(r.company_name)}</CommandTd>
                  <CommandTd className="font-medium tabular-nums text-zinc-100">{formatLrdFromCents(Number(r.amount_cents))}</CommandTd>
                  <CommandTd className="capitalize text-zinc-400">{String(r.payment_method).replace(/_/g, ' ')}</CommandTd>
                  <CommandTd className="font-mono text-xs text-zinc-500">{String(r.reference ?? '—')}</CommandTd>
                  <CommandTd className="text-right text-xs text-zinc-500">{new Date(String(r.paid_at)).toLocaleString()}</CommandTd>
                </CommandTr>
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
