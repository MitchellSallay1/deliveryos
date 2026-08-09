export type MarketingNavLink = { label: string; to: string; description?: string }

export type MarketingMegaColumn = {
  heading: string
  links: MarketingNavLink[]
}

export const MARKETING_PRODUCT_TOUR_HREF = '/features#product-tour'

export const MARKETING_PRODUCT_MEGA_COLUMNS: MarketingMegaColumn[] = [
  {
    heading: 'Operations',
    links: [
      { label: 'Dispatch', to: '/features#dispatch', description: 'Create, assign, track' },
      { label: 'Tracking', to: '/features#tracking', description: 'Live status for teams' },
      { label: 'Customers', to: '/features#tracking', description: 'Visibility and notifications' },
    ],
  },
  {
    heading: 'Riders',
    links: [
      { label: 'Smartphone', to: '/features#riders', description: 'Rider PWA, GPS, POD' },
      { label: 'Button phone', to: '/features#riders', description: 'SMS / USSD readiness' },
      { label: 'GPS', to: '/features#riders', description: 'Location during active jobs' },
    ],
  },
  {
    heading: 'Business',
    links: [
      { label: 'COD', to: '/features#money', description: 'Collect and reconcile' },
      { label: 'Fleet', to: '/features#fleet', description: 'Vehicles and maintenance' },
      { label: 'Inventory', to: '/features#fleet', description: 'Warehouses and stock' },
    ],
  },
  {
    heading: 'Platform',
    links: [
      { label: 'Marketplace', to: '/features#network', description: 'Merchant ↔ provider' },
      { label: 'API', to: '/features#developers', description: 'Integrate your stack' },
      { label: 'Analytics', to: '/features#control', description: 'Reports and KPIs' },
    ],
  },
]

/** @deprecated use columns; flat list for mobile accordion */
export const MARKETING_PRODUCT_LINKS: MarketingNavLink[] = MARKETING_PRODUCT_MEGA_COLUMNS.flatMap((c) => c.links)

export const MARKETING_COMPANY_LINKS: MarketingNavLink[] = [
  { label: 'About', to: '/about' },
  { label: 'Contact', to: '/contact' },
  { label: 'Partners', to: '/partners' },
  { label: 'Status', to: '/status' },
]

export const MARKETING_PRIMARY_NAV = [
  { id: 'product', label: 'Product', mega: 'product' as const, to: MARKETING_PRODUCT_TOUR_HREF },
  { id: 'solutions', label: 'Solutions', to: '/solutions' },
  { id: 'pricing', label: 'Pricing', to: '/pricing' },
  { id: 'developers', label: 'Developers', to: '/developers' },
  { id: 'security', label: 'Security', to: '/security' },
  { id: 'company', label: 'Company', mega: 'company' as const },
]

export function isFeaturesRoute(pathname: string): boolean {
  return pathname === '/features' || pathname.startsWith('/features/')
}

export function isProductNavActive(pathname: string): boolean {
  return isFeaturesRoute(pathname)
}
