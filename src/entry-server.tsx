import type { ComponentType } from 'react'
import { renderToString } from 'react-dom/server'
import { StaticRouter } from 'react-router'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { BrandingProvider } from '@/branding/BrandingProvider'
import { PwaInstallProvider } from '@/hooks/use-pwa-install'
import { MarketingHeader } from '@/components/marketing/MarketingHeader'
import { MarketingFooter } from '@/components/marketing/MarketingFooter'
import type { PageMetaOptions } from '@/lib/page-meta'
import { renderMarketingHtml } from '@/lib/seo/html-template'
import { getPageHeadData } from '@/lib/seo/page-head'
import type { SeoRouteKey } from '@/lib/seo/routes'
import { SITE_URL } from '@/lib/seo/config'
import { HomePage } from '@/pages/marketing/home'
import { FeaturesPage } from '@/pages/marketing/features'
import { SolutionsPage } from '@/pages/marketing/solutions'
import { PricingPage } from '@/pages/marketing/pricing'
import { AboutPage } from '@/pages/marketing/about'
import { ContactPage } from '@/pages/marketing/contact'
import { FaqPage } from '@/pages/marketing/faq'
import { SecurityPage } from '@/pages/marketing/security'
import { StatusPage } from '@/pages/marketing/status'
import { DevelopersPage, PartnersPage } from '@/pages/marketing/developers'
import { TermsPage, PrivacyPage } from '@/pages/legal'

/**
 * Build-time-only entry point (see scripts/prerender.mjs). Renders each
 * public marketing route to a real HTML string with react-dom/server so
 * search and social-preview crawlers — none of which run JavaScript for
 * OG/Twitter cards, and some of which don't for indexing either — receive
 * actual page content and not an empty `<div id="root">` shell. Never
 * imported by the browser bundle (vite.config.ts only builds this file
 * when isSsrBuild is true) and never imports AuthProvider or anything else
 * that assumes a signed-in session — crawlers are always signed out, so
 * that is the correct content to serve them anyway.
 */
const SSR_ROUTE_KEYS: Record<string, SeoRouteKey> = {
  '/': 'home',
  '/features': 'features',
  '/solutions': 'solutions',
  '/pricing': 'pricing',
  '/about': 'about',
  '/contact': 'contact',
  '/faq': 'faq',
  '/security': 'security',
  '/status': 'status',
  '/developers': 'developers',
  '/partners': 'partners',
  '/terms': 'terms',
  '/privacy': 'privacy',
}

export const SSR_PAGE_COMPONENTS: Record<string, ComponentType> = {
  '/': HomePage,
  '/features': FeaturesPage,
  '/solutions': SolutionsPage,
  '/pricing': PricingPage,
  '/about': AboutPage,
  '/contact': ContactPage,
  '/faq': FaqPage,
  '/security': SecurityPage,
  '/status': StatusPage,
  '/developers': DevelopersPage,
  '/partners': PartnersPage,
  '/terms': TermsPage,
  '/privacy': PrivacyPage,
}

/** Every path scripts/prerender.mjs should generate a static HTML file for. */
export const SSR_PATHS = Object.keys(SSR_ROUTE_KEYS)

/** Title/description/canonical/OG/robots/JSON-LD for a prerendered route — same source the client hook uses. */
export function getMarketingPageHead(path: string): PageMetaOptions {
  const key = SSR_ROUTE_KEYS[path]
  if (!key) throw new Error(`entry-server: no SEO route registered for "${path}"`)
  return getPageHeadData(key)
}

/** Full static HTML document for `path`, given the built dist/index.html shell as `template`. */
export function renderStaticPage(path: string, template: string): string {
  return renderMarketingHtml({
    template,
    bodyHtml: renderMarketingPage(path),
    head: getMarketingPageHead(path),
    origin: SITE_URL,
  })
}

export function renderMarketingPage(path: string): string {
  const Page = SSR_PAGE_COMPONENTS[path]
  if (!Page) {
    throw new Error(`entry-server: no SSR page component registered for "${path}"`)
  }

  // Fresh QueryClient per render — this is a one-shot synchronous string
  // render, not a hydrated app, so there is nothing to cache across calls.
  // No queries resolve during renderToString; components that fetch (e.g.
  // HomePricingPreview) render their already-designed loading/fallback
  // state, which is real, non-fabricated content.
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false, staleTime: Infinity } },
  })

  return renderToString(
    <BrandingProvider>
      <QueryClientProvider client={queryClient}>
        <StaticRouter location={path}>
          <PwaInstallProvider>
            <div className="mkt-root flex min-h-screen flex-col overflow-x-hidden">
              <MarketingHeader />
              <main className="flex-1">
                <Page />
              </main>
              <MarketingFooter />
            </div>
          </PwaInstallProvider>
        </StaticRouter>
      </QueryClientProvider>
    </BrandingProvider>,
  )
}
