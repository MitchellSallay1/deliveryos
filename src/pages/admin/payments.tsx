import { useState } from 'react'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { useBillingPaymentsPage } from '@/hooks/use-billing'
import { downloadCsv, rowsToCsv } from '@/utils/csv-export'
import { formatLrdFromCents } from '@/utils/delivery-schemas'

export function AdminPaymentsPage() {
  const [page, setPage] = useState(1)
  const { data, isLoading } = useBillingPaymentsPage(null, page, true)
  const rows = (data?.rows ?? []) as Record<string, unknown>[]

  return (
    <Card>
      <CardHeader>
        <CardTitle>Subscription payments</CardTitle>
      </CardHeader>
      <CardContent>
        <Button
          type="button"
          size="sm"
          variant="outline"
          className="mb-3"
          onClick={() =>
            downloadCsv(
              'subscription-payments.csv',
              rowsToCsv(rows, ['company_name', 'amount_cents', 'payment_method', 'reference', 'paid_at']),
            )
          }
        >
          Export CSV
        </Button>
        {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
        <table className="w-full text-left text-sm">
          <thead>
            <tr className="border-b text-xs uppercase text-[var(--color-muted)]">
              <th className="py-2">Company</th>
              <th className="py-2">Amount</th>
              <th className="py-2">Method</th>
              <th className="py-2">Reference</th>
              <th className="py-2">Paid</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={String(r.id)} className="border-b">
                <td className="py-2">{String(r.company_name)}</td>
                <td className="py-2">{formatLrdFromCents(Number(r.amount_cents))}</td>
                <td className="py-2">{String(r.payment_method)}</td>
                <td className="py-2">{String(r.reference ?? '—')}</td>
                <td className="py-2 text-xs">{String(r.paid_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
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
