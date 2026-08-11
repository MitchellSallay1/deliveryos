import { describe, expect, it } from 'vitest'
import { availableOrderActions, productDisplayStatus } from '@/lib/vendor-commerce-ui'

describe('availableOrderActions', () => {
  it('offers accept/reject only when awaiting_vendor and paid', () => {
    expect(availableOrderActions('awaiting_vendor', 'paid')).toEqual(['accept', 'reject'])
  })

  it('offers only reject when awaiting_vendor and not yet paid — never accept without payment', () => {
    expect(availableOrderActions('awaiting_vendor', 'pending_payment')).toEqual(['reject'])
  })

  it('offers only mark-preparing after vendor_accepted', () => {
    expect(availableOrderActions('vendor_accepted', 'paid')).toEqual(['preparing'])
  })

  it('offers only mark-ready while preparing', () => {
    expect(availableOrderActions('preparing', 'paid')).toEqual(['ready'])
  })

  it('offers no actions once ready_for_pickup, completed, rejected, or cancelled', () => {
    expect(availableOrderActions('ready_for_pickup', 'paid')).toEqual([])
    expect(availableOrderActions('completed', 'paid')).toEqual([])
    expect(availableOrderActions('vendor_rejected', 'refund_pending')).toEqual([])
    expect(availableOrderActions('cancelled', 'pending_payment')).toEqual([])
  })
})

describe('productDisplayStatus', () => {
  it('shows Draft/Paused regardless of stock', () => {
    expect(productDisplayStatus('draft', true, 0)).toEqual({ label: 'Draft', variant: 'outline' })
    expect(productDisplayStatus('paused', true, 5)).toEqual({ label: 'Paused', variant: 'outline' })
  })

  it('shows Out of stock only for an active, inventory-tracked product with zero available', () => {
    expect(productDisplayStatus('active', true, 0)).toEqual({ label: 'Out of stock', variant: 'danger' })
    expect(productDisplayStatus('active', true, -1)).toEqual({ label: 'Out of stock', variant: 'danger' })
  })

  it('shows Active for an active product with stock remaining or untracked inventory', () => {
    expect(productDisplayStatus('active', true, 3)).toEqual({ label: 'Active', variant: 'success' })
    expect(productDisplayStatus('active', false, null)).toEqual({ label: 'Active', variant: 'success' })
  })
})
