import { isNonCanonicalHost } from '@/lib/seo/config'
import type { JsonLd } from '@/lib/seo/json-ld'

const DEFAULT_TITLE = 'DeliveryOS — The operating system for modern delivery businesses'
const DEFAULT_DESCRIPTION =
  'Manage dispatch, riders, live tracking, customers, COD, fleet operations, and logistics from one platform. Powered by MTN.'

export type PageMetaOptions = {
  title?: string
  /** Use `title` verbatim, without appending " · DeliveryOS" — for the homepage, whose title already leads with the brand name. */
  titleIsAbsolute?: boolean
  description?: string
  path?: string
  /**
   * Defaults to 'index, follow'. Automatically forced to 'noindex, nofollow'
   * on app.delivoslib.com / *.vercel.app regardless of this value — see
   * isNonCanonicalHost. Pass explicitly for pages that should never be
   * indexed even on the canonical marketing domain (there are none today).
   */
  robots?: string
  ogType?: 'website' | 'article'
  jsonLd?: JsonLd[]
}

/**
 * Sets document.title and meta/link/script tags client-side. This runs
 * after the JS bundle loads, so it is NOT sufficient on its own for search
 * or social-preview crawlers that don't execute JavaScript — those read
 * scripts/prerender.mjs's build-time HTML instead (see docs/SEO.md). This
 * function still matters for: in-app SPA navigation (the tab title/tags
 * must update without a full reload), and as a second, independent source
 * of the same values for any crawler that does run JS.
 */
export function setPageMeta(options: PageMetaOptions) {
  const title = options.title
    ? options.titleIsAbsolute
      ? options.title
      : `${options.title} · DeliveryOS`
    : DEFAULT_TITLE
  const description = options.description ?? DEFAULT_DESCRIPTION
  const ogType = options.ogType ?? 'website'
  document.title = title

  setMetaTag('name', 'description', description)
  setMetaTag('property', 'og:site_name', 'DeliveryOS')
  setMetaTag('property', 'og:type', ogType)
  setMetaTag('property', 'og:title', title)
  setMetaTag('property', 'og:description', description)
  setMetaTag('property', 'og:image', '/og-image.png', true)
  setMetaTag('property', 'og:image:width', '1200')
  setMetaTag('property', 'og:image:height', '630')
  setMetaTag('name', 'twitter:card', 'summary_large_image')
  setMetaTag('name', 'twitter:title', title)
  setMetaTag('name', 'twitter:description', description)
  setMetaTag('name', 'twitter:image', '/og-image.png', true)

  const hostname = typeof window !== 'undefined' ? window.location.hostname : ''
  const robots = isNonCanonicalHost(hostname) ? 'noindex, nofollow' : (options.robots ?? 'index, follow')
  setMetaTag('name', 'robots', robots)

  if (options.path) {
    const origin = window.location.origin
    setMetaTag('property', 'og:url', `${origin}${options.path}`)
    setLinkTag('canonical', `${origin}${options.path}`)
  }

  setJsonLd(options.jsonLd)
}

function setMetaTag(attr: 'name' | 'property', key: string, content: string, resolveAgainstOrigin = false) {
  let el = document.querySelector<HTMLMetaElement>(`meta[${attr}="${key}"]`)
  if (!el) {
    el = document.createElement('meta')
    el.setAttribute(attr, key)
    document.head.appendChild(el)
  }
  el.content = resolveAgainstOrigin && typeof window !== 'undefined' ? `${window.location.origin}${content}` : content
}

function setLinkTag(rel: string, href: string) {
  let link = document.querySelector<HTMLLinkElement>(`link[rel="${rel}"]`)
  if (!link) {
    link = document.createElement('link')
    link.rel = rel
    document.head.appendChild(link)
  }
  link.href = href
}

function setJsonLd(items: JsonLd[] | undefined) {
  const existing = document.head.querySelectorAll('script[data-seo="page"]')
  existing.forEach((el) => el.remove())
  if (!items || items.length === 0) return
  for (const item of items) {
    const script = document.createElement('script')
    script.type = 'application/ld+json'
    script.dataset.seo = 'page'
    script.textContent = JSON.stringify(item)
    document.head.appendChild(script)
  }
}
