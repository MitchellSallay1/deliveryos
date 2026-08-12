import { usePageMeta } from '@/hooks/use-page-meta'
import { getPageHeadData } from '@/lib/seo/page-head'
import { MarketingCtaBand, MarketingPageShell } from '@/layouts/MarketingLayout'

const SOLUTIONS = [
  { id: 'couriers', title: 'Delivery & courier companies', text: 'Run dispatch, riders, COD, and live operations from one control center.' },
  { id: 'merchants', title: 'Merchants without own riders', text: 'Request deliveries from logistics providers via marketplace workflows.' },
  { id: 'retail', title: 'Retail, pharmacy, restaurant, supermarket', text: 'Same-day delivery with customer tracking and proof of delivery.' },
  { id: 'enterprise', title: 'Enterprise logistics teams', text: 'Multi-branch operations, fleet, inventory, API integrations, and audit trails.' },
  { id: 'online', title: 'Online sellers', text: 'Connect order flows through API/webhooks and manage last-mile delivery.' },
]

export function SolutionsPage() {
  usePageMeta(getPageHeadData('solutions'))
  return (
    <>
      <MarketingPageShell className="py-16">
        <h1 className="text-4xl font-semibold tracking-tight text-zinc-900">Solutions</h1>
        <p className="mt-4 max-w-2xl text-lg text-zinc-600">
          Whether you operate a fleet or need deliveries fulfilled, DeliveryOS adapts to your role.
        </p>
        <div className="mt-12 grid gap-6 md:grid-cols-2">
          {SOLUTIONS.map((s) => (
            <article key={s.id} id={s.id} className="scroll-mt-24 rounded-xl border border-zinc-200 p-6 hover:shadow-md">
              <h2 className="text-xl font-semibold text-zinc-900">{s.title}</h2>
              <p className="mt-3 text-sm text-zinc-600">{s.text}</p>
            </article>
          ))}
        </div>
      </MarketingPageShell>
      <MarketingCtaBand />
    </>
  )
}
