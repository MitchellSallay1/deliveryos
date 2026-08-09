import { useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { Button } from '@/components/ui/Button'
import { useNetworkMetrics } from '@/hooks/use-admin-platform'

export function AdminNetworkPage() {
  const [days, setDays] = useState(7)
  const { data, isLoading } = useNetworkMetrics(days, true)

  return (
    <div className="space-y-4">
      <div className="flex gap-2">
        {[7, 30, 90].map((d) => (
          <Button key={d} size="sm" variant={days === d ? 'accent' : 'outline'} onClick={() => setDays(d)}>
            {d} days
          </Button>
        ))}
      </div>
      {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
      {data && (
        <div className="grid gap-4 lg:grid-cols-2">
          <MetricCard title="Volume & quality" data={data} keys={['delivery_volume', 'completion_rate', 'failed_rate', 'avg_delivery_minutes']} />
          <MetricCard title="Network" data={data} keys={['active_companies', 'active_riders', 'marketplace_acceptance_rate']} />
          <Card className="lg:col-span-2">
            <CardHeader>
              <CardTitle className="text-base">Top companies</CardTitle>
            </CardHeader>
            <CardContent>
              <pre className="overflow-auto text-xs">{JSON.stringify(data.top_companies, null, 2)}</pre>
            </CardContent>
          </Card>
        </div>
      )}
    </div>
  )
}

function MetricCard({ title, data, keys }: { title: string; data: Record<string, unknown>; keys: string[] }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">{title}</CardTitle>
      </CardHeader>
      <CardContent>
        <dl className="space-y-2">
          {keys.map((k) => (
            <div key={k} className="flex justify-between text-sm">
              <dt className="capitalize text-[var(--color-muted)]">{k.replace(/_/g, ' ')}</dt>
              <dd className="font-medium tabular-nums">{String(data[k] ?? '—')}</dd>
            </div>
          ))}
        </dl>
      </CardContent>
    </Card>
  )
}
