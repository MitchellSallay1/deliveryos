/** Prevent open redirects after login (internal paths only). */
export function safeInternalRedirect(path: string | null | undefined): string | null {
  if (!path) return null
  const trimmed = path.trim()
  if (!trimmed.startsWith('/') || trimmed.startsWith('//')) return null
  if (trimmed.includes('://')) return null
  return trimmed
}
