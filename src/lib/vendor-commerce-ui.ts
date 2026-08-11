/**
 * Pure label/variant mapping for Commerce vendor-facing states. No fetching
 * here — these functions only label statuses the backend already computed
 * (store_profiles.status, products.status, commerce_orders.payment_status/
 * fulfillment_status), the same "the frontend never re-derives status, only
 * labels it" discipline already used for platform user lifecycle badges.
 */

import type {
  CommerceOrderFulfillmentStatus,
  CommerceOrderPaymentStatus,
  CommerceProductStatus,
  CommerceVendorState,
} from '@/types/supabase'

export type BadgeVariant = 'default' | 'accent' | 'outline' | 'success' | 'warning' | 'danger'

export function vendorStateLabel(state: CommerceVendorState): string {
  switch (state) {
    case 'draft':
      return 'Draft'
    case 'pending_review':
      return 'Pending review'
    case 'active':
      return 'Active'
    case 'suspended':
      return 'Suspended'
    case 'rejected':
      return 'Rejected'
  }
}

export function vendorStateVariant(state: CommerceVendorState): BadgeVariant {
  switch (state) {
    case 'draft':
      return 'outline'
    case 'pending_review':
      return 'warning'
    case 'active':
      return 'success'
    case 'suspended':
      return 'danger'
    case 'rejected':
      return 'danger'
  }
}

/** Product status shown to the vendor — "Out of stock" is a derived display state, never stored, computed from stock only when tracking is on. */
export function productDisplayStatus(
  status: CommerceProductStatus,
  tracksInventory: boolean,
  available: number | null,
): { label: string; variant: BadgeVariant } {
  if (status === 'draft') return { label: 'Draft', variant: 'outline' }
  if (status === 'paused') return { label: 'Paused', variant: 'outline' }
  if (tracksInventory && available !== null && available <= 0) {
    return { label: 'Out of stock', variant: 'danger' }
  }
  return { label: 'Active', variant: 'success' }
}

export function orderPaymentStatusLabel(status: CommerceOrderPaymentStatus): string {
  switch (status) {
    case 'pending_payment':
      return 'Payment pending'
    case 'paid':
      return 'Paid'
    case 'payment_failed':
      return 'Payment failed'
    case 'refund_pending':
      return 'Refund pending'
    case 'refunded':
      return 'Refunded'
  }
}

export function orderPaymentStatusVariant(status: CommerceOrderPaymentStatus): BadgeVariant {
  switch (status) {
    case 'paid':
      return 'success'
    case 'pending_payment':
      return 'outline'
    case 'payment_failed':
    case 'refund_pending':
    case 'refunded':
      return 'danger'
  }
}

export function orderFulfillmentStatusLabel(status: CommerceOrderFulfillmentStatus): string {
  switch (status) {
    case 'awaiting_vendor':
      return 'New'
    case 'vendor_accepted':
      return 'Accepted'
    case 'vendor_rejected':
      return 'Rejected'
    case 'preparing':
      return 'Preparing'
    case 'ready_for_pickup':
      return 'Ready for pickup'
    case 'handed_to_carrier':
      return 'With carrier'
    case 'completed':
      return 'Completed'
    case 'cancelled':
      return 'Cancelled'
  }
}

export function orderFulfillmentStatusVariant(status: CommerceOrderFulfillmentStatus): BadgeVariant {
  switch (status) {
    case 'awaiting_vendor':
      return 'accent'
    case 'vendor_accepted':
    case 'preparing':
      return 'warning'
    case 'ready_for_pickup':
    case 'handed_to_carrier':
    case 'completed':
      return 'success'
    case 'vendor_rejected':
    case 'cancelled':
      return 'danger'
  }
}

/**
 * Which fulfillment actions are valid from the order's CURRENT state —
 * mirrors the server-side state machine exactly (awaiting_vendor ->
 * vendor_accepted -> preparing -> ready_for_pickup, or awaiting_vendor ->
 * vendor_rejected) so the UI never offers a button the RPC would reject.
 * Acceptance additionally requires payment_status = 'paid'.
 */
export function availableOrderActions(
  fulfillmentStatus: CommerceOrderFulfillmentStatus,
  paymentStatus: CommerceOrderPaymentStatus,
): Array<'accept' | 'reject' | 'preparing' | 'ready'> {
  if (fulfillmentStatus !== 'awaiting_vendor') {
    if (fulfillmentStatus === 'vendor_accepted') return ['preparing']
    if (fulfillmentStatus === 'preparing') return ['ready']
    return []
  }
  return paymentStatus === 'paid' ? ['accept', 'reject'] : ['reject']
}

/** Vendor order inbox tabs — each maps to real fulfillment_status value(s), never a fabricated bucket. */
export const VENDOR_ORDER_TABS: Array<{ value: string; label: string; statuses: CommerceOrderFulfillmentStatus[] }> = [
  { value: 'new', label: 'New', statuses: ['awaiting_vendor'] },
  { value: 'preparing', label: 'Preparing', statuses: ['vendor_accepted', 'preparing'] },
  { value: 'ready', label: 'Ready', statuses: ['ready_for_pickup', 'handed_to_carrier'] },
  { value: 'completed', label: 'Completed', statuses: ['completed'] },
  { value: 'cancelled', label: 'Cancelled/Rejected', statuses: ['vendor_rejected', 'cancelled'] },
]
