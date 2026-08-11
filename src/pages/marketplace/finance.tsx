import { Badge } from '@/components/ui/Badge'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { useAuth } from '@/hooks/use-auth'
import { useCarrierCommerceFinance, useCommerceSettlements } from '@/hooks/use-commerce-finance'
import { parseSupabaseError } from '@/lib/supabase-errors'
import { formatLrdFromCents } from '@/utils/delivery-schemas'

function KpiCard({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-sm font-medium text-[var(--color-muted)]">{label}</CardTitle>
      </CardHeader>
      <CardContent>
        <p className="text-2xl font-semibold tabular-nums">{value}</p>
        {hint && <p className="mt-1 text-xs text-[var(--color-muted)]">{hint}</p>}
      </CardContent>
    </Card>
  )
}

export function MarketplaceFinancePage() {
  const { context } = useAuth()
  const companyId = context?.activeCompanyId ?? null
  const { data: finance, isLoading, error } = useCarrierCommerceFinance(companyId)
  const { data: settlements } = useCommerceSettlements({ payeeType: 'carrier', payeeCompanyId: companyId ?? undefined, page: 1 })

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <div>
        <h2 className="text-xl font-semibold">Commerce delivery earnings</h2>
        <p className="text-sm text-[var(--color-muted)]">
          Real figures from Commerce orders where cash-on-delivery was actually collected — separate from your overall
          marketplace GMV shown on the jobs page, since COD earnings aren&apos;t real until the cash is in hand.
        </p>
      </div>

      {error && <p className="text-sm text-red-600">{parseSupabaseError(error)}</p>}
      {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}

      {finance && (
        <>
          <div className="grid gap-4 sm:grid-cols-2">
            <KpiCard
              label="Delivery earnings collected"
              value={formatLrdFromCents(finance.carrier_gross_lrd_cents)}
              hint="Sum of delivery fees on Commerce orders you actually delivered and were paid COD for"
            />
            <KpiCard
              label="Platform fees charged"
              value={formatLrdFromCents(finance.platform_fees_lrd_cents)}
              hint="DeliveryOS marketplace commission on your delivery fee"
            />
            <KpiCard
              label="Net payable"
              value={formatLrdFromCents(finance.net_earnings_lrd_cents)}
              hint="Delivery earnings minus platform fees"
            />
            <KpiCard
              label="Pending settlement"
              value={formatLrdFromCents(finance.pending_settlement_lrd_cents)}
              hint="Recognized but not yet paid out to you"
            />
          </div>

          <Card>
            <CardHeader>
              <CardTitle>Settled to date</CardTitle>
              <CardDescription>Amount DeliveryOS has recorded as paid out to you via a completed settlement.</CardDescription>
            </CardHeader>
            <CardContent>
              <p className="text-xl font-semibold tabular-nums">{formatLrdFromCents(finance.settled_lrd_cents)}</p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Delivery-level breakdown</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2">
              {finance.deliveries.length === 0 && <p className="text-sm text-[var(--color-muted)]">No recognized deliveries yet.</p>}
              {finance.deliveries.map((d) => (
                <div key={d.delivery_id} className="flex items-center justify-between border-b py-2 text-sm last:border-0">
                  <div>
                    <p className="font-medium">{d.tracking_code}</p>
                    <p className="text-xs text-[var(--color-muted)]">{new Date(d.recognized_at).toLocaleString()}</p>
                  </div>
                  <div className="text-right">
                    <p className="tabular-nums">{formatLrdFromCents(d.carrier_net_lrd_cents)} net</p>
                    <p className="text-xs text-[var(--color-muted)] tabular-nums">
                      {formatLrdFromCents(d.carrier_gross_lrd_cents)} gross − {formatLrdFromCents(d.carrier_platform_fee_lrd_cents)} fee
                    </p>
                  </div>
                </div>
              ))}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Settlement history</CardTitle>
              <CardDescription>DeliveryOS records settlements manually today — this is a record of what was paid, not an automatic transfer.</CardDescription>
            </CardHeader>
            <CardContent className="space-y-2">
              {(settlements?.rows ?? []).length === 0 && <p className="text-sm text-[var(--color-muted)]">No settlements yet.</p>}
              {(settlements?.rows ?? []).map((s) => (
                <div key={s.id} className="flex items-center justify-between border-b py-2 text-sm last:border-0">
                  <div>
                    <p className="tabular-nums font-medium">{formatLrdFromCents(s.total_amount_lrd_cents)}</p>
                    <p className="text-xs text-[var(--color-muted)]">{new Date(s.created_at).toLocaleString()}</p>
                    {s.external_reference && <p className="text-xs text-[var(--color-muted)]">Ref: {s.external_reference}</p>}
                  </div>
                  <Badge
                    variant={
                      s.status === 'settled' ? 'success' : s.status === 'failed' ? 'danger' : s.status === 'reversed' ? 'danger' : 'outline'
                    }
                  >
                    {s.status}
                  </Badge>
                </div>
              ))}
            </CardContent>
          </Card>
        </>
      )}
    </div>
  )
}
