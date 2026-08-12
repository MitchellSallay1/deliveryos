/** Pure, DOM-free logic backing the install promotion UX — kept separate so it's testable in this repo's `node`-environment test suite. */

export const INSTALL_DISMISS_COOLDOWN_MS = 14 * 24 * 60 * 60 * 1000 // 14 days, local-only.

/** Whether a prior dismissal is still within its cooldown window. */
export function isWithinDismissalCooldown(
  dismissedAt: number | null,
  now: number,
  cooldownMs: number = INSTALL_DISMISS_COOLDOWN_MS,
): boolean {
  return dismissedAt != null && now - dismissedAt < cooldownMs
}

/**
 * Routes safe for an UNPROMPTED install promotion to appear on — an
 * allowlist, not a denylist, so a route added later is excluded by default
 * rather than accidentally interrupting a workflow no one thought to block.
 * Never OTP entry, checkout, vendor order handling, rider delivery
 * transitions, or any admin/financial screen.
 */
export function isSafeRouteForInstallPromotion(pathname: string): boolean {
  if (pathname === '/') return true
  if (pathname === '/dashboard') return true
  if (pathname === '/orders') return true // customer order history — not /store/:slug/checkout
  if (/^\/store\/[^/]+$/.test(pathname)) return true // storefront browsing — not its /checkout subroute
  return false
}
