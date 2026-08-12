import { Link } from 'react-router-dom'
import { usePageMeta } from '@/hooks/use-page-meta'
import { getPageHeadData } from '@/lib/seo/page-head'
import { useMarketingHashScroll } from '@/hooks/use-marketing-hash-scroll'
import { MarketingCtaBand } from '@/layouts/MarketingLayout'
import { Reveal } from '@/components/marketing/Reveal'
import { ProductTourHero } from '@/components/marketing/features/ProductTourHero'
import { HeroControlTower } from '@/components/marketing/hero/HeroControlTower'
import { MarketingDispatchFlow } from '@/components/marketing/visuals/MarketingDispatchFlow'
import { MarketingRiderPhone, MarketingButtonPhone } from '@/components/marketing/visuals/MarketingRiderPhone'
import { MarketingTrackingPreview } from '@/components/marketing/visuals/MarketingTrackingPreview'
import { MarketingCodPanel } from '@/components/marketing/visuals/MarketingCodPanel'
import { MarketingMarketplaceFlow } from '@/components/marketing/visuals/MarketingMarketplaceFlow'
import { MarketingApiPreview } from '@/components/marketing/visuals/MarketingApiPreview'

function TourSection({
  id,
  dark,
  title,
  children,
  className = '',
}: {
  id: string
  dark?: boolean
  title: string
  children: React.ReactNode
  className?: string
}) {
  return (
    <section
      id={id}
      className={`scroll-mt-[72px] py-16 sm:py-20 ${dark ? 'bg-[#11110F] text-white' : 'bg-[#F8F6F1]'} ${className}`}
    >
      <div className="mx-auto max-w-[1440px] px-4 sm:px-6 lg:px-8">
        <Reveal>
          <h2 className={`text-3xl font-semibold tracking-tight sm:text-4xl ${dark ? 'text-white' : 'text-zinc-900'}`}>
            {title}
          </h2>
        </Reveal>
        <div className="mt-10">{children}</div>
      </div>
    </section>
  )
}

export function FeaturesPage() {
  usePageMeta(getPageHeadData('features'))
  useMarketingHashScroll()

  return (
    <div className="overflow-x-hidden bg-[#F8F6F1]">
      <ProductTourHero />

      <TourSection id="control" dark title="Everything happening right now.">
        <Reveal delayMs={80}>
          <HeroControlTower className="mx-auto max-w-4xl" />
        </Reveal>
      </TourSection>

      <TourSection id="dispatch" title="From request to delivered.">
        <MarketingDispatchFlow />
      </TourSection>

      <TourSection id="riders" dark title="Every rider. Any phone.">
        <div className="grid gap-12 lg:grid-cols-2 lg:items-center">
          <div>
            <p className="text-sm font-semibold uppercase tracking-wider text-[#FFCB05]">Smartphone rider</p>
            <p className="mt-2 text-zinc-400">PWA · GPS · photo proof · OTP</p>
            <MarketingRiderPhone />
          </div>
          <div>
            <p className="text-sm font-semibold uppercase tracking-wider text-zinc-300">Button-phone rider</p>
            <p className="mt-2 text-zinc-400">SMS · USSD when configured</p>
            <MarketingButtonPhone />
          </div>
        </div>
      </TourSection>

      <TourSection id="tracking" title="Visibility for everyone.">
        <MarketingTrackingPreview />
      </TourSection>

      <TourSection id="money" dark title="Cash doesn't disappear into operations.">
        <div className="grid gap-8 lg:grid-cols-2 lg:items-start">
          <MarketingCodPanel />
          <ul className="space-y-3 text-sm text-zinc-300">
            {['COD collected', 'Cash held by rider', 'Deposited', 'Reconciled', 'Profitability views'].map((step) => (
              <li key={step} className="flex gap-2 border-l-2 border-[#FFCB05] pl-4">
                {step}
              </li>
            ))}
          </ul>
        </div>
        <p className="mt-6 text-xs text-zinc-500">Demo values on marketing pages only.</p>
      </TourSection>

      <TourSection id="fleet" title="Fleet, inventory, and branches.">
        <div className="mkt-scroll-x">
          {['Vehicles', 'Maintenance', 'Warehouses', 'Inventory', 'Branches'].map((m) => (
            <div key={m} className="rounded-2xl border border-zinc-200 bg-white p-6 shadow-sm">
              <p className="text-lg font-semibold text-zinc-900">{m}</p>
              <div className="mt-4 h-28 rounded-lg bg-zinc-100" />
              <p className="mt-2 text-xs text-zinc-500">Plan-gated module</p>
            </div>
          ))}
        </div>
      </TourSection>

      <TourSection id="network" dark title="Your network when you need capacity.">
        <MarketingMarketplaceFlow />
      </TourSection>

      <TourSection id="developers" title="Built to connect.">
        <MarketingApiPreview />
        <Link to="/developers" className="mt-6 inline-block text-sm font-semibold text-zinc-900 underline">
          Developer documentation
        </Link>
      </TourSection>

      <MarketingCtaBand />
    </div>
  )
}
