/** Public marketing routes (no auth required). */
export const PUBLIC_MARKETING_PATHS = [
  '/',
  '/features',
  '/solutions',
  '/pricing',
  '/about',
  '/contact',
  '/faq',
  '/security',
  '/terms',
  '/privacy',
  '/status',
  '/developers',
  '/partners',
] as const

export type PublicMarketingPath = (typeof PUBLIC_MARKETING_PATHS)[number]

export const MARKETING_CTA_REGISTER = '/register'
export const MARKETING_CTA_LOGIN = '/login'
