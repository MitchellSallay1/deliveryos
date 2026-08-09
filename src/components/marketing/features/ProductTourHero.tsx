import { Link } from 'react-router-dom'
import { HeroControlTower } from '@/components/marketing/hero/HeroControlTower'
import {
  HERO_TOUR_NOTIFICATIONS,
  HeroNotificationStack,
} from '@/components/marketing/hero/HeroNotificationStack'
import { RiderPhonePreview } from '@/components/marketing/hero/RiderPhonePreview'
import { MARKETING_CTA_TRIAL } from '@/lib/marketing-cta'
import { Button } from '@/components/ui/Button'

const HERO_PERSON = '/marketing/african-woman-phone.png'

export function ProductTourHero() {
  return (
    <section
      id="product-tour"
      className="scroll-mt-[72px] relative overflow-hidden bg-[#11110F] pb-14 pt-8 sm:pb-20 sm:pt-10"
    >
      <div
        className="pointer-events-none absolute inset-0 opacity-70"
        aria-hidden
        style={{
          background:
            'radial-gradient(ellipse 55% 45% at 72% 42%, rgba(255, 203, 5, 0.07), transparent 55%), radial-gradient(ellipse 40% 50% at 12% 70%, rgba(120, 72, 32, 0.28), transparent 60%)',
        }}
      />
      <div
        className="pointer-events-none absolute inset-0 opacity-[0.06]"
        aria-hidden
        style={{
          backgroundImage: `url("data:image/svg+xml,%3Csvg width='60' height='60' xmlns='http://www.w3.org/2000/svg'%3E%3Cpath d='M0 30h60M30 0v60' stroke='%23fff' stroke-width='0.5' fill='none'/%3E%3C/svg%3E")`,
        }}
      />

      <div className="relative mx-auto max-w-[1440px] px-4 sm:px-6 lg:px-8">
        <p className="text-xs font-semibold uppercase tracking-[0.2em] text-[#FFCB05]">Product tour</p>
        <h1 className="mkt-product-tour-headline mt-4 max-w-4xl text-white">
          Your entire delivery operation.
          <span className="mt-1 block text-[#FFCB05]">One live command center.</span>
        </h1>
        <p className="mt-5 max-w-2xl text-base leading-relaxed text-[#A5A5A5] sm:text-lg">
          See every rider, every delivery, and every payment—in real time. From dispatch to COD reconciliation, watch
          how DeliveryOS keeps the whole network in sync.
        </p>
        <div className="mt-8 flex flex-wrap gap-3">
          <Link to="/register">
            <Button variant="accent" type="button" className="h-11 rounded-xl px-6">
              {MARKETING_CTA_TRIAL}
            </Button>
          </Link>
          <Link to="/contact">
            <Button
              variant="outline"
              type="button"
              className="h-11 rounded-xl border-zinc-600 bg-transparent px-6 text-white hover:bg-white/10"
            >
              Talk to sales
            </Button>
          </Link>
        </div>

        <div className="relative mt-12 lg:mt-14">
          <div className="grid items-end gap-6 lg:grid-cols-[minmax(0,3fr)_minmax(0,7fr)] lg:gap-2 xl:gap-4">
            <div className="relative z-20 mx-auto w-full max-w-[340px] lg:mx-0 lg:max-w-none lg:-mr-6 xl:-mr-10">
              <div className="relative">
                <img
                  src={HERO_PERSON}
                  alt="Logistics professional reviewing live deliveries on DeliveryOS"
                  className="relative z-10 mx-auto h-auto max-h-[380px] w-full object-contain object-bottom drop-shadow-[0_28px_56px_rgba(0,0,0,0.55)] sm:max-h-[440px] lg:max-h-[520px] lg:object-left-bottom"
                  width={480}
                  height={640}
                  loading="eager"
                  decoding="async"
                />
                <div className="absolute bottom-[8%] right-[4%] z-20 sm:bottom-[10%] sm:right-[6%] lg:bottom-[12%] lg:right-[2%]">
                  <RiderPhonePreview />
                </div>
                <div
                  className="pointer-events-none absolute inset-y-[15%] right-0 z-[15] hidden w-24 bg-gradient-to-l from-[#11110F]/80 to-transparent lg:block"
                  aria-hidden
                />
              </div>
            </div>

            <div className="relative z-10 min-w-0 lg:-ml-4 xl:-ml-6">
              <HeroControlTower prominent className="w-full min-w-0 lg:origin-bottom-left lg:scale-[1.03]" />
            </div>
          </div>

          <HeroNotificationStack
            cards={HERO_TOUR_NOTIFICATIONS}
            showDemoLabel={false}
            className="pointer-events-none absolute left-1/2 top-[8%] z-30 hidden -translate-x-1/2 lg:flex xl:left-[34%] xl:top-[12%] xl:translate-x-0"
          />
          <HeroNotificationStack
            cards={HERO_TOUR_NOTIFICATIONS}
            showDemoLabel={false}
            className="relative z-30 mx-auto mt-6 flex max-w-[260px] lg:hidden"
          />
        </div>
      </div>
    </section>
  )
}
