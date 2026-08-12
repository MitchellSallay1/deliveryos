import { SITE_NAME } from './config'

export type SeoRouteKey =
  | 'home'
  | 'features'
  | 'solutions'
  | 'pricing'
  | 'about'
  | 'contact'
  | 'faq'
  | 'security'
  | 'status'
  | 'developers'
  | 'partners'
  | 'terms'
  | 'privacy'

export type SeoRoute = {
  path: string
  /** Rendered as `${title} · DeliveryOS` by setPageMeta, except home which is used verbatim. */
  title: string
  description: string
  /** Human label used in breadcrumb JSON-LD and nav; omitted for home. */
  breadcrumbLabel?: string
}

/**
 * Single registry for every public, indexable marketing route — consumed by
 * both `usePageMeta` (client-side, src/hooks/use-page-meta.ts) and the
 * build-time prerender script (scripts/prerender.mjs) so the two can never
 * drift out of sync. Titles/descriptions are written for humans first —
 * accurate, specific to the page, no keyword repetition.
 */
export const SEO_ROUTES: Record<SeoRouteKey, SeoRoute> = {
  home: {
    path: '/',
    title: `${SITE_NAME} — Delivery management software for Liberia`,
    description:
      'Dispatch, rider management, live delivery tracking, cash-on-delivery reconciliation, and vendor commerce in one platform — built for delivery businesses and merchants operating in Liberia.',
  },
  features: {
    path: '/features',
    title: 'Product tour',
    description:
      'See how DeliveryOS handles dispatch, rider management on smartphone or button phones, live tracking, cash-on-delivery, fleet operations, and marketplace capacity.',
    breadcrumbLabel: 'Features',
  },
  solutions: {
    path: '/solutions',
    title: 'Solutions for delivery companies and merchants',
    description:
      'DeliveryOS for courier and delivery companies, merchants without their own riders, retail and restaurant businesses, and enterprise logistics teams.',
    breadcrumbLabel: 'Solutions',
  },
  pricing: {
    path: '/pricing',
    title: 'Pricing',
    description:
      'DeliveryOS plans and feature comparison — Starter, Business, and Enterprise, with a 7-day free trial and no card required to start.',
    breadcrumbLabel: 'Pricing',
  },
  about: {
    path: '/about',
    title: 'About',
    description:
      'DeliveryOS is the operating system for modern delivery businesses — a multi-tenant platform for dispatch, riders, customers, payments, tracking, and logistics operations.',
    breadcrumbLabel: 'About',
  },
  contact: {
    path: '/contact',
    title: 'Contact',
    description: 'Talk to DeliveryOS about dispatch, rider management, tracking, and vendor commerce for your operation.',
    breadcrumbLabel: 'Contact',
  },
  faq: {
    path: '/faq',
    title: 'FAQ',
    description: 'Answers to common questions about DeliveryOS: riders, GPS tracking, marketplace, trials, and integrations.',
    breadcrumbLabel: 'FAQ',
  },
  security: {
    path: '/security',
    title: 'Security',
    description:
      'How DeliveryOS protects tenant data — Row Level Security, role-based access, audit trails, and scoped storage policies.',
    breadcrumbLabel: 'Security',
  },
  status: {
    path: '/status',
    title: 'Status',
    description: 'Current DeliveryOS component readiness status.',
    breadcrumbLabel: 'Status',
  },
  developers: {
    path: '/developers',
    title: 'Developers',
    description: 'Integrate order flows, tracking, and events with the DeliveryOS REST API and webhooks.',
    breadcrumbLabel: 'Developers',
  },
  partners: {
    path: '/partners',
    title: 'Partners',
    description: 'DeliveryOS partner and network relationships, including MTN as strategic technology partner.',
    breadcrumbLabel: 'Partners',
  },
  terms: {
    path: '/terms',
    title: 'Terms of Service',
    description: 'DeliveryOS Terms of Service.',
    breadcrumbLabel: 'Terms',
  },
  privacy: {
    path: '/privacy',
    title: 'Privacy Policy',
    description: 'How DeliveryOS processes account, delivery, and location data.',
    breadcrumbLabel: 'Privacy',
  },
}

export const SEO_ROUTE_LIST = Object.values(SEO_ROUTES)

/**
 * Paths that are public (no login required) but are not useful, indexable
 * search results — personal/transactional data or one-time flows. Kept
 * here so robots.txt (public/robots-marketing.txt) and this registry state
 * the same reasoning in one place; the two files must be kept in sync by
 * hand since robots.txt is plain static text.
 */
export const NON_INDEXABLE_PUBLIC_PATH_PREFIXES = [
  '/login',
  '/register',
  '/auth',
  '/setup',
  '/link-rider',
  '/track', // per-delivery tracking codes — personal, not a search result
  '/invite',
  '/rider/invite',
  '/orders', // customer order history/detail
  '/dashboard',
  '/deliveries',
  '/merchant',
  '/marketplace',
  '/billing',
  '/vendor',
  '/live-map',
  '/operations',
  '/riders',
  '/customers',
  '/reports',
  '/notifications',
  '/settings',
  '/team',
  '/my-jobs',
  '/admin',
] as const
