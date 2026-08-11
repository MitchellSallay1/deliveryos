import { describe, expect, it } from 'vitest'
import { availableOrderActions, productDisplayStatus } from '@/lib/vendor-commerce-ui'

describe('availableOrderActions', () => {
  it('offers accept/reject for an online-payment order only once paid', () => {
    expect(availableOrderActions('awaiting_vendor', 'paid', 'mtn_momo')).toEqual(['accept', 'reject'])
  })

  it('offers only reject for an online-payment order not yet paid — never accept without payment', () => {
    expect(availableOrderActions('awaiting_vendor', 'pending_payment', 'mtn_momo')).toEqual(['reject'])
    expect(availableOrderActions('awaiting_vendor', 'pending_payment', 'orange_money')).toEqual(['reject'])
  })

  it('offers accept/reject for a COD order while still pending_payment — payment is legitimately due on delivery', () => {
    expect(availableOrderActions('awaiting_vendor', 'pending_payment', 'cod')).toEqual(['accept', 'reject'])
  })

  it('offers accept/reject for a COD order already marked paid — being paid must never block acceptance', () => {
    expect(availableOrderActions('awaiting_vendor', 'paid', 'cod')).toEqual(['accept', 'reject'])
  })

  it('offers only reject for a COD order in a payment-problem state', () => {
    expect(availableOrderActions('awaiting_vendor', 'payment_failed', 'cod')).toEqual(['reject'])
    expect(availableOrderActions('awaiting_vendor', 'refund_pending', 'cod')).toEqual(['reject'])
  })

  it('offers only mark-preparing after vendor_accepted', () => {
    expect(availableOrderActions('vendor_accepted', 'paid', 'cod')).toEqual(['preparing'])
  })

  it('offers only mark-ready while preparing', () => {
    expect(availableOrderActions('preparing', 'paid', 'cod')).toEqual(['ready'])
  })

  it('offers no actions once ready_for_pickup, completed, rejected, or cancelled', () => {
    expect(availableOrderActions('ready_for_pickup', 'paid', 'cod')).toEqual([])
    expect(availableOrderActions('completed', 'paid', 'cod')).toEqual([])
    expect(availableOrderActions('vendor_rejected', 'refund_pending', 'cod')).toEqual([])
    expect(availableOrderActions('cancelled', 'pending_payment', 'cod')).toEqual([])
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
