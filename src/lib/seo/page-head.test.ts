import { describe, expect, it } from 'vitest'
import { getPageHeadData } from './page-head'
import { FAQ_ITEMS } from '@/pages/marketing/faq-content'

describe('getPageHeadData', () => {
  it('home: absolute title, and Organization + WebSite + SoftwareApplication + WebPage JSON-LD', () => {
    const head = getPageHeadData('home')
    expect(head.titleIsAbsolute).toBe(true)
    const types = head.jsonLd?.map((n) => n['@type'])
    expect(types).toEqual(['Organization', 'WebSite', 'SoftwareApplication', 'WebPage'])
  })

  it('faq: WebPage + BreadcrumbList + FAQPage built from the real published Q&A copy', () => {
    const head = getPageHeadData('faq')
    const types = head.jsonLd?.map((n) => n['@type'])
    expect(types).toEqual(['WebPage', 'BreadcrumbList', 'FAQPage'])
    const faqNode = head.jsonLd?.find((n) => n['@type'] === 'FAQPage') as { mainEntity: unknown[] }
    expect(faqNode.mainEntity).toHaveLength(FAQ_ITEMS.length)
  })

  it('status: forced noindex even though every other route defaults to index, follow', () => {
    const head = getPageHeadData('status')
    expect(head.robots).toBe('noindex, follow')
  })

  it('a standard route (e.g. security) is not forced noindex and gets WebPage + BreadcrumbList', () => {
    const head = getPageHeadData('security')
    expect(head.robots).toBeUndefined()
    expect(head.jsonLd?.map((n) => n['@type'])).toEqual(['WebPage', 'BreadcrumbList'])
  })
})
