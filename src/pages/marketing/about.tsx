import { usePageMeta } from '@/hooks/use-page-meta'
import { getPageHeadData } from '@/lib/seo/page-head'
import { MarketingCtaBand, MarketingPageShell } from '@/layouts/MarketingLayout'

export function AboutPage() {
  usePageMeta(getPageHeadData('about'))
  return (
    <>
      <MarketingPageShell className="py-16 prose-zinc max-w-3xl">
        <h1 className="text-4xl font-semibold tracking-tight text-zinc-900">About DeliveryOS</h1>
        <p className="mt-6 text-lg text-zinc-600">
          DeliveryOS is the operating system for modern delivery businesses—a multi-tenant platform for dispatch,
          riders, customers, payments, tracking, and logistics operations.
        </p>
        <h2 className="mt-10 text-2xl font-semibold text-zinc-900">Mission</h2>
        <p className="mt-3 text-zinc-600">
          Make modern logistics technology accessible to delivery operators and the businesses they serve—without
          forcing teams to stitch together spreadsheets, chat apps, and single-purpose tools.
        </p>
        <h2 className="mt-10 text-2xl font-semibold text-zinc-900">Partner presentation</h2>
        <p className="mt-3 text-zinc-600">
          This deployment is presented as <strong>DeliveryOS, powered by MTN</strong>. MTN is the strategic technology
          and network partner for SMS, USSD, and future Mobile Money integrations when configured and tested.
        </p>
      </MarketingPageShell>
      <MarketingCtaBand />
    </>
  )
}
