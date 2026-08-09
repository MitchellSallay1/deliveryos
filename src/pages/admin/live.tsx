import type { ReactNode } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { useLiveSnapshot } from '@/hooks/use-admin-platform'

export function AdminLivePage() {
  const { data, isLoading, error } = useLiveSnapshot(true)

  const deliveries = (data?.deliveries ?? {}) as Record<string, number>
  const riders = (data?.riders ?? {}) as Record<string, number>
  const marketplace = (data?.marketplace ?? {}) as Record<string, number>
  const comms = (data?.communications ?? {}) as Record<string, number>

  return (
    <div className="space-y-6">
      {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading live snapshot…</p>}
      {error && (
        <p className="text-sm text-red-600">{error instanceof Error ? error.message : 'Failed'}</p>
      )}
      <div className="grid gap-4 lg:grid-cols-2">
        <Panel title="Live deliveries">
          <Grid stats={deliveries} />
        </Panel>
        <Panel title="Live riders">
          <Grid stats={riders} />
        </Panel>
        <Panel title="Live marketplace">
          <Grid stats={marketplace} />
        </Panel>
        <Panel title="Communications queues">
          <Grid stats={comms} />
        </Panel>
      </div>
      <p className="text-xs text-[var(--color-muted)]">Auto-refresh every 15 seconds. Aggregates only.</p>
    </div>
  )
}

function Panel({ title, children }: { title: string; children: ReactNode }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">{title}</CardTitle>
      </CardHeader>
      <CardContent>{children}</CardContent>
    </Card>
  )
}

function Grid({ stats }: { stats: Record<string, number> }) {
  const entries = Object.entries(stats)
  if (!entries.length) return <p className="text-sm text-[var(--color-muted)]">No data</p>
  return (
    <dl className="grid grid-cols-2 gap-3">
      {entries.map(([k, v]) => (
        <div key={k} className="rounded-lg bg-zinc-50 p-3">
          <dt className="text-xs capitalize text-[var(--color-muted)]">{k.replace(/_/g, ' ')}</dt>
          <dd className="text-2xl font-semibold tabular-nums">{v}</dd>
        </div>
      ))}
    </dl>
  )
}
