import { useState } from 'react'
import {
  CommandButton,
  CommandCard,
  CommandCardBody,
  CommandEmptyState,
  CommandInput,
  CommandPagination,
  CommandTable,
  CommandTableHead,
  CommandTd,
  CommandTh,
  CommandTr,
  SectionHeader,
  StatusChip,
} from '@/components/admin/control-tower'
import { statusColorFor } from '@/lib/admin-control-tower'
import { useAdminBillingActions, useInvoicesPage } from '@/hooks/use-billing'
import { downloadCsv, rowsToCsv } from '@/utils/csv-export'
import { formatLrdFromCents } from '@/utils/delivery-schemas'
import { parseSupabaseError } from '@/lib/supabase-errors'

const PAGE = 25

export function AdminInvoicesPage() {
  const [page, setPage] = useState(1)
  const [search, setSearch] = useState('')
  const { data, isLoading, error } = useInvoicesPage({ search, page }, true)
  const { markInvoicePaid } = useAdminBillingActions()
  const rows = (data?.rows ?? []) as Record<string, unknown>[]
  const total = data?.total ?? 0

  function exportCsv() {
    downloadCsv(
      'invoices.csv',
      rowsToCsv(rows, ['invoice_number', 'company_name', 'status', 'amount_cents', 'due_at']),
    )
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <SectionHeader eyebrow="Billing" title="Invoices" className="mb-0" />
        <CommandButton variant="outline" onClick={exportCsv}>
          Export CSV
        </CommandButton>
      </div>

      <CommandCard>
        <CommandCardBody className="border-b border-white/[0.06] pb-4">
          <CommandInput
            className="max-w-xs"
            placeholder="Search invoice #"
            value={search}
            onChange={(e) => {
              setSearch(e.target.value)
              setPage(1)
            }}
          />
        </CommandCardBody>

        {error && <p className="px-4 pt-3 text-sm text-red-400">{parseSupabaseError(error)}</p>}

        {isLoading ? (
          <p className="p-4 text-sm text-zinc-500">Loading…</p>
        ) : rows.length === 0 ? (
          <CommandEmptyState label="No invoices match this search." />
        ) : (
          <CommandTable>
            <CommandTableHead>
              <CommandTh>Invoice</CommandTh>
              <CommandTh>Company</CommandTh>
              <CommandTh>Amount</CommandTh>
              <CommandTh>Status</CommandTh>
              <CommandTh className="text-right">Action</CommandTh>
            </CommandTableHead>
            <tbody>
              {rows.map((r) => (
                <CommandTr key={String(r.id)}>
                  <CommandTd>{String(r.invoice_number)}</CommandTd>
                  <CommandTd>{String(r.company_name)}</CommandTd>
                  <CommandTd className="font-medium tabular-nums text-zinc-100">{formatLrdFromCents(Number(r.amount_cents))}</CommandTd>
                  <CommandTd>
                    <StatusChip color={statusColorFor(String(r.status))} label={String(r.status)} />
                  </CommandTd>
                  <CommandTd className="text-right">
                    {r.status === 'issued' && (
                      <CommandButton size="sm" onClick={() => markInvoicePaid.mutate({ invoiceId: String(r.id) })}>
                        Mark paid
                      </CommandButton>
                    )}
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
    </div>
  )
}
