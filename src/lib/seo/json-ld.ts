import { DEFAULT_OG_IMAGE, SITE_NAME, SITE_URL } from './config'
import type { SeoRoute } from './routes'

/**
 * Schema.org JSON-LD builders. Every field is either a fixed, currently-true
 * fact about DeliveryOS (name, URL, description) or omitted — no ratings,
 * reviews, prices, addresses, or social profiles are fabricated. Keep it
 * that way: add a property only when there is a real value to put in it.
 */

export type JsonLd = Record<string, unknown>

export function buildOrganizationJsonLd(): JsonLd {
  return {
    '@context': 'https://schema.org',
    '@type': 'Organization',
    name: SITE_NAME,
    url: SITE_URL,
    logo: `${SITE_URL}/icon-512.png`,
    description:
      'DeliveryOS builds delivery and logistics operations software for dispatch, rider management, tracking, and vendor commerce in Liberia.',
  }
}

export function buildWebSiteJsonLd(): JsonLd {
  return {
    '@context': 'https://schema.org',
    '@type': 'WebSite',
    name: SITE_NAME,
    url: SITE_URL,
  }
}

/**
 * SoftwareApplication without `offers`/`aggregateRating` — DeliveryOS has no
 * published fixed price (plans are shown on /pricing but vary by usage/plan
 * tier) and no review data to report honestly, so those properties are
 * left out entirely rather than filled with placeholder values.
 */
export function buildSoftwareApplicationJsonLd(): JsonLd {
  return {
    '@context': 'https://schema.org',
    '@type': 'SoftwareApplication',
    name: SITE_NAME,
    applicationCategory: 'BusinessApplication',
    operatingSystem: 'Web',
    url: SITE_URL,
    description:
      'Delivery and logistics operations software: dispatch, rider management, live tracking, cash-on-delivery reconciliation, and vendor commerce.',
  }
}

export function buildWebPageJsonLd(params: { path: string; title: string; description: string }): JsonLd {
  return {
    '@context': 'https://schema.org',
    '@type': 'WebPage',
    name: params.title,
    description: params.description,
    url: `${SITE_URL}${params.path}`,
    isPartOf: {
      '@type': 'WebSite',
      name: SITE_NAME,
      url: SITE_URL,
    },
  }
}

export function buildBreadcrumbJsonLd(items: { label: string; path: string }[]): JsonLd {
  return {
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    itemListElement: items.map((item, index) => ({
      '@type': 'ListItem',
      position: index + 1,
      name: item.label,
      item: `${SITE_URL}${item.path}`,
    })),
  }
}

/** Built only from the real Q&A copy already published on /faq — see src/pages/marketing/faq.tsx. */
export function buildFaqJsonLd(items: { q: string; a: string }[]): JsonLd {
  return {
    '@context': 'https://schema.org',
    '@type': 'FAQPage',
    mainEntity: items.map((item) => ({
      '@type': 'Question',
      name: item.q,
      acceptedAnswer: {
        '@type': 'Answer',
        text: item.a,
      },
    })),
  }
}

/** OG image reference used by JSON-LD `image` properties where relevant. */
export const JSON_LD_IMAGE = DEFAULT_OG_IMAGE

/** WebPage + BreadcrumbList (Home → this page) for a standard, non-home marketing page. */
export function buildStandardPageJsonLd(route: SeoRoute): JsonLd[] {
  const result: JsonLd[] = [buildWebPageJsonLd(route)]
  if (route.breadcrumbLabel) {
    result.push(
      buildBreadcrumbJsonLd([
        { label: SITE_NAME, path: '/' },
        { label: route.breadcrumbLabel, path: route.path },
      ]),
    )
  }
  return result
}
