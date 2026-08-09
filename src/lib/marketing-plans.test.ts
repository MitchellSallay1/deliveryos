import { describe, expect, it } from 'vitest'
import { formatPublicPlanPrice, PLAN_CATALOG_FALLBACK } from '@/lib/marketing-plans'

describe('marketing plans', () => {
  it('formats enterprise as contact us when price is zero', () => {
    const ent = PLAN_CATALOG_FALLBACK.find((p) => p.slug === 'enterprise')!
    expect(formatPublicPlanPrice(ent)).toBe('Contact us')
  })

  it('formats starter with LRD from cents', () => {
    const starter = PLAN_CATALOG_FALLBACK.find((p) => p.slug === 'starter')!
    expect(formatPublicPlanPrice(starter)).toMatch(/LRD/)
  })
})
