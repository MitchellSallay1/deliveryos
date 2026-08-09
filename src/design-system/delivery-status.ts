import type { DeliveryStatus } from '@/types/supabase'

export const KANBAN_STATUSES: DeliveryStatus[] = [
  'pending',
  'assigned',
  'accepted',
  'picked_up',
  'in_transit',
  'delivered',
  'failed',
  'cancelled',
]

type StatusStyle = {
  label: string
  badge: string
  dot: string
  column: string
}

export const deliveryStatusStyles: Record<DeliveryStatus, StatusStyle> = {
  pending: {
    label: 'Pending',
    badge: 'bg-slate-100 text-slate-800 ring-slate-200',
    dot: 'bg-slate-400',
    column: 'border-slate-200 bg-slate-50/50',
  },
  assigned: {
    label: 'Assigned',
    badge: 'bg-blue-50 text-blue-900 ring-blue-100',
    dot: 'bg-blue-500',
    column: 'border-blue-100 bg-blue-50/30',
  },
  accepted: {
    label: 'Accepted',
    badge: 'bg-indigo-50 text-indigo-900 ring-indigo-100',
    dot: 'bg-indigo-500',
    column: 'border-indigo-100 bg-indigo-50/30',
  },
  picked_up: {
    label: 'Picked up',
    badge: 'bg-violet-50 text-violet-900 ring-violet-100',
    dot: 'bg-violet-500',
    column: 'border-violet-100 bg-violet-50/30',
  },
  in_transit: {
    label: 'In transit',
    badge: 'bg-amber-50 text-amber-950 ring-amber-100',
    dot: 'bg-amber-500',
    column: 'border-amber-100 bg-amber-50/30',
  },
  delivered: {
    label: 'Delivered',
    badge: 'bg-emerald-50 text-emerald-900 ring-emerald-100',
    dot: 'bg-emerald-500',
    column: 'border-emerald-100 bg-emerald-50/30',
  },
  failed: {
    label: 'Failed',
    badge: 'bg-red-50 text-red-900 ring-red-100',
    dot: 'bg-red-500',
    column: 'border-red-100 bg-red-50/30',
  },
  cancelled: {
    label: 'Cancelled',
    badge: 'bg-neutral-100 text-neutral-600 ring-neutral-200',
    dot: 'bg-neutral-400',
    column: 'border-neutral-200 bg-neutral-50/50',
  },
}

export function statusStyle(status: string): StatusStyle {
  return (
    deliveryStatusStyles[status as DeliveryStatus] ?? deliveryStatusStyles.pending
  )
}
