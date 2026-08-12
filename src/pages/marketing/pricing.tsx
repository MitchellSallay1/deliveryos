import { Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { usePageMeta } from '@/hooks/use-page-meta'
import { getPageHeadData } from '@/lib/seo/page-head'
import { MarketingCtaBand, MarketingPageShell } from '@/layouts/MarketingLayout'
import { listPublicPlans } from '@/services/billing-service'
import {
  PLAN_CATALOG_FALLBACK,
  formatPlanLimit,
  formatPublicPlanPrice,
  type PublicPlanRow,
} from '@/lib/marketing-plans'
import { Button } from '@/components/ui/Button'

const COMPARISON_ROWS: { label: string; key: keyof PublicPlanRow | 'marketplace' | 'webhooks' | 'fleet' | 'inventory' | 'ussd' | 'support' }[] = [
  { label: 'Deliveries / month', key: 'max_deliveries_per_month' },
  { label: 'Riders', key: 'max_riders' },
  { label: 'Customer tracking', key: 'proof_of_delivery' },
  { label: 'SMS allowance', key: 'monthly_sms_allowance' },
  { label: 'USSD', key: 'ussd' },
  { label: 'GPS tracking', key: 'gps_tracking' },
  { label: 'Reports', key: 'advanced_reports' },
  { label: 'Fleet module', key: 'fleet' },
  { label: 'Inventory', key: 'inventory' },
  { label: 'Marketplace', key: 'marketplace' },
  { label: 'API access', key: 'api_access' },
  { label: 'Webhooks', key: 'webhooks' },
  { label: 'Custom branding', key: 'custom_branding' },
  { label: 'Support', key: 'support' },
]

function cellValue(plan: PublicPlanRow, key: (typeof COMPARISON_ROWS)[number]['key']): string {
  if (key === 'ussd') return plan.slug === 'starter' ? 'Designed' : 'Designed'
  if (key === 'fleet' || key === 'inventory' || key === 'marketplace' || key === 'webhooks')
    return plan.slug === 'starter' ? '—' : plan.slug === 'business' ? 'Add-on' : 'Included'
  if (key === 'support') return plan.slug === 'enterprise' ? 'Priority' : 'Standard'
  const v = plan[key as keyof PublicPlanRow]
  if (typeof v === 'boolean') return v ? 'Yes' : '—'
  if (key === 'max_deliveries_per_month' || key === 'max_riders') return formatPlanLimit(v as number | null)
  if (key === 'monthly_sms_allowance') return v == null ? 'Custom' : String(v)
  return '—'
}

export function PricingPage() {
  usePageMeta(getPageHeadData('pricing'))
  const { data, isLoading } = useQuery({
    queryKey: ['public-plans'],
    queryFn: listPublicPlans,
    staleTime: 60_000,
  })

  const plans = (data?.length ? data : PLAN_CATALOG_FALLBACK) as PublicPlanRow[]
  const ordered = ['starter', 'business', 'enterprise']
    .map((slug) => plans.find((p) => p.slug === slug))
    .filter(Boolean) as PublicPlanRow[]

  return (
    <>
      <div className="border-b border-zinc-200/80 bg-[#faf9f7] py-20">
        <MarketingPageShell className="py-0">
          <h1 className="mkt-display text-zinc-950">Pricing</h1>
          <p className="mkt-lead mt-6 max-w-2xl">
            Starter, Business, and Enterprise — limits enforced in PostgreSQL. 7-day free trial on sign-up.
          </p>
        </MarketingPageShell>
      </div>
      <MarketingPageShell className="py-12">
        <p className="max-w-2xl text-zinc-600">
          7-day free trial on signup. Prices shown from your live plan catalog when available.
        </p>
        {isLoading && <p className="mt-4 text-sm text-zinc-500">Loading plans…</p>}
        <div className="mt-12 grid gap-6 lg:grid-cols-3">
          {ordered.map((plan) => (
            <div
              key={plan.slug}
              className={`flex flex-col rounded-2xl border p-8 ${plan.slug === 'business' ? 'border-zinc-900 shadow-lg' : 'border-zinc-200'}`}
            >
              <h2 className="text-xl font-semibold">{plan.name}</h2>
              <p className="mt-2 text-3xl font-semibold tabular-nums">{formatPublicPlanPrice(plan)}</p>
              <p className="text-sm text-zinc-500">per month · LRD where configured</p>
              <ul className="mt-6 flex-1 space-y-2 text-sm text-zinc-600">
                <li>{formatPlanLimit(plan.max_riders)} riders</li>
                <li>{formatPlanLimit(plan.max_deliveries_per_month)} deliveries / month</li>
                <li>{plan.monthly_sms_allowance ?? 'Custom'} SMS / month</li>
                {plan.api_access && <li>API access</li>}
                {plan.gps_tracking && <li>GPS tracking</li>}
              </ul>
              <Link to={plan.slug === 'enterprise' ? '/contact' : '/register'} className="mt-8 block">
                <Button variant={plan.slug === 'business' ? 'accent' : 'default'} type="button" className="w-full">
                  {plan.slug === 'enterprise' ? 'Contact sales' : 'Start free trial'}
                </Button>
              </Link>
            </div>
          ))}
        </div>

        <h2 className="mt-20 text-2xl font-semibold text-zinc-900">Compare plans</h2>
        <div className="mt-6 overflow-x-auto">
          <table className="w-full min-w-[640px] text-left text-sm">
            <thead>
              <tr className="border-b">
                <th className="py-3 pr-4">Feature</th>
                {ordered.map((p) => (
                  <th key={p.slug} className="py-3 px-2 font-semibold">
                    {p.name}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {COMPARISON_ROWS.map((row) => (
                <tr key={row.label} className="border-b">
                  <td className="py-3 pr-4 text-zinc-600">{row.label}</td>
                  {ordered.map((p) => (
                    <td key={p.slug} className="py-3 px-2">
                      {cellValue(p, row.key)}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div className="mt-16 rounded-xl border border-zinc-200 bg-zinc-50 p-6">
          <h2 className="font-semibold text-zinc-900">Pricing FAQ</h2>
          <dl className="mt-4 space-y-4 text-sm text-zinc-600">
            <div>
              <dt className="font-medium text-zinc-900">Is a credit card required for the trial?</dt>
              <dd className="mt-1">No credit card is required to start the 7-day trial in the current product flow.</dd>
            </div>
            <div>
              <dt className="font-medium text-zinc-900">Can I change plans later?</dt>
              <dd className="mt-1">Plan changes are managed through billing and platform admin workflows.</dd>
            </div>
          </dl>
        </div>
      </MarketingPageShell>
      <MarketingCtaBand />
    </>
  )
}
