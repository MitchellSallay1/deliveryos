/** Public app origin for auth redirects (never embed secrets). */
export function getAppUrl(): string {
  const fromEnv = import.meta.env.VITE_APP_URL?.trim()
  if (fromEnv) {
    return fromEnv.replace(/\/$/, '')
  }
  if (typeof window !== 'undefined' && window.location?.origin) {
    return window.location.origin
  }
  return 'http://localhost:5173'
}

export function authCallbackUrl(): string {
  return `${getAppUrl()}/auth/callback`
}
