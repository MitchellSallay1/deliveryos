import { describe, expect, it } from 'vitest'
import { can } from '@/lib/rbac'

describe('operations rbac', () => {
  it('allows dispatcher operations hub', () => {
    expect(can('dispatcher', 'page:operations')).toBe(true)
  })

  it('denies rider operations hub', () => {
    expect(can('rider', 'page:operations')).toBe(false)
  })
})
