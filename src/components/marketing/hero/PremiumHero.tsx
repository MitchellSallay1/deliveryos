import { Link } from 'react-router-dom'
import { ArrowRight, Play } from 'lucide-react'
import { HeroControlTower } from '@/components/marketing/hero/HeroControlTower'
import { HeroNotificationStack } from '@/components/marketing/hero/HeroNotificationStack'
import {
  MARKETING_CTA_EXPLORE,
  MARKETING_EXPLORE_HREF,
  MARKETING_CTA_TRIAL,
  MARKETING_TRIAL_FOOTNOTE,
} from '@/lib/marketing-cta'

const HERO_PERSON = '/marketing/african-woman-phone.png'

export function PremiumHero() {
  return (
    <section className="relative min-h-[760px] overflow-hidden bg-[#11110F] pb-24 pt-4 lg:min-h-[880px] lg:pb-32">
      {/* Background */}
      <div className="pointer-events-none absolute inset-0 bg-[#11110F]" aria-hidden />
      <div
        className="pointer-events-none absolute inset-0 opacity-60"
        style={{
          background:
            'radial-gradient(ellipse 70% 55% at 55% 45%, rgba(120, 72, 32, 0.35), transparent 65%), radial-gradient(ellipse 40% 30% at 20% 80%, rgba(255, 203, 5, 0.08), transparent)',
        }}
      />
      <div
        className="pointer-events-none absolute inset-0 opacity-[0.07]"
        style={{
          backgroundImage: `url("data:image/svg+xml,%3Csvg width='60' height='60' xmlns='http://www.w3.org/2000/svg'%3E%3Cpath d='M0 30h60M30 0v60' stroke='%23fff' stroke-width='0.5' fill='none'/%3E%3C/svg%3E")`,
        }}
      />

      <p
        className="pointer-events-none absolute left-3 top-1/2 hidden -translate-y-1/2 text-[10px] uppercase tracking-[0.35em] text-zinc-600 [writing-mode:vertical-rl] xl:left-6 xl:block"
        aria-hidden
      >
        Built for Africa · Built for growth
      </p>

      <div className="relative mx-auto max-w-[1440px] px-4 sm:px-6 lg:px-8">
        <div className="grid items-end gap-8 lg:grid-cols-12 lg:gap-4 xl:gap-6">
          <div className="relative z-20 order-1 lg:col-span-4 xl:col-span-4">
            <div className="mb-4 flex items-center gap-2 text-xs text-zinc-400">
              <span className="font-semibold text-white">DeliveryOS</span>
              <span className="text-zinc-600">·</span>
              <span>
                Powered by <span className="font-semibold text-[#FFCB05]">MTN</span>
              </span>
            </div>
            <span className="inline-flex items-center gap-1.5 rounded-full border border-white/10 bg-white/5 px-3 py-1 text-[11px] text-zinc-300">
              <span className="text-[#FFCB05]">✦</span> The operating system for modern delivery
            </span>
            <h1 className="mkt-hero-headline mt-6 text-white">
              Run every delivery.
              <span className="mt-1 block">
                From <span className="text-[#FFCB05]">one</span>
              </span>
              <span className="block text-[#FFCB05]">operating system.</span>
            </h1>
            <p className="mt-5 max-w-md text-sm leading-relaxed text-[#A5A5A5] sm:text-base">
              Dispatch riders, track deliveries, manage customers, reconcile cash, operate fleets, and connect delivery
              partners — from one platform.
            </p>
            <div className="mt-8 flex flex-wrap items-center gap-3">
              <Link
                to="/register"
                className="inline-flex h-12 items-center gap-2 rounded-xl bg-[#FFCB05] px-6 text-sm font-semibold text-black transition hover:brightness-105"
              >
                {MARKETING_CTA_TRIAL}
                <ArrowRight className="h-4 w-4" />
              </Link>
              <Link
                to={MARKETING_EXPLORE_HREF}
                className="inline-flex h-12 items-center gap-2 rounded-xl border border-white/20 bg-white/5 px-5 text-sm font-semibold text-white backdrop-blur-sm transition hover:bg-white/10"
              >
                <Play className="h-4 w-4 fill-white" />
                {MARKETING_CTA_EXPLORE}
              </Link>
            </div>
            <p className="mt-4 flex items-center gap-2 text-xs text-zinc-500">
              <span className="text-emerald-500">✓</span> {MARKETING_TRIAL_FOOTNOTE} Cancel anytime.
            </p>
          </div>

          <div className="relative z-10 order-2 flex justify-center lg:order-2 lg:col-span-3 xl:col-span-3">
            <div className="relative w-full max-w-[280px] sm:max-w-[320px] lg:max-w-none">
              <img
                src={HERO_PERSON}
                alt=""
                className="relative z-10 mx-auto h-auto max-h-[420px] w-full object-contain object-bottom drop-shadow-[0_24px_48px_rgba(0,0,0,0.5)] lg:max-h-[520px]"
                width={480}
                height={640}
                loading="eager"
                decoding="async"
              />
              <HeroNotificationStack className="absolute -right-2 top-[18%] z-20 hidden sm:flex lg:-right-8 xl:-right-12" />
            </div>
          </div>

          <div className="relative z-10 order-3 lg:order-3 lg:col-span-5 xl:col-span-5">
            <HeroControlTower className="w-full min-w-0" />
            <HeroNotificationStack className="mt-4 flex sm:hidden" />
          </div>
        </div>
      </div>
    </section>
  )
}
