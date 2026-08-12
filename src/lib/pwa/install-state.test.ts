import { describe, expect, it } from 'vitest'
import { INSTALL_DISMISS_COOLDOWN_MS, isSafeRouteForInstallPromotion, isWithinDismissalCooldown } from './install-state'

describe('isWithinDismissalCooldown', () => {
  const now = 1_700_000_000_000

  it('is false when never dismissed', () => {
    expect(isWithinDismissalCooldown(null, now)).toBe(false)
  })

  it('is true immediately after dismissal', () => {
    expect(isWithinDismissalCooldown(now, now)).toBe(true)
  })

  it('is true just before the cooldown expires', () => {
    expect(isWithinDismissalCooldown(now - (INSTALL_DISMISS_COOLDOWN_MS - 1), now)).toBe(true)
  })

  it('is false once the cooldown has fully elapsed', () => {
    expect(isWithinDismissalCooldown(now - INSTALL_DISMISS_COOLDOWN_MS, now)).toBe(false)
  })

  it('is false well after the cooldown', () => {
    expect(isWithinDismissalCooldown(now - INSTALL_DISMISS_COOLDOWN_MS * 2, now)).toBe(false)
  })

  it('respects a custom cooldown window', () => {
    const oneHour = 60 * 60 * 1000
    expect(isWithinDismissalCooldown(now - oneHour / 2, now, oneHour)).toBe(true)
    expect(isWithinDismissalCooldown(now - oneHour * 2, now, oneHour)).toBe(false)
  })
})

describe('isSafeRouteForInstallPromotion', () => {
  it('allows the marketing home page', () => {
    expect(isSafeRouteForInstallPromotion('/')).toBe(true)
  })

  it('allows the authenticated dashboard', () => {
    expect(isSafeRouteForInstallPromotion('/dashboard')).toBe(true)
  })

  it('allows customer order history', () => {
    expect(isSafeRouteForInstallPromotion('/orders')).toBe(true)
  })

  it('allows storefront browsing', () => {
    expect(isSafeRouteForInstallPromotion('/store/marys-kitchen')).toBe(true)
  })

  it('blocks storefront checkout', () => {
    expect(isSafeRouteForInstallPromotion('/store/marys-kitchen/checkout')).toBe(false)
  })

  it('blocks an individual order detail page', () => {
    expect(isSafeRouteForInstallPromotion('/orders/abc-123')).toBe(false)
  })

  it('blocks OTP/registration routes', () => {
    expect(isSafeRouteForInstallPromotion('/register')).toBe(false)
    expect(isSafeRouteForInstallPromotion('/register/merchant')).toBe(false)
  })

  it('blocks rider job/delivery-transition routes', () => {
    expect(isSafeRouteForInstallPromotion('/my-jobs')).toBe(false)
  })

  it('blocks vendor order handling', () => {
    expect(isSafeRouteForInstallPromotion('/vendor/orders')).toBe(false)
  })

  it('blocks carrier marketplace job handling', () => {
    expect(isSafeRouteForInstallPromotion('/marketplace/jobs')).toBe(false)
  })

  it('blocks admin/financial screens', () => {
    expect(isSafeRouteForInstallPromotion('/admin')).toBe(false)
    expect(isSafeRouteForInstallPromotion('/admin/commerce-finance')).toBe(false)
    expect(isSafeRouteForInstallPromotion('/billing')).toBe(false)
  })
})
