import { useState } from 'react'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { useAdminBillingActions, useInvoicesPage } from '@/hooks/use-billing'
import { downloadCsv, rowsToCsv } from '@/utils/csv-export'
import { formatLrdFromCents } from '@/utils/delivery-schemas'
import { parseSupabaseError } from '@/lib/supabase-errors'

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
    <Card>
      <CardHeader>
        <CardTitle>Invoices</CardTitle>
      </CardHeader>
      <CardContent>
        <div className="mb-3 flex flex-wrap gap-2">
          <Input
            placeholder="Search invoice #"
            value={search}
            onChange={(e) => {
              setSearch(e.target.value)
              setPage(1)
            }}
            className="max-w-xs"
          />
          <Button type="button" variant="outline" size="sm" onClick={exportCsv}>
            Export CSV
          </Button>
        </div>
        {error && <p className="text-sm text-red-600">{parseSupabaseError(error)}</p>}
        {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
        <table className="w-full text-left text-sm">
          <thead>
            <tr className="border-b text-xs uppercase text-[var(--color-muted)]">
              <th className="py-2">Invoice</th>
              <th className="py-2">Company</th>
              <th className="py-2">Amount</th>
              <th className="py-2">Status</th>
              <th className="py-2">Action</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={String(r.id)} className="border-b">
                <td className="py-2">{String(r.invoice_number)}</td>
                <td className="py-2">{String(r.company_name)}</td>
                <td className="py-2">{formatLrdFromCents(Number(r.amount_cents))}</td>
                <td className="py-2 capitalize">{String(r.status)}</td>
                <td className="py-2">
                  {r.status === 'issued' && (
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => markInvoicePaid.mutate({ invoiceId: String(r.id) })}
                    >
                      Mark paid
                    </Button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        <p className="mt-2 text-xs text-[var(--color-muted)]">
          {total} total · page {page}
        </p>
        <div className="mt-2 flex gap-2">
          <Button size="sm" variant="outline" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>
            Previous
          </Button>
          <Button size="sm" variant="outline" onClick={() => setPage((p) => p + 1)}>
            Next
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}
