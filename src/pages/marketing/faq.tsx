import { usePageMeta } from '@/hooks/use-page-meta'
import { getPageHeadData } from '@/lib/seo/page-head'
import { MarketingPageShell } from '@/layouts/MarketingLayout'
import { FAQ_ITEMS } from './faq-content'

export function FaqPage() {
  usePageMeta(getPageHeadData('faq'))
  return (
    <MarketingPageShell className="py-16 max-w-3xl">
      <h1 className="text-4xl font-semibold tracking-tight text-zinc-900">FAQ</h1>
      <dl className="mt-10 space-y-8">
        {FAQ_ITEMS.map((item) => (
          <div key={item.q}>
            <dt className="text-lg font-semibold text-zinc-900">{item.q}</dt>
            <dd className="mt-2 text-zinc-600">{item.a}</dd>
          </div>
        ))}
      </dl>
    </MarketingPageShell>
  )
}
