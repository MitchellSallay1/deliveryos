import { createContext, useContext, useEffect, useMemo, type ReactNode } from 'react'
import type { BrandTheme } from '@/branding/types'
import { defaultBrandTheme } from '@/branding/themes/default'
import { mtnBrandTheme } from '@/branding/themes/mtn'

const BrandingContext = createContext<BrandTheme>(mtnBrandTheme)

function applyThemeToDocument(theme: BrandTheme) {
  const root = document.documentElement
  root.style.setProperty('--color-primary', theme.tokens.primary)
  root.style.setProperty('--color-primary-foreground', theme.tokens.primaryForeground)
  root.style.setProperty('--color-accent', theme.tokens.accent)
  root.style.setProperty('--color-sidebar', theme.tokens.sidebar)
  root.style.setProperty('--color-sidebar-foreground', theme.tokens.sidebarForeground)
  root.style.setProperty('--color-sidebar-accent', theme.tokens.sidebarAccent)
  root.dataset.brand = theme.id
}

type BrandingProviderProps = {
  theme?: BrandTheme
  children: ReactNode
}

/** Set `VITE_BRAND_THEME=default` to use neutral branding without partner lock-in. */
function resolveTheme(): BrandTheme {
  const env = import.meta.env.VITE_BRAND_THEME as string | undefined
  if (env === 'default') return defaultBrandTheme
  return mtnBrandTheme
}

export function BrandingProvider({ theme, children }: BrandingProviderProps) {
  const resolved = useMemo(() => theme ?? resolveTheme(), [theme])

  useEffect(() => {
    applyThemeToDocument(resolved)
  }, [resolved])

  return <BrandingContext.Provider value={resolved}>{children}</BrandingContext.Provider>
}

export function useBranding() {
  return useContext(BrandingContext)
}
