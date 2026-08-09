import { describe, expect, it } from 'vitest'
import { PUBLIC_MARKETING_PATHS, MARKETING_CTA_LOGIN, MARKETING_CTA_REGISTER } from '@/lib/public-routes'

describe('public marketing routes', () => {
  it('lists all required public paths', () => {
    expect(PUBLIC_MARKETING_PATHS).toContain('/')
    expect(PUBLIC_MARKETING_PATHS).toContain('/pricing')
    expect(PUBLIC_MARKETING_PATHS).toContain('/terms')
    expect(PUBLIC_MARKETING_PATHS).toContain('/privacy')
    expect(PUBLIC_MARKETING_PATHS).toContain('/status')
  })

  it('CTAs point to auth flows', () => {
    expect(MARKETING_CTA_LOGIN).toBe('/login')
    expect(MARKETING_CTA_REGISTER).toBe('/register')
  })
})
