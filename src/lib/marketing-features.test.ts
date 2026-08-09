import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { MARKETING_EXPLORE_HREF } from '@/lib/marketing-cta'
import {
  MARKETING_PRODUCT_TOUR_HREF,
  MARKETING_PRIMARY_NAV,
  MARKETING_PRODUCT_MEGA_COLUMNS,
  isFeaturesRoute,
  isProductNavActive,
} from '@/lib/marketing-nav'

describe('features product tour', () => {
  it('Explore platform CTA targets product tour hash', () => {
    expect(MARKETING_EXPLORE_HREF).toBe('/features#product-tour')
    expect(MARKETING_PRODUCT_TOUR_HREF).toBe(MARKETING_EXPLORE_HREF)
  })

  it('product nav links to tour without forcing mega open (route helper only)', () => {
    const product = MARKETING_PRIMARY_NAV.find((n) => n.mega === 'product')
    expect(product?.to).toBe('/features#product-tour')
    expect(isProductNavActive('/features')).toBe(true)
    expect(isProductNavActive('/pricing')).toBe(false)
    expect(isFeaturesRoute('/features')).toBe(true)
  })

  it('mega menu columns use feature section anchors', () => {
    const hrefs = MARKETING_PRODUCT_MEGA_COLUMNS.flatMap((c) => c.links.map((l) => l.to))
    expect(hrefs.some((h) => h.includes('#dispatch'))).toBe(true)
    expect(hrefs.some((h) => h.includes('#developers'))).toBe(true)
  })

  it('features page defines product-tour hero above fold', () => {
    const src = readFileSync(resolve(process.cwd(), 'src/pages/marketing/features.tsx'), 'utf8')
    expect(src).toContain('ProductTourHero')
    expect(src).toContain('useMarketingHashScroll')
    const hero = readFileSync(
      resolve(process.cwd(), 'src/components/marketing/features/ProductTourHero.tsx'),
      'utf8',
    )
    expect(hero).toMatch(/id="product-tour"/)
    expect(hero).toContain('HeroControlTower')
    expect(hero).toContain('HeroNotificationStack')
    expect(hero).toContain('HERO_TOUR_NOTIFICATIONS')
    expect(hero).toMatch(/One live command center/)
  })

  it('marketing header closes mega on navigation (source contract)', () => {
    const src = readFileSync(resolve(process.cwd(), 'src/components/marketing/MarketingHeader.tsx'), 'utf8')
    expect(src).toContain('setMega(null)')
    expect(src).toMatch(/useEffect\(\(\) => \{[\s\S]*setMega\(null\)/)
    expect(src).toContain('absolute left-0 right-0 top-full')
    expect(src).not.toMatch(/mega && \(\s*<div className="hidden border-t/)
  })

  it('mobile header exposes product tour without desktop mega panel', () => {
    const src = readFileSync(resolve(process.cwd(), 'src/components/marketing/MarketingHeader.tsx'), 'utf8')
    expect(src).toContain('mobileMega === \'product\'')
    expect(src).toContain('xl:hidden')
  })
})
