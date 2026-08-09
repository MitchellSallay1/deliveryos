import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/Card'
import { Button } from '@/components/ui/Button'
import { PageHeader } from '@/components/ui/PageHeader'
import { Badge } from '@/components/ui/Badge'
import { useAuth } from '@/hooks/use-auth'
import { getMarketplaceAnalytics } from '@/services/marketplace-service'
import { fetchCompanyUsage } from '@/services/billing-service'
import { formatTrialEndsAt, trialBannerMessage } from '@/lib/trial-display'

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

  const trialMsg = trialBannerMessage(usage?.trial)

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
            <Link to="/billing">
              <Button type="button" size="sm">
                Choose plan
              </Button>
            </Link>
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
