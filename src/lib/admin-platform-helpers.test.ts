import { describe, expect, it } from 'vitest'
import { compareHint, formatLrd } from '@/components/admin/AdminHealthBadge'

describe('admin platform helpers', () => {
  it('formats LRD from cents', () => {
    expect(formatLrd(250000)).toContain('2,500')
  })

  it('computes day-over-day hint without inventing history', () => {
    expect(compareHint(10, 5)).toMatch(/\+100%/)
    expect(compareHint(0, 0)).toBeUndefined()
  })
})
