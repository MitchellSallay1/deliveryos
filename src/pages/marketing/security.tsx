import { usePageMeta } from '@/hooks/use-page-meta'
import { getPageHeadData } from '@/lib/seo/page-head'
import { MarketingPageShell } from '@/layouts/MarketingLayout'

export function SecurityPage() {
  usePageMeta(getPageHeadData('security'))
  return (
    <MarketingPageShell className="py-16 max-w-3xl">
      <h1 className="text-4xl font-semibold tracking-tight text-zinc-900">Security</h1>
      <p className="mt-4 text-lg text-zinc-600">
        DeliveryOS is built for multi-tenant logistics. This overview is for customers—not a certification claim.
      </p>
      <ul className="mt-10 space-y-6 text-zinc-700">
        <li>
          <strong className="text-zinc-900">Tenant separation.</strong> Each company workspace is isolated with PostgreSQL
          Row Level Security and server-side checks on every sensitive RPC.
        </li>
        <li>
          <strong className="text-zinc-900">Authentication.</strong> Phone OTP via Supabase Auth; sessions use industry-standard JWTs.
        </li>
        <li>
          <strong className="text-zinc-900">Role-based access.</strong> Owners, dispatchers, support staff, and riders see only what their role allows.
        </li>
        <li>
          <strong className="text-zinc-900">Audit trails.</strong> Platform and workspace audit events for operational accountability.
        </li>
        <li>
          <strong className="text-zinc-900">Private storage.</strong> Delivery photos and assets use scoped storage policies.
        </li>
        <li>
          <strong className="text-zinc-900">API keys.</strong> Hashed verification server-side; never exposed in the browser bundle.
        </li>
        <li>
          <strong className="text-zinc-900">Webhooks.</strong> Signed payloads for verified integrations.
        </li>
      </ul>
      <p className="mt-10 text-sm text-zinc-500">
        DeliveryOS does not claim PCI DSS, ISO 27001, SOC 2, or GDPR certification unless separately documented by your
        organization after legal review.
      </p>
    </MarketingPageShell>
  )
}
