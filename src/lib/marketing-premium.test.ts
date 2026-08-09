import { describe, expect, it } from 'vitest'
import {
  MARKETING_CTA_TRIAL,
  MARKETING_TRIAL_FOOTNOTE,
  MARKETING_EXPLORE_HREF,
  MTN_INTEGRATION_STATUS,
} from '@/lib/marketing-cta'
import {
  MARKETING_PRIMARY_NAV,
  MARKETING_PRODUCT_LINKS,
  MARKETING_PRODUCT_TOUR_HREF,
} from '@/lib/marketing-nav'
import { MARKETING_CTA_REGISTER } from '@/lib/public-routes'

describe('marketing premium site', () => {
  it('primary trial CTA routes to register', () => {
    expect(MARKETING_CTA_REGISTER).toBe('/register')
  })

  it('uses honest MTN integration labeling', () => {
    expect(MTN_INTEGRATION_STATUS).toMatch(/coming soon|pending/i)
  })

  it('explore CTA uses product tour deep link', () => {
    expect(MARKETING_EXPLORE_HREF).toBe(MARKETING_PRODUCT_TOUR_HREF)
  })

  it('includes product mega menu anchors', () => {
    expect(MARKETING_PRODUCT_LINKS.some((l) => l.to.includes('#dispatch'))).toBe(true)
    expect(MARKETING_PRIMARY_NAV.some((n) => n.mega === 'product')).toBe(true)
  })

  it('trial copy mentions no card when configured', () => {
    expect(MARKETING_TRIAL_FOOTNOTE.toLowerCase()).toContain('no card')
    expect(MARKETING_CTA_TRIAL.toLowerCase()).toContain('7 days')
  })

  it('hero assets paths are local', () => {
    expect('/marketing/african-woman-phone.png').toMatch(/^\/marketing\//)
    expect('/marketing/delivery-rider.png').toMatch(/^\/marketing\//)
  })
})
