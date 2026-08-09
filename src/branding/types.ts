export type BrandPartner = {
  id: string
  displayName: string
  /** Shown as “Powered by {displayName}” */
  poweredByLabel: string
  logo?: React.ReactNode
}

export type BrandThemeTokens = {
  primary: string
  primaryForeground: string
  accent: string
  sidebar: string
  sidebarForeground: string
  sidebarAccent: string
}

export type BrandTheme = {
  id: string
  productName: string
  partner: BrandPartner | null
  tokens: BrandThemeTokens
}
