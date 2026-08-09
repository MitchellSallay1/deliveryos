import { describe, expect, it } from 'vitest'
import { can, isNavVisibleForBusinessType } from '@/lib/rbac'

describe('marketplace rbac navigation', () => {
  it('hides fleet nav for merchant-only companies', () => {
    expect(isNavVisibleForBusinessType('page:operations', 'merchant')).toBe(false)
    expect(isNavVisibleForBusinessType('page:riders', 'merchant')).toBe(false)
    expect(isNavVisibleForBusinessType('page:deliveries', 'merchant')).toBe(true)
    expect(isNavVisibleForBusinessType('page:merchant-requests', 'merchant')).toBe(true)
  })

  it('hides merchant portal for logistics-only companies', () => {
    expect(isNavVisibleForBusinessType('page:merchant-requests', 'logistics_provider')).toBe(
      false,
    )
    expect(isNavVisibleForBusinessType('page:marketplace-jobs', 'logistics_provider')).toBe(true)
  })

  it('hybrid sees both sides', () => {
    expect(isNavVisibleForBusinessType('page:operations', 'hybrid')).toBe(true)
    expect(isNavVisibleForBusinessType('page:merchant-requests', 'hybrid')).toBe(true)
  })

  it('merchant owner can create deliveries via permission set', () => {
    expect(can('company_owner', 'page:merchant-requests')).toBe(true)
    expect(can('company_owner', 'page:billing')).toBe(true)
  })
})
