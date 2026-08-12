import type { PageMetaOptions } from '@/lib/page-meta'
import { FAQ_ITEMS } from '@/pages/marketing/faq-content'
import {
  buildFaqJsonLd,
  buildOrganizationJsonLd,
  buildSoftwareApplicationJsonLd,
  buildStandardPageJsonLd,
  buildWebPageJsonLd,
  buildWebSiteJsonLd,
} from './json-ld'
import { SEO_ROUTES, type SeoRouteKey } from './routes'

/**
 * The one function that decides what goes in `<head>` (and, via jsonLd,
 * `<script type="application/ld+json">`) for a given marketing route. Both
 * consumers call this same function so they can never disagree:
 *  - each page component, client-side, via usePageMeta(getPageHeadData(key))
 *  - scripts/prerender.mjs, at build time, via the compiled entry-server
 *    bundle (src/entry-server.tsx re-exports this)
 */
export function getPageHeadData(key: SeoRouteKey): PageMetaOptions {
  const route = SEO_ROUTES[key]

  if (key === 'home') {
    return {
      ...route,
      titleIsAbsolute: true,
      jsonLd: [
        buildOrganizationJsonLd(),
        buildWebSiteJsonLd(),
        buildSoftwareApplicationJsonLd(),
        buildWebPageJsonLd(route),
      ],
    }
  }

  if (key === 'faq') {
    return { ...route, jsonLd: [...buildStandardPageJsonLd(route), buildFaqJsonLd([...FAQ_ITEMS])] }
  }

  // /status shows product-readiness placeholders, not live monitoring data
  // (see src/pages/marketing/status.tsx) — not a useful search result, but
  // still worth crawling for its outbound links.
  if (key === 'status') {
    return { ...route, robots: 'noindex, follow', jsonLd: buildStandardPageJsonLd(route) }
  }

  return { ...route, jsonLd: buildStandardPageJsonLd(route) }
}
