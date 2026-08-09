import { usePageMeta } from '@/hooks/use-page-meta'
import { MarketingPageShell } from '@/layouts/MarketingLayout'

const FAQ = [
  {
    q: 'What is DeliveryOS?',
    a: 'A multi-tenant SaaS platform for running delivery operations: dispatch, riders, tracking, customers, COD, billing, and optional fleet, inventory, and marketplace modules.',
  },
  {
    q: 'Who can use it?',
    a: 'Delivery companies, merchants that need deliveries, enterprise logistics teams, and riders (smartphone or button-phone channels).',
  },
  {
    q: 'Do riders need smartphones?',
    a: 'Smartphone riders use the DeliveryOS PWA. Button-phone riders can operate via SMS/USSD when your workspace and carrier integrations are configured—no app login required.',
  },
  {
    q: 'Does DeliveryOS support GPS?',
    a: 'Yes, for smartphone riders during active delivery operations, subject to plan features and device permissions.',
  },
  {
    q: 'Can merchants request delivery companies?',
    a: 'Yes, via marketplace workflows when enabled for merchant and provider workspaces.',
  },
  {
    q: 'How does the 7-day trial work?',
    a: 'New company and merchant workspaces receive a trial period on signup. Operational limits follow your subscription rules after trial.',
  },
  {
    q: 'Does it support MTN Mobile Money?',
    a: 'Not yet. Mobile Money is planned as a future integration—UI may show “Coming soon” until APIs are configured and tested.',
  },
  {
    q: 'Is SMS/USSD available?',
    a: 'The product is designed to support operational SMS and USSD. Production use requires Supabase/auth SMS for login and operational carrier configuration—verify on staging before launch.',
  },
  {
    q: 'Can businesses use their own riders?',
    a: 'Yes. You create rider records, assign jobs, and onboard smartphone or button-phone riders under your company workspace.',
  },
  {
    q: 'Can DeliveryOS integrate with websites or apps?',
    a: 'Yes, via REST API and webhooks on eligible plans.',
  },
  {
    q: 'How is company data protected?',
    a: 'PostgreSQL Row Level Security, role-based access, tenant-scoped RPCs, and private storage. See the Security page for details.',
  },
]

export function FaqPage() {
  usePageMeta({ title: 'FAQ', path: '/faq' })
  return (
    <MarketingPageShell className="py-16 max-w-3xl">
      <h1 className="text-4xl font-semibold tracking-tight text-zinc-900">FAQ</h1>
      <dl className="mt-10 space-y-8">
        {FAQ.map((item) => (
          <div key={item.q}>
            <dt className="text-lg font-semibold text-zinc-900">{item.q}</dt>
            <dd className="mt-2 text-zinc-600">{item.a}</dd>
          </div>
        ))}
      </dl>
    </MarketingPageShell>
  )
}
