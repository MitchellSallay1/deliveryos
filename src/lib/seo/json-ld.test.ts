import { describe, expect, it } from 'vitest'
import {
  buildBreadcrumbJsonLd,
  buildFaqJsonLd,
  buildOrganizationJsonLd,
  buildSoftwareApplicationJsonLd,
  buildStandardPageJsonLd,
  buildWebPageJsonLd,
  buildWebSiteJsonLd,
} from './json-ld'
import { SITE_URL } from './config'

/** No object in this file may claim data DeliveryOS doesn't actually have. */
const FORBIDDEN_KEYS = ['aggregateRating', 'review', 'offers', 'priceRange', 'address', 'telephone', 'sameAs']

function assertNoFabrication(obj: unknown) {
  const json = JSON.stringify(obj)
  for (const key of FORBIDDEN_KEYS) {
    expect(json.includes(`"${key}"`)).toBe(false)
  }
}

describe('Organization JSON-LD', () => {
  it('is a valid Organization node with only real, static facts', () => {
    const org = buildOrganizationJsonLd()
    expect(org['@context']).toBe('https://schema.org')
    expect(org['@type']).toBe('Organization')
    expect(org.url).toBe(SITE_URL)
    assertNoFabrication(org)
  })
})

describe('WebSite JSON-LD', () => {
  it('is a valid WebSite node', () => {
    const site = buildWebSiteJsonLd()
    expect(site['@type']).toBe('WebSite')
    expect(site.url).toBe(SITE_URL)
  })
})

describe('SoftwareApplication JSON-LD', () => {
  it('never fabricates pricing or review data', () => {
    const app = buildSoftwareApplicationJsonLd()
    expect(app['@type']).toBe('SoftwareApplication')
    assertNoFabrication(app)
  })
})

describe('WebPage JSON-LD', () => {
  it('builds a page-specific node from real title/description/path', () => {
    const page = buildWebPageJsonLd({ path: '/features', title: 'Product tour', description: 'See it in action.' })
    expect(page.url).toBe(`${SITE_URL}/features`)
    expect(page.name).toBe('Product tour')
  })
})

describe('BreadcrumbList JSON-LD', () => {
  it('numbers positions starting at 1 and resolves absolute URLs', () => {
    const crumbs = buildBreadcrumbJsonLd([
      { label: 'DeliveryOS', path: '/' },
      { label: 'Features', path: '/features' },
    ])
    const items = crumbs.itemListElement as { position: number; item: string }[]
    expect(items[0]?.position).toBe(1)
    expect(items[1]?.position).toBe(2)
    expect(items[1]?.item).toBe(`${SITE_URL}/features`)
  })
})

describe('FAQPage JSON-LD', () => {
  it('maps real Q&A copy 1:1 into mainEntity, no added/altered answers', () => {
    const items = [{ q: 'Does it support GPS?', a: 'Yes, for smartphone riders.' }]
    const faq = buildFaqJsonLd(items)
    expect(faq['@type']).toBe('FAQPage')
    const entity = faq.mainEntity as { name: string; acceptedAnswer: { text: string } }[]
    expect(entity[0]?.name).toBe(items[0]!.q)
    expect(entity[0]?.acceptedAnswer.text).toBe(items[0]!.a)
  })
})

describe('buildStandardPageJsonLd', () => {
  it('includes a WebPage and, when breadcrumbLabel is set, a BreadcrumbList back to home', () => {
    const result = buildStandardPageJsonLd({ path: '/about', title: 'About', description: 'x', breadcrumbLabel: 'About' })
    expect(result).toHaveLength(2)
    expect(result[0]!['@type']).toBe('WebPage')
    expect(result[1]!['@type']).toBe('BreadcrumbList')
  })

  it('omits the BreadcrumbList when the route has no breadcrumbLabel', () => {
    const result = buildStandardPageJsonLd({ path: '/', title: 'Home', description: 'x' })
    expect(result).toHaveLength(1)
  })
})
