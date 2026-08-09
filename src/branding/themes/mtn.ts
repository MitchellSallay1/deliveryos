import type { BrandTheme } from '@/branding/types'

/** MTN deployment — product remains DeliveryOS; MTN is the partner. */
export const mtnBrandTheme: BrandTheme = {
  id: 'mtn',
  productName: 'DeliveryOS',
  partner: {
    id: 'mtn',
    displayName: 'MTN',
    poweredByLabel: 'Powered by MTN',
  },
  tokens: {
    primary: '#000000',
    primaryForeground: '#ffffff',
    accent: '#FFCB05',
    sidebar: '#0a0a0a',
    sidebarForeground: '#fafafa',
    sidebarAccent: '#FFCB05',
  },
}
