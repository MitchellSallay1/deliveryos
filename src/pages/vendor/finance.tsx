import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { Badge } from '@/components/ui/Badge'
import { PageHeader } from '@/components/ui/PageHeader'
import { VendorGuard } from '@/components/vendor/VendorGuard'
import { useVendorContext } from '@/hooks/use-vendor-context'
import { useVendorOrders } from '@/hooks/use-vendor-commerce'
import { formatLrdFromCents } from '@/utils/delivery-schemas'

function VendorFinanceContent() {
  const { companyId } = useVendorContext()
  // "Completed" orders only — the one fulfillment state where the order
  // value is no longer subject to rejection/cancellation. This is order
  // value, not collected revenue: no payment processor, commission split,
  // or settlement exists yet (Phase E/F).
  const { data } = useVendorOrders(companyId, ['completed'], 1)
  const completedOrders = data?.rows ?? []
  const totalOrderValue = completedOrders.reduce((sum, o) => sum + o.subtotal_lrd_cents, 0)

  return (
    <div className="mx-auto max-w-2xl space-y-6 animate-fade-in">
      <PageHeader title="Vendor finance" description="Order value today — payment collection and settlement are not live yet." />

      <Card className="border-dashed">
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            Payments & settlements
            <Badge variant="outline">Coming soon</Badge>
          </CardTitle>
          <CardDescription>
            Finance becomes available once Commerce payments (MTN MoMo / Orange Money) are enabled.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-2 text-sm text-[var(--color-muted)]">
          <p>Not available yet, and not shown here because they don't exist yet:</p>
          <ul className="list-inside list-disc">
            <li>Gross merchandise value (GMV) collected</li>
            <li>Vendor earnings after platform commission</li>
            <li>Settlement / payout history</li>
            <li>Platform commission charged</li>
          </ul>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Order value (completed orders)</CardTitle>
          <CardDescription>
            Sum of product subtotals on completed orders — this is what customers were charged for
            merchandise, not confirmed collected revenue.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <p className="text-2xl font-semibold tabular-nums">{formatLrdFromCents(totalOrderValue)}</p>
          <p className="mt-1 text-xs text-[var(--color-muted)]">{completedOrders.length} completed orders</p>
        </CardContent>
      </Card>
    </div>
  )
}

export function VendorFinancePage() {
  return (
    <VendorGuard>
      <VendorFinanceContent />
    </VendorGuard>
  )
}
