import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/Card'
import { Button } from '@/components/ui/Button'
import { Badge } from '@/components/ui/Badge'
import { PageHeader } from '@/components/ui/PageHeader'
import { useAuth } from '@/hooks/use-auth'
import { usePublicPlans } from '@/hooks/use-billing'
import { getMarketplaceAnalytics } from '@/services/marketplace-service'
import { fetchCompanyUsage } from '@/services/billing-service'
import { formatTrialEndsAt, trialBannerMessage } from '@/lib/trial-display'
import { formatLrdFromCents } from '@/utils/delivery-schemas'

type PublicPlan = {
  id: string
  slug: string
  name: string
  price_lrd_cents: number
  currency: string
  max_riders: number
  max_deliveries_per_month: number | null
  monthly_sms_allowance: number
  proof_of_delivery: boolean
  advanced_reports: boolean
  api_access: boolean
  gps_tracking: boolean
  custom_branding: boolean
}

export function BillingPage() {
  const { context } = useAuth()
  const companyId = context?.activeCompanyId
  const businessType = context?.memberships.find((m) => m.company_id === companyId)?.company
    .business_type

  const { data: usage } = useQuery({
    queryKey: ['billing-summary', companyId],
    queryFn: () => fetchCompanyUsage(companyId!),
    enabled: !!companyId,
  })

  const { data: marketplace } = useQuery({
    queryKey: ['billing-marketplace', companyId, businessType],
    queryFn: () =>
      getMarketplaceAnalytics(
        businessType === 'logistics_provider' ? 'provider' : 'merchant',
        companyId!,
      ),
    enabled: !!companyId && businessType !== undefined,
  })

  const { data: plans = [] } = usePublicPlans(true)

  const trialMsg = trialBannerMessage(usage?.trial)
  const currentPlanSlug = (usage?.plan as { slug?: string })?.slug

  return (
    <div className="mx-auto max-w-4xl space-y-6 animate-fade-in">
      <PageHeader
        title="Billing & usage"
        description="Plans, trial status, and marketplace summary — same data as before, clearer layout."
      />
      {trialMsg && (
        <Card>
          <CardHeader>
            <CardTitle>{trialMsg.headline}</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <p>{trialMsg.detail}</p>
            {usage?.trial?.trial_ends_at ? (
              <p className="text-[var(--color-muted)]">
                Trial ends: {formatTrialEndsAt(usage.trial.trial_ends_at)}
              </p>
            ) : null}
            {usage?.trial?.days_remaining != null && !usage.trial.expired ? (
              <p>{usage.trial.days_remaining} days remaining</p>
            ) : null}
            <Button
              type="button"
              size="sm"
              onClick={() => document.getElementById('plans')?.scrollIntoView({ behavior: 'smooth' })}
            >
              View plans
            </Button>
          </CardContent>
        </Card>
      )}
      <Card>
        <CardHeader>
          <CardTitle>Subscription</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2 text-sm">
          <p>Plan: {(usage?.plan as { name?: string })?.name ?? '—'}</p>
          <p>Status: {(usage?.subscription as { status?: string })?.status ?? '—'}</p>
          <Link to="/settings" className="text-[var(--color-primary)] hover:underline">
            Manage integrations & company settings
          </Link>
        </CardContent>
      </Card>
      {marketplace && (
        <Card>
          <CardHeader>
            <CardTitle>Marketplace spend / revenue</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-2xl font-semibold tabular-nums">
              LRD {Number(marketplace.gmv_lrd_cents ?? 0) / 100}
            </p>
            <p className="text-sm text-[var(--color-muted)]">
              Platform fees (where applicable): LRD{' '}
              {Number(marketplace.platform_fees_lrd_cents ?? 0) / 100}
            </p>
          </CardContent>
        </Card>
      )}

      <div id="plans" className="space-y-3 scroll-mt-6">
        <div>
          <h2 className="text-lg font-semibold">Available plans</h2>
          <p className="text-sm text-[var(--color-muted)]">
            Online self-service checkout is not enabled yet — contact DeliveryOS to change your
            plan. Pricing, limits, and features below come directly from the current plan catalog.
          </p>
        </div>
        <div className="grid gap-4 sm:grid-cols-3">
          {(plans as unknown as PublicPlan[]).map((p) => {
            const isCurrent = p.slug === currentPlanSlug
            return (
              <Card key={p.id} className={isCurrent ? 'border-[var(--color-primary)]' : undefined}>
                <CardHeader>
                  <div className="flex items-center justify-between gap-2">
                    <CardTitle className="text-base">{p.name}</CardTitle>
                    {isCurrent && <Badge variant="accent">Current plan</Badge>}
                  </div>
                  <CardDescription>
                    {p.price_lrd_cents > 0
                      ? `${formatLrdFromCents(p.price_lrd_cents)} ${p.currency}/mo`
                      : 'Custom pricing'}
                  </CardDescription>
                </CardHeader>
                <CardContent className="space-y-2 text-sm">
                  <ul className="space-y-1 text-[var(--color-muted)]">
                    <li>{p.max_riders} riders</li>
                    <li>
                      {p.max_deliveries_per_month == null
                        ? 'Unlimited deliveries/mo'
                        : `${p.max_deliveries_per_month} deliveries/mo`}
                    </li>
                    <li>{p.monthly_sms_allowance} SMS credits/mo</li>
                    {p.proof_of_delivery && <li>Proof of delivery</li>}
                    {p.advanced_reports && <li>Advanced reports</li>}
                    {p.gps_tracking && <li>GPS tracking</li>}
                    {p.api_access && <li>API access</li>}
                    {p.custom_branding && <li>Custom branding</li>}
                  </ul>
                  {!isCurrent && (
                    <Link to="/contact">
                      <Button type="button" variant="outline" size="sm" className="w-full">
                        Contact us about this plan
                      </Button>
                    </Link>
                  )}
                </CardContent>
              </Card>
            )
          })}
        </div>
      </div>

      <Card className="border-dashed">
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            MTN Mobile Money
            <Badge variant="outline">Coming soon</Badge>
          </CardTitle>
          <CardDescription>Subscription and settlement payments — visual placeholder only.</CardDescription>
        </CardHeader>
        <CardContent className="text-sm text-[var(--color-muted)]">
          No API integration in this phase. Existing manual billing and COD flows unchanged.
        </CardContent>
      </Card>
    </div>
  )
}
