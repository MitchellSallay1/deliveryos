import { Link } from 'react-router-dom'
import { usePageMeta } from '@/hooks/use-page-meta'
import { getPageHeadData } from '@/lib/seo/page-head'
import { MarketingPageShell } from '@/layouts/MarketingLayout'

export function DevelopersPage() {
  usePageMeta(getPageHeadData('developers'))
  return (
    <MarketingPageShell className="py-16 max-w-3xl">
      <h1 className="text-4xl font-semibold tracking-tight text-zinc-900">Developers</h1>
      <p className="mt-4 text-lg text-zinc-600">
        Integrate order flows, tracking, and events with DeliveryOS API and webhooks.
      </p>
      <ul className="mt-8 list-disc space-y-2 pl-5 text-zinc-700">
        <li>
          REST API v1 via Edge function — see <code className="text-sm">docs/API.md</code> in the repository.
        </li>
        <li>Webhook signatures and event catalog — see <code className="text-sm">docs/WEBHOOKS.md</code>.</li>
        <li>API access is plan-gated in PostgreSQL.</li>
      </ul>
      <Link to="/register" className="mt-8 inline-block text-sm font-semibold text-zinc-900 underline">
        Create a workspace to generate API keys
      </Link>
    </MarketingPageShell>
  )
}

export function PartnersPage() {
  usePageMeta(getPageHeadData('partners'))
  return (
    <MarketingPageShell className="py-16 max-w-3xl">
      <h1 className="text-4xl font-semibold tracking-tight text-zinc-900">Partners</h1>
      <p className="mt-4 text-lg text-zinc-600">
        DeliveryOS is presented with MTN as the strategic network partner for SMS, USSD, and future Mobile Money.
      </p>
      <p className="mt-4 text-zinc-600">
        Additional carrier and technology partnerships can be discussed via{' '}
        <Link to="/contact" className="underline">
          contact sales
        </Link>
        .
      </p>
    </MarketingPageShell>
  )
}
