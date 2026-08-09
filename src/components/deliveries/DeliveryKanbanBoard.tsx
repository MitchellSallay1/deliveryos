import { memo, useMemo } from 'react'
import { Link } from 'react-router-dom'
import { GripVertical } from 'lucide-react'
import type { DeliveryRow, RiderRow } from '@/types/delivery'
import type { DeliveryStatus } from '@/types/supabase'
import { KANBAN_STATUSES, statusStyle } from '@/design-system/delivery-status'
import { formatLrdFromCents, NEXT_STATUS } from '@/utils/delivery-schemas'
import { Badge } from '@/components/ui/Badge'
import { cn } from '@/lib/utils'

function initials(name: string) {
  return name
    .split(/\s+/)
    .slice(0, 2)
    .map((p) => p[0]?.toUpperCase() ?? '')
    .join('')
}

function canDropToStatus(from: DeliveryStatus, to: DeliveryStatus): boolean {
  if (from === to) return true
  if (from === 'pending') return false
  const next = NEXT_STATUS[from] ?? []
  return next.includes(to)
}

type DeliveryKanbanBoardProps = {
  deliveries: DeliveryRow[]
  riderMap: Map<string, RiderRow>
  onSelect: (d: DeliveryRow) => void
  onMove: (deliveryId: string, status: DeliveryStatus) => void
}

export const DeliveryKanbanBoard = memo(function DeliveryKanbanBoard({
  deliveries,
  riderMap,
  onSelect,
  onMove,
}: DeliveryKanbanBoardProps) {
  const byStatus = useMemo(() => {
    const map = new Map<DeliveryStatus, DeliveryRow[]>()
    for (const s of KANBAN_STATUSES) map.set(s, [])
    for (const d of deliveries) {
      const list = map.get(d.status as DeliveryStatus)
      if (list) list.push(d)
    }
    return map
  }, [deliveries])

  return (
    <div className="flex gap-3 overflow-x-auto pb-2">
      {KANBAN_STATUSES.map((status) => {
        const col = statusStyle(status)
        const items = byStatus.get(status) ?? []
        return (
          <div
            key={status}
            className={cn('flex w-72 shrink-0 flex-col rounded-xl border', col.column)}
            onDragOver={(e) => {
              e.preventDefault()
              e.dataTransfer.dropEffect = 'move'
            }}
            onDrop={(e) => {
              e.preventDefault()
              const id = e.dataTransfer.getData('text/delivery-id')
              const from = e.dataTransfer.getData('text/delivery-status') as DeliveryStatus
              if (!id || !from) return
              if (canDropToStatus(from, status)) onMove(id, status)
            }}
          >
            <div className="flex items-center justify-between border-b border-inherit px-3 py-2">
              <div className="flex items-center gap-2">
                <span className={cn('h-2 w-2 rounded-full', col.dot)} />
                <span className="text-xs font-semibold uppercase tracking-wide">{col.label}</span>
              </div>
              <Badge variant="outline">{items.length}</Badge>
            </div>
            <div className="flex max-h-[min(70vh,640px)] flex-col gap-2 overflow-y-auto p-2">
              {items.map((d) => (
                <KanbanCard
                  key={d.id}
                  delivery={d}
                  riderLabel={d.rider_id ? riderMap.get(d.rider_id)?.rider_code : undefined}
                  onSelect={() => onSelect(d)}
                />
              ))}
              {items.length === 0 && (
                <p className="px-2 py-6 text-center text-xs text-[var(--color-muted)]">No deliveries</p>
              )}
            </div>
          </div>
        )
      })}
    </div>
  )
})

function KanbanCard({
  delivery: d,
  riderLabel,
  onSelect,
}: {
  delivery: DeliveryRow
  riderLabel?: string
  onSelect: () => void
}) {
  const cod = d.amount_to_collect_lrd_cents > 0

  return (
    <article
      draggable={d.status !== 'pending'}
      onDragStart={(e) => {
        e.dataTransfer.setData('text/delivery-id', d.id)
        e.dataTransfer.setData('text/delivery-status', d.status)
      }}
      className="group cursor-grab rounded-lg border bg-white p-3 shadow-sm transition-shadow hover:shadow-md active:cursor-grabbing"
      onClick={onSelect}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault()
          onSelect()
        }
      }}
      role="button"
      tabIndex={0}
    >
      <div className="flex items-start gap-2">
        <GripVertical className="mt-0.5 h-4 w-4 shrink-0 text-zinc-300 opacity-0 group-hover:opacity-100" aria-hidden />
        <div className="flex min-w-0 flex-1 gap-2">
          <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-zinc-100 text-xs font-semibold">
            {initials(d.customer_name)}
          </span>
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-medium">{d.customer_name}</p>
            <Link
              to={`/track/${d.tracking_code}`}
              className="text-xs text-[var(--color-muted)] hover:text-[var(--color-foreground)]"
              onClick={(e) => e.stopPropagation()}
              target="_blank"
            >
              {d.tracking_code}
            </Link>
          </div>
        </div>
      </div>
      <p className="mt-2 line-clamp-2 text-xs text-[var(--color-muted)]">{d.destination_address}</p>
      <div className="mt-2 flex flex-wrap gap-1">
        {cod && <Badge variant="warning">COD {formatLrdFromCents(d.amount_to_collect_lrd_cents)}</Badge>}
        {riderLabel && <Badge variant="outline">Rider {riderLabel}</Badge>}
      </div>
    </article>
  )
}
