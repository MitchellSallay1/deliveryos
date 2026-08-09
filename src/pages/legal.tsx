import { MarketingPageShell } from '@/layouts/MarketingLayout'
import { usePageMeta } from '@/hooks/use-page-meta'

function LegalNotice() {
  return (
    <p className="rounded-lg border border-amber-200 bg-amber-50 p-4 text-sm text-amber-950">
      <strong>Draft for legal review.</strong> This text is a structural placeholder. Qualified legal counsel must
      approve all terms and privacy content before production launch. Do not rely on this copy for compliance.
    </p>
  )
}

export function TermsPage() {
  usePageMeta({ title: 'Terms of Service', path: '/terms' })
  return (
    <MarketingPageShell className="py-16 max-w-3xl">
      <h1 className="text-4xl font-semibold tracking-tight text-zinc-900">Terms of Service</h1>
      <div className="mt-6 space-y-8 text-sm text-zinc-700">
        <LegalNotice />
        <section>
          <h2 className="text-lg font-semibold text-zinc-900">1. Acceptance</h2>
          <p className="mt-2">By accessing DeliveryOS you agree to these terms. If you use the service on behalf of an organization, you represent that you have authority to bind that organization.</p>
        </section>
        <section>
          <h2 className="text-lg font-semibold text-zinc-900">2. Account responsibilities</h2>
          <p className="mt-2">You are responsible for safeguarding access to your workspace, accurate company information, and actions taken by users you invite.</p>
        </section>
        <section>
          <h2 className="text-lg font-semibold text-zinc-900">3. Subscriptions & free trial</h2>
          <p className="mt-2">Plans, limits, and trial periods are described at signup and in your workspace billing area. After trial, continued use may require a paid plan.</p>
        </section>
        <section>
          <h2 className="text-lg font-semibold text-zinc-900">4. Permitted use</h2>
          <p className="mt-2">Use DeliveryOS only for lawful logistics and delivery operations. Do not abuse SMS, API, or authentication systems.</p>
        </section>
        <section>
          <h2 className="text-lg font-semibold text-zinc-900">5. Delivery provider responsibility</h2>
          <p className="mt-2">DeliveryOS provides software. Your company remains responsible for deliveries, rider safety, customer communication, and regulatory obligations in your markets.</p>
        </section>
        <section>
          <h2 className="text-lg font-semibold text-zinc-900">6. Marketplace relationships</h2>
          <p className="mt-2">Marketplace features connect merchants and providers. Contractual terms between parties may apply outside this software agreement.</p>
        </section>
        <section>
          <h2 className="text-lg font-semibold text-zinc-900">7. Payments</h2>
          <p className="mt-2">Subscription and payment terms are as presented in product billing flows. Third-party payment integrations may add separate terms when enabled.</p>
        </section>
        <section>
          <h2 className="text-lg font-semibold text-zinc-900">8. Data</h2>
          <p className="mt-2">See the Privacy Policy for data handling. You retain responsibility for customer consents required in your jurisdiction.</p>
        </section>
        <section>
          <h2 className="text-lg font-semibold text-zinc-900">9. Availability</h2>
          <p className="mt-2">We strive for reliable service but do not guarantee uninterrupted availability. Maintenance and third-party outages may occur.</p>
        </section>
        <section>
          <h2 className="text-lg font-semibold text-zinc-900">10. Termination</h2>
          <p className="mt-2">Either party may terminate use according to subscription terms. We may suspend accounts for abuse or non-payment.</p>
        </section>
        <section>
          <h2 className="text-lg font-semibold text-zinc-900">11. Liability</h2>
          <p className="mt-2">To the extent permitted by law, liability is limited as set forth in your master agreement with the service provider. This placeholder must be replaced by counsel.</p>
        </section>
        <section>
          <h2 className="text-lg font-semibold text-zinc-900">12. Changes</h2>
          <p className="mt-2">We may update these terms. Material changes should be communicated to workspace owners.</p>
        </section>
        <section>
          <h2 className="text-lg font-semibold text-zinc-900">13. Contact</h2>
          <p className="mt-2">Contact us via the marketing contact page for legal or commercial inquiries.</p>
        </section>
      </div>
    </MarketingPageShell>
  )
}

export function PrivacyPage() {
  usePageMeta({ title: 'Privacy Policy', path: '/privacy' })
  return (
    <MarketingPageShell className="py-16 max-w-3xl">
      <h1 className="text-4xl font-semibold tracking-tight text-zinc-900">Privacy Policy</h1>
      <div className="mt-6 space-y-8 text-sm text-zinc-700">
        <LegalNotice />
        <section>
          <h2 className="text-lg font-semibold text-zinc-900">Information we process</h2>
          <ul className="mt-2 list-disc pl-5 space-y-1">
            <li>Account information (name, phone, optional email)</li>
            <li>Delivery and customer information (names, phones, addresses)</li>
            <li>GPS location samples during active delivery operations for smartphone riders</li>
            <li>Usage and audit logs for security and billing</li>
            <li>SMS/USSD interaction metadata when operational messaging is enabled</li>
          </ul>
        </section>
        <section>
          <h2 className="text-lg font-semibold text-zinc-900">Why we process it</h2>
          <p className="mt-2">To provide dispatch, tracking, notifications, billing, and security for your workspace.</p>
        </section>
        <section>
          <h2 className="text-lg font-semibold text-zinc-900">Retention</h2>
          <p className="mt-2">Retention follows operational and legal requirements documented in product runbooks. See <code>docs/DATA_RETENTION.md</code> for technical retention jobs.</p>
        </section>
        <section>
          <h2 className="text-lg font-semibold text-zinc-900">Security</h2>
          <p className="mt-2">Tenant isolation, encryption in transit, and access controls. See the Security page for a customer-facing summary.</p>
        </section>
        <section>
          <h2 className="text-lg font-semibold text-zinc-900">Third-party providers</h2>
          <p className="mt-2">Infrastructure (e.g. Supabase), hosting, and telecommunications providers process data as subprocessors when you use those features.</p>
        </section>
        <section>
          <h2 className="text-lg font-semibold text-zinc-900">Your choices</h2>
          <p className="mt-2">Workspace owners manage user access. Contact us for data subject requests according to applicable law after counsel review.</p>
        </section>
        <section>
          <h2 className="text-lg font-semibold text-zinc-900">Contact</h2>
          <p className="mt-2">Use the contact page for privacy inquiries.</p>
        </section>
        <p className="text-xs text-zinc-500">Operational GPS behavior: see <code>docs/GPS_AND_PRIVACY.md</code>.</p>
      </div>
    </MarketingPageShell>
  )
}
