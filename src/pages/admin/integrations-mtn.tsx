import { ShieldCheck } from 'lucide-react'
import { CommandCard, CommandCardBody, CommandCardHeader, SectionHeader, StatusChip } from '@/components/admin/control-tower'
import { MTN_READINESS_ITEMS } from '@/lib/admin-control-tower'
import { useExtendedHealth } from '@/hooks/use-admin-platform'

const EDGE_FUNCTIONS = [
  { name: 'sms-dispatch', note: 'Outbound SMS worker — provider-neutral, awaiting MTN credentials' },
  { name: 'sms-inbound', note: 'Inbound SMS/USSD command handler — provider-neutral fail-closed boundary in place' },
  { name: 'ussd-rider', note: 'USSD session handler — awaiting MTN USSD integration' },
  { name: 'webhooks-dispatch', note: 'Outbound webhook delivery worker — live, carrier-independent' },
  { name: 'email-dispatch', note: 'Outbound email worker — live, carrier-independent' },
  { name: 'jobs-scheduler', note: 'Scheduled maintenance jobs (trial expiry, subscription upkeep) — live' },
]

export function AdminMtnIntegrationsPage() {
  const { data } = useExtendedHealth(true)
  const dbStatus = (data?.database as { status?: string } | undefined)?.status

  return (
    <div className="space-y-8">
      <SectionHeader eyebrow="Integrations" title="MTN readiness" className="mb-0" />

      <CommandCard className="border-amber-400/20">
        <CommandCardBody>
          <p className="text-sm text-zinc-400">
            Readiness surface only. Nothing here makes a live call to MTN. Status reflects what has been built and
            deployed in DeliveryOS — not carrier confirmation. No secret values are ever shown on this page.
          </p>
        </CommandCardBody>
      </CommandCard>

      <section>
        <SectionHeader eyebrow="Channel readiness" />
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          {MTN_READINESS_ITEMS.map((item) => (
            <CommandCard key={item.key} className="p-4">
              <p className="text-sm font-medium text-zinc-200">{item.label}</p>
              <div className="mt-3">
                <StatusChip color="gray" label={item.status} />
              </div>
            </CommandCard>
          ))}
        </div>
      </section>

      <div className="grid gap-4 xl:grid-cols-2">
        <CommandCard>
          <CommandCardHeader
            title={
              <span className="inline-flex items-center gap-1.5">
                <ShieldCheck className="h-3.5 w-3.5 text-zinc-500" /> Webhook / carrier auth security boundary
              </span>
            }
          />
          <CommandCardBody className="space-y-2 text-sm text-zinc-400">
            <p>
              A provider-neutral, fail-closed carrier authentication boundary (
              <code className="text-zinc-300">supabase/functions/_shared/carrier-auth.ts</code>) is implemented and wired
              into the inbound SMS/USSD Edge Functions. It rejects any request that doesn't present a valid signature —
              there is no permissive fallback.
            </p>
            <p>
              It does not yet validate against a real MTN signature scheme because MTN has not provided one. Once MTN's
              specification is available, the concrete verifier plugs into this boundary without changing the
              fail-closed contract.
            </p>
          </CommandCardBody>
        </CommandCard>

        <CommandCard>
          <CommandCardHeader title="Edge Function status" description="Deployed in this repository" />
          <CommandCardBody>
            <ul className="space-y-2 text-sm">
              {EDGE_FUNCTIONS.map((fn) => (
                <li key={fn.name} className="flex items-start justify-between gap-3 border-b border-white/[0.05] pb-2 last:border-0 last:pb-0">
                  <div>
                    <p className="font-mono text-xs text-zinc-300">{fn.name}</p>
                    <p className="mt-0.5 text-xs text-zinc-500">{fn.note}</p>
                  </div>
                </li>
              ))}
            </ul>
            <p className="mt-3 text-xs text-zinc-600">
              Database connectivity used to serve this dashboard: <span className="text-zinc-400">{dbStatus ?? 'unknown'}</span>
            </p>
          </CommandCardBody>
        </CommandCard>
      </div>

      <CommandCard>
        <CommandCardHeader title="Required secrets" description="Presence only — values are never displayed" />
        <CommandCardBody>
          <p className="text-sm text-zinc-500">
            Not observable from this dashboard. Edge Function secret configuration lives in the Supabase project
            settings, not in the application database, so it cannot be queried or displayed here without a live
            probe — which this admin UX layer intentionally does not perform. Verify directly in the Supabase
            dashboard under Edge Functions → Secrets before enabling any MTN channel above.
          </p>
        </CommandCardBody>
      </CommandCard>
    </div>
  )
}
