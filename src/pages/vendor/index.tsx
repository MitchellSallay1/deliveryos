import { Link } from 'react-router-dom'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { PageHeader } from '@/components/ui/PageHeader'
import { VendorGuard } from '@/components/vendor/VendorGuard'
import { PlanUpgradeNotice } from '@/components/dashboard/PlanUpgradeNotice'
import { OnboardingProgressStrip } from '@/components/dashboard/OnboardingProgressStrip'
import { useVendorContext } from '@/hooks/use-vendor-context'
import { useStoreProfile, useVendorOverview } from '@/hooks/use-vendor-commerce'
import { vendorStateLabel, vendorStateVariant } from '@/lib/vendor-commerce-ui'
import { parseSupabaseError } from '@/lib/supabase-errors'

function Metric({ label, value, accent }: { label: string; value: number; accent?: 'warn' | 'bad' }) {
  const accentClass = accent === 'warn' ? 'text-amber-700' : accent === 'bad' ? 'text-red-700' : ''
  return (
    <Card>
      <CardContent className="pt-6">
        <p className="text-sm text-[var(--color-muted)]">{label}</p>
        <p className={`mt-1 text-2xl font-semibold tabular-nums ${accentClass}`}>{value}</p>
      </CardContent>
    </Card>
  )
}

function VendorOverviewContent() {
  const { companyId, companyName } = useVendorContext()
  const { data: store } = useStoreProfile(companyId)
  const { data: overview, isLoading, error } = useVendorOverview(companyId)

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader title="Vendor overview" description={`${companyName} — Commerce storefront`} />

      {companyId && <OnboardingProgressStrip companyId={companyId} />}

      {store && (
        <Card>
          <CardContent className="flex flex-wrap items-center justify-between gap-3 pt-6">
            <div>
              <p className="text-sm text-[var(--color-muted)]">Store status</p>
              <div className="mt-1 flex items-center gap-2">
                <Badge variant={vendorStateVariant(store.status)}>{vendorStateLabel(store.status)}</Badge>
                {store.status_reason && (
                  <span className="text-sm text-[var(--color-muted)]">{store.status_reason}</span>
                )}
              </div>
            </div>
            {store.status === 'draft' || store.status === 'rejected' ? (
              <Link to="/vendor/settings">
                <Button type="button" size="sm">
                  Finish store setup
                </Button>
              </Link>
            ) : null}
          </CardContent>
        </Card>
      )}

      {error && <p className="text-sm text-red-600">{parseSupabaseError(error)}</p>}

      {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}

      {overview && !overview.commerce_enabled && (
        <Card>
          <CardContent className="pt-6">
            <PlanUpgradeNotice message="Commerce is not included in this store's current plan — orders and catalog changes are read-only until you upgrade." />
          </CardContent>
        </Card>
      )}

      {overview && (
        <>
          <div>
            <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-[var(--color-muted)]">
              Orders
            </h2>
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
              <Metric label="New" value={overview.orders.new} accent="warn" />
              <Metric label="Preparing" value={overview.orders.preparing} />
              <Metric label="Ready for pickup" value={overview.orders.ready_for_pickup} />
              <Metric label="Completed" value={overview.orders.completed} />
              <Metric label="Cancelled / rejected" value={overview.orders.cancelled} accent="bad" />
            </div>
          </div>

          <div>
            <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-[var(--color-muted)]">
              Catalog
            </h2>
            <div className="grid gap-4 sm:grid-cols-3">
              <Metric label="Products" value={overview.catalog.product_count} />
              <Metric label="Low stock" value={overview.catalog.low_stock} accent={overview.catalog.low_stock > 0 ? 'warn' : undefined} />
              <Metric label="Out of stock" value={overview.catalog.out_of_stock} accent={overview.catalog.out_of_stock > 0 ? 'bad' : undefined} />
            </div>
          </div>
        </>
      )}

      <Card>
        <CardHeader>
          <CardTitle>Quick links</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-wrap gap-2">
          <Link to="/vendor/orders"><Button type="button" variant="outline" size="sm">Order inbox</Button></Link>
          <Link to="/vendor/catalog"><Button type="button" variant="outline" size="sm">Categories</Button></Link>
          <Link to="/vendor/products"><Button type="button" variant="outline" size="sm">Products</Button></Link>
          <Link to="/vendor/locations"><Button type="button" variant="outline" size="sm">Locations</Button></Link>
          <Link to="/vendor/settings"><Button type="button" variant="outline" size="sm">Store setup</Button></Link>
        </CardContent>
      </Card>
    </div>
  )
}

export function VendorOverviewPage() {
  return (
    <VendorGuard>
      <VendorOverviewContent />
    </VendorGuard>
  )
}
