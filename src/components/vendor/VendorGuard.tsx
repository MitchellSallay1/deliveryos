import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { useVendorContext } from '@/hooks/use-vendor-context'

/**
 * Shared empty-state for every /vendor/* page — real security lives in the
 * RPC layer (assert_vendor_manager / assert_vendor_order_actor already
 * reject non-merchant/hybrid companies), this is purely the friendly UX
 * companion so a logistics-only company sees an explanation instead of a
 * raw RPC error.
 */
export function VendorGuard({ children }: { children: React.ReactNode }) {
  const { companyId, isVendorEligible } = useVendorContext()

  if (!companyId) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>No workspace</CardTitle>
          <CardDescription>Join or register a company to use Commerce.</CardDescription>
        </CardHeader>
      </Card>
    )
  }

  if (!isVendorEligible) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Vendor Commerce not available</CardTitle>
          <CardDescription>
            This workspace is registered as a logistics provider. Commerce storefront features are
            available to merchant and hybrid businesses.
          </CardDescription>
        </CardHeader>
        <CardContent className="text-sm text-[var(--color-muted)]">
          Contact DeliveryOS if this company should also operate a Vendor storefront.
        </CardContent>
      </Card>
    )
  }

  return <>{children}</>
}
