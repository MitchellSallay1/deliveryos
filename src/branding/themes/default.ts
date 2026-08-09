import type { BrandTheme } from '@/branding/types'

/** Neutral default — swap partner via BrandingProvider without code changes. */
export const defaultBrandTheme: BrandTheme = {
  id: 'default',
  productName: 'DeliveryOS',
  partner: null,
  tokens: {
    primary: '#171717',
    primaryForeground: '#ffffff',
    accent: '#404040',
    sidebar: '#0a0a0a',
    sidebarForeground: '#f5f5f5',
    sidebarAccent: '#ffcc00',
  },
}
