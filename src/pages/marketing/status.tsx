import { usePageMeta } from '@/hooks/use-page-meta'
import { getPageHeadData } from '@/lib/seo/page-head'
import { MarketingPageShell } from '@/layouts/MarketingLayout'
import { Badge } from '@/components/ui/Badge'

type StatusRow = { name: string; status: 'operational' | 'not_enabled' | 'degraded' }

const ROWS: StatusRow[] = [
  { name: 'DeliveryOS Platform (app)', status: 'operational' },
  { name: 'Authentication (phone OTP)', status: 'not_enabled' },
  { name: 'Database', status: 'operational' },
  { name: 'Operational SMS', status: 'not_enabled' },
  { name: 'USSD', status: 'not_enabled' },
  { name: 'Mobile Money', status: 'not_enabled' },
  { name: 'API', status: 'operational' },
  { name: 'Webhooks', status: 'operational' },
]

function StatusPill({ status }: { status: StatusRow['status'] }) {
  if (status === 'operational') return <Badge variant="success">Operational</Badge>
  if (status === 'degraded') return <Badge variant="warning">Degraded</Badge>
  return <Badge variant="outline">Not yet enabled</Badge>
}

export function StatusPage() {
  usePageMeta(getPageHeadData('status'))
  return (
    <MarketingPageShell className="py-16 max-w-2xl">
      <h1 className="text-4xl font-semibold tracking-tight text-zinc-900">Service status</h1>
      <p className="mt-4 text-zinc-600">
        Component statuses reflect product readiness—not live monitoring. Connect observability for production SLOs.
      </p>
      <ul className="mt-10 divide-y divide-zinc-200 rounded-xl border border-zinc-200">
        {ROWS.map((row) => (
          <li key={row.name} className="flex items-center justify-between px-4 py-4">
            <span className="font-medium text-zinc-900">{row.name}</span>
            <StatusPill status={row.status} />
          </li>
        ))}
      </ul>
      <p className="mt-6 text-xs text-zinc-500">
        Auth SMS and MTN integrations show &quot;Not yet enabled&quot; until configured and verified in your environment.
      </p>
    </MarketingPageShell>
  )
}
