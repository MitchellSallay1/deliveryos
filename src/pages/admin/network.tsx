import { useState } from 'react'
import { Link } from 'react-router-dom'
import {
  CommandButton,
  CommandCard,
  CommandCardHeader,
  CommandEmptyState,
  CommandKpi,
  CommandTable,
  CommandTableHead,
  CommandTd,
  CommandTh,
  CommandTr,
  SectionHeader,
} from '@/components/admin/control-tower'
import { formatPercent } from '@/lib/admin-control-tower'
import { useNetworkMetrics } from '@/hooks/use-admin-platform'

export function AdminNetworkPage() {
  const [days, setDays] = useState(7)
  const { data, isLoading } = useNetworkMetrics(days, true)
  const topCompanies = (data?.top_companies ?? []) as Array<{ id: string; name: string; deliveries: number }>

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <SectionHeader eyebrow="Network" title="Network metrics" className="mb-0" />
        <div className="flex gap-2">
          {[7, 30, 90].map((d) => (
            <CommandButton key={d} size="sm" variant={days === d ? 'primary' : 'outline'} onClick={() => setDays(d)}>
              {d} days
            </CommandButton>
          ))}
        </div>
      </div>

      {isLoading && <p className="text-sm text-zinc-500">Loading…</p>}

      {data && (
        <>
          <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
            <CommandKpi label="Delivery volume" value={String(data.delivery_volume ?? '—')} />
            <CommandKpi label="Completion rate" value={formatPercent(data.completion_rate as number | null)} />
            <CommandKpi label="Failed rate" value={formatPercent(data.failed_rate as number | null)} color={Number(data.failed_rate ?? 0) > 0.1 ? 'amber' : undefined} />
            <CommandKpi label="Avg delivery time" value={data.avg_delivery_minutes != null ? `${data.avg_delivery_minutes} min` : '—'} />
            <CommandKpi label="Active companies" value={String(data.active_companies ?? '—')} />
            <CommandKpi label="Active riders" value={String(data.active_riders ?? '—')} />
            <CommandKpi label="Marketplace acceptance" value={formatPercent(data.marketplace_acceptance_rate as number | null)} />
          </div>

          <CommandCard>
            <CommandCardHeader title="Top companies" description={`By delivery volume, last ${days} days`} />
            {topCompanies.length === 0 ? (
              <CommandEmptyState label="No delivery activity in this window." />
            ) : (
              <CommandTable>
                <CommandTableHead>
                  <CommandTh>Company</CommandTh>
                  <CommandTh className="text-right">Deliveries</CommandTh>
                </CommandTableHead>
                <tbody>
                  {topCompanies.map((c) => (
                    <CommandTr key={c.id}>
                      <CommandTd>
                        <Link to={`/admin/companies/${c.id}`} className="hover:text-white hover:underline">
                          {c.name}
                        </Link>
                      </CommandTd>
                      <CommandTd className="text-right font-medium tabular-nums text-zinc-100">{c.deliveries}</CommandTd>
                    </CommandTr>
                  ))}
                </tbody>
              </CommandTable>
            )}
          </CommandCard>
        </>
      )}
    </div>
  )
}
