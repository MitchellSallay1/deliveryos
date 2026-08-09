import { Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { listPublicPlans } from '@/services/billing-service'
import { PLAN_CATALOG_FALLBACK, formatPublicPlanPrice, type PublicPlanRow } from '@/lib/marketing-plans'
import { MARKETING_CTA_COMPARE_PLANS } from '@/lib/marketing-cta'
import { Button } from '@/components/ui/Button'
import { Reveal } from '@/components/marketing/Reveal'

export function HomePricingPreview() {
  const { data } = useQuery({ queryKey: ['public-plans'], queryFn: listPublicPlans, staleTime: 60_000 })
  const plans = (data?.length ? data : PLAN_CATALOG_FALLBACK) as PublicPlanRow[]
  const ordered = ['starter', 'business', 'enterprise']
    .map((slug) => plans.find((p) => p.slug === slug))
    .filter(Boolean) as PublicPlanRow[]

  return (
    <Reveal>
      <div className="grid gap-6 md:grid-cols-3">
        {ordered.map((plan) => (
          <div
            key={plan.slug}
            className={`rounded-2xl border p-6 transition hover:shadow-lg ${
              plan.slug === 'business' ? 'border-zinc-900 bg-zinc-900 text-white' : 'border-zinc-200 bg-white'
            }`}
          >
            <p className="text-sm font-semibold uppercase tracking-wider opacity-70">{plan.name}</p>
            <p className="mt-3 text-3xl font-semibold tracking-tight">{formatPublicPlanPrice(plan)}</p>
            <p className={`mt-2 text-sm ${plan.slug === 'business' ? 'text-zinc-300' : 'text-zinc-600'}`}>
              {plan.max_riders} riders · {plan.max_deliveries_per_month ?? 'Custom'} deliveries/mo
            </p>
            <Link to="/register" className="mt-6 block">
              <Button variant={plan.slug === 'business' ? 'accent' : 'outline'} type="button" className="w-full">
                Start trial
              </Button>
            </Link>
          </div>
        ))}
      </div>
      <div className="mt-8 text-center">
        <Link to="/pricing">
          <Button variant="ghost" type="button">
            {MARKETING_CTA_COMPARE_PLANS}
          </Button>
        </Link>
        <p className="mt-2 text-sm text-zinc-500">7-day free trial · Phone sign-up</p>
      </div>
    </Reveal>
  )
}
