import { describe, expect, it } from 'vitest'
import { NON_INDEXABLE_PUBLIC_PATH_PREFIXES, SEO_ROUTES, SEO_ROUTE_LIST } from './routes'

describe('SEO_ROUTES', () => {
  it('has no duplicate paths', () => {
    const paths = SEO_ROUTE_LIST.map((r) => r.path)
    expect(new Set(paths).size).toBe(paths.length)
  })

  it('every route has a non-empty title and description', () => {
    for (const route of SEO_ROUTE_LIST) {
      expect(route.title.length).toBeGreaterThan(0)
      expect(route.description.length).toBeGreaterThan(0)
    }
  })

  it('every non-home route has a breadcrumb label', () => {
    for (const [key, route] of Object.entries(SEO_ROUTES)) {
      if (key === 'home') continue
      expect(route.breadcrumbLabel, `${key} should have a breadcrumbLabel`).toBeTruthy()
    }
  })

  it('descriptions stay within a reasonable length for a search snippet', () => {
    for (const route of SEO_ROUTE_LIST) {
      expect(route.description.length).toBeLessThanOrEqual(300)
    }
  })
})

describe('NON_INDEXABLE_PUBLIC_PATH_PREFIXES', () => {
  it('does not disallow public storefronts or the marketing routes themselves', () => {
    expect(NON_INDEXABLE_PUBLIC_PATH_PREFIXES).not.toContain('/store')
    for (const route of SEO_ROUTE_LIST) {
      expect(NON_INDEXABLE_PUBLIC_PATH_PREFIXES).not.toContain(route.path)
    }
  })
})
