import { useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { AdminHealthBadge } from '@/components/admin/AdminHealthBadge'
import { useCommunicationsSummary } from '@/hooks/use-admin-platform'

export function AdminCommunicationsPage() {
  const [days] = useState(7)
  const { data, isLoading } = useCommunicationsSummary(days, true)
  const sms = (data?.sms ?? {}) as Record<string, number>
  const email = (data?.email ?? {}) as Record<string, number>

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>MTN channels</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-wrap gap-2">
          <AdminHealthBadge level="not_configured" />
          <span className="text-sm text-[var(--color-muted)]">SMS / USSD — not verified in production</span>
        </CardContent>
      </Card>
      {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
      <div className="grid gap-4 md:grid-cols-2">
        <SummaryCard title="SMS" stats={sms} />
        <SummaryCard title="Email" stats={email} />
      </div>
      <p className="text-xs text-[var(--color-muted)]">Window: last {days} days. USSD session metrics require provider instrumentation.</p>
    </div>
  )
}

function SummaryCard({ title, stats }: { title: string; stats: Record<string, number> }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">{title}</CardTitle>
      </CardHeader>
      <CardContent>
        <dl className="grid grid-cols-2 gap-2 text-sm">
          {Object.entries(stats).map(([k, v]) => (
            <div key={k}>
              <dt className="text-xs capitalize text-[var(--color-muted)]">{k}</dt>
              <dd className="font-semibold tabular-nums">{v}</dd>
            </div>
          ))}
        </dl>
      </CardContent>
    </Card>
  )
}
