import { Link } from 'react-router-dom'
import { usePageMeta } from '@/hooks/use-page-meta'
import { Reveal } from '@/components/marketing/Reveal'
import { HomePricingPreview } from '@/components/marketing/HomePricingPreview'
import { PremiumHero } from '@/components/marketing/hero/PremiumHero'
import { FeatureTrustStrip } from '@/components/marketing/hero/FeatureTrustStrip'
import { OldVsDeliveryOS } from '@/components/marketing/hero/OldVsDeliveryOS'
import { MarketingControlTower } from '@/components/marketing/visuals/MarketingControlTower'
import { MarketingDispatchFlow } from '@/components/marketing/visuals/MarketingDispatchFlow'
import { MarketingRiderPhone, MarketingButtonPhone } from '@/components/marketing/visuals/MarketingRiderPhone'
import { MarketingTrackingPreview } from '@/components/marketing/visuals/MarketingTrackingPreview'
import { MarketingCodPanel } from '@/components/marketing/visuals/MarketingCodPanel'
import { MarketingMarketplaceFlow } from '@/components/marketing/visuals/MarketingMarketplaceFlow'
import { MarketingApiPreview } from '@/components/marketing/visuals/MarketingApiPreview'
import {
  MARKETING_CTA_CONTACT,
  MARKETING_CTA_DEVELOPERS,
  MARKETING_CTA_TRIAL,
  MTN_INTEGRATION_STATUS,
} from '@/lib/marketing-cta'
import { Button } from '@/components/ui/Button'

const OPS_MODULES = ['Fleet', 'Warehouses', 'Inventory', 'Branches', 'Maintenance', 'Expenses', 'Profitability']

export function HomePage() {
  usePageMeta({
    title: 'Deliver smarter',
    description:
      'The operating system for modern delivery businesses. Dispatch, riders, tracking, COD, and operations in one platform.',
    path: '/',
  })

  return (
    <div className="overflow-x-hidden bg-[#F8F6F1]">
      <PremiumHero />
      <FeatureTrustStrip />
      <OldVsDeliveryOS />

      {/* Control tower (light section) */}
      <section className="border-b border-zinc-200/80 bg-[#F8F6F1] py-20 sm:py-28">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <Reveal>
            <h2 className="text-3xl font-semibold tracking-tight text-zinc-900 sm:text-4xl">See your entire operation.</h2>
            <p className="mt-4 max-w-xl text-lg text-zinc-600">
              The same control tower your dispatch team uses — live map, riders, and performance in one view.
            </p>
          </Reveal>
          <Reveal delayMs={100} className="mt-12">
            <MarketingControlTower dark deliveryStatus="in_transit" className="mx-auto max-w-4xl" />
          </Reveal>
        </div>
      </section>

      <section className="border-b border-zinc-200/80 bg-white py-20 sm:py-28">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <Reveal>
            <h2 className="text-3xl font-semibold tracking-tight text-zinc-900 sm:text-4xl">From order to doorstep.</h2>
          </Reveal>
          <div className="mt-16">
            <MarketingDispatchFlow />
          </div>
        </div>
      </section>

      <section className="bg-[#F8F6F1] py-20 sm:py-28">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <Reveal>
            <h2 className="text-center text-3xl font-semibold tracking-tight text-zinc-900 sm:text-4xl">
              Built for every rider.
            </h2>
          </Reveal>
          <div className="mt-16 grid gap-12 lg:grid-cols-2 lg:items-center">
            <MarketingRiderPhone />
            <div>
              <MarketingButtonPhone />
              <p className="mx-auto mt-6 max-w-sm text-center text-sm font-medium text-zinc-800 lg:text-left">
                No smartphone? No problem.
              </p>
            </div>
          </div>
        </div>
      </section>

      <section className="bg-white py-20 sm:py-28">
        <div className="mx-auto grid max-w-7xl items-center gap-12 px-4 sm:px-6 lg:grid-cols-2 lg:px-8">
          <Reveal>
            <h2 className="text-3xl font-semibold tracking-tight text-zinc-900 sm:text-4xl">
              Customers always know where their delivery is.
            </h2>
          </Reveal>
          <Reveal delayMs={120}>
            <MarketingTrackingPreview />
          </Reveal>
        </div>
      </section>

      <section className="border-y border-zinc-200/80 bg-[#F8F6F1] py-20 sm:py-28">
        <div className="mx-auto grid max-w-7xl items-center gap-12 px-4 sm:px-6 lg:grid-cols-2 lg:px-8">
          <MarketingCodPanel />
          <Reveal>
            <h2 className="text-3xl font-semibold tracking-tight text-zinc-900 sm:text-4xl">
              Know where every dollar goes.
            </h2>
            <p className="mt-4 text-sm text-zinc-500">Demo figures on this page are presentation-only.</p>
          </Reveal>
        </div>
      </section>

      <section className="bg-white py-20 sm:py-28">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <Reveal>
            <h2 className="text-3xl font-semibold tracking-tight text-zinc-900 sm:text-4xl">Operations beyond dispatch.</h2>
          </Reveal>
          <div className="mkt-scroll-x mt-12">
            {OPS_MODULES.map((m) => (
              <div key={m} className="rounded-2xl border border-zinc-200 bg-[#F8F6F1] p-6">
                <p className="text-xl font-semibold text-zinc-900">{m}</p>
                <div className="mt-4 h-24 rounded-lg bg-white" />
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="mkt-section-dark py-20 sm:py-28">
        <div className="mx-auto max-w-7xl px-4 text-center sm:px-6 lg:px-8">
          <Reveal>
            <h2 className="text-3xl font-semibold tracking-tight sm:text-4xl">
              Your own riders when you have them.
              <span className="mt-2 block text-zinc-400">A delivery network when you don&apos;t.</span>
            </h2>
          </Reveal>
          <Reveal delayMs={100} className="mt-12">
            <MarketingMarketplaceFlow />
          </Reveal>
        </div>
      </section>

      <section className="relative overflow-hidden bg-[#FFCB05] py-20 sm:py-24">
        <div className="mx-auto max-w-7xl px-4 text-center sm:px-6 lg:px-8">
          <Reveal>
            <p className="text-2xl font-semibold text-black">DeliveryOS</p>
            <p className="mt-1 text-sm font-semibold uppercase tracking-widest text-black/70">Powered by MTN</p>
            <div className="mt-10 grid gap-4 sm:grid-cols-3">
              {['MTN SMS', 'MTN USSD', 'MTN Mobile Money'].map((label) => (
                <div key={label} className="rounded-xl border border-black/10 bg-black/5 px-4 py-5">
                  <p className="font-semibold text-black">{label}</p>
                  <p className="mt-2 text-sm font-medium text-black/70">{MTN_INTEGRATION_STATUS}</p>
                </div>
              ))}
            </div>
          </Reveal>
        </div>
      </section>

      <section className="border-b border-zinc-200/80 bg-[#F8F6F1] py-20 sm:py-28">
        <div className="mx-auto grid max-w-7xl gap-16 px-4 sm:px-6 lg:grid-cols-2 lg:px-8">
          <Reveal>
            <h2 className="text-3xl font-semibold tracking-tight text-zinc-900">Built to connect.</h2>
            <MarketingApiPreview />
            <Link to="/developers" className="mt-6 inline-block">
              <Button variant="outline" type="button">
                {MARKETING_CTA_DEVELOPERS}
              </Button>
            </Link>
          </Reveal>
          <Reveal delayMs={120}>
            <h2 className="text-3xl font-semibold tracking-tight text-zinc-900">Your operation. Your data.</h2>
            <ul className="mt-8 space-y-3 text-sm text-zinc-700">
              {['Multi-tenant isolation', 'Role-based access', 'Row Level Security', 'Audit logs', 'Secure API auth'].map(
                (item) => (
                  <li key={item} className="border-l-2 border-[#FFCB05] pl-4 font-medium">
                    {item}
                  </li>
                ),
              )}
            </ul>
          </Reveal>
        </div>
      </section>

      <section className="bg-white py-20 sm:py-28">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <Reveal>
            <h2 className="text-center text-3xl font-semibold tracking-tight text-zinc-900">Plans that grow with you.</h2>
          </Reveal>
          <div className="mt-12">
            <HomePricingPreview />
          </div>
        </div>
      </section>

      <section className="mkt-section-dark py-24 sm:py-32">
        <div className="mx-auto max-w-3xl px-4 text-center sm:px-6 lg:px-8">
          <Reveal>
            <h2 className="text-3xl font-semibold tracking-tight sm:text-4xl lg:text-5xl">
              Your delivery operation deserves better infrastructure.
            </h2>
            <div className="mt-10 flex flex-wrap justify-center gap-3">
              <Link to="/register">
                <Button variant="accent" type="button" className="h-12 px-8">
                  {MARKETING_CTA_TRIAL}
                </Button>
              </Link>
              <Link to="/contact">
                <Button variant="outline" type="button" className="h-12 border-zinc-600 bg-transparent px-8 text-white">
                  {MARKETING_CTA_CONTACT}
                </Button>
              </Link>
            </div>
          </Reveal>
        </div>
      </section>
    </div>
  )
}
