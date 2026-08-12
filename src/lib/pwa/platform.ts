/**
 * Pure, testable PWA platform-detection helpers. Standards-based capability
 * checks are used wherever one exists; user-agent sniffing is used ONLY for
 * iOS/iPadOS, which never fires `beforeinstallprompt` and exposes no
 * capability API to detect Add-to-Home-Screen support — this is the one
 * unavoidable case, isolated here rather than scattered across components.
 */

/** True once launched from the home screen / installed shortcut, on any platform. */
export function isStandaloneDisplayMode(win?: Window): boolean {
  // Default parameters evaluate `window` eagerly even when an argument is
  // passed, which throws ReferenceError in Node (build-time SEO
  // prerendering — see scripts/prerender.mjs — has no `window` global).
  // This provider is instantiated on every marketing page during that
  // render, so the check must be safe there, not just in the browser.
  const w = win ?? (typeof window === 'undefined' ? undefined : window)
  if (!w) return false
  const matchesDisplayMode = typeof w.matchMedia === 'function' && w.matchMedia('(display-mode: standalone)').matches
  // iOS Safari has no `display-mode: standalone` media query support in all
  // versions; `navigator.standalone` is its own long-standing, non-standard
  // signal for the same state.
  const iosStandalone = (w.navigator as Navigator & { standalone?: boolean }).standalone === true
  return matchesDisplayMode || iosStandalone
}

/**
 * iOS/iPadOS detection. iPadOS 13+ reports as "MacIntel" in the UA string,
 * so touch-point count disambiguates it from a real Mac (which has none).
 */
export function isIosDevice(nav?: Navigator): boolean {
  // Same Node-safety concern as isStandaloneDisplayMode above.
  const n = nav ?? (typeof navigator === 'undefined' ? undefined : navigator)
  if (!n) return false
  const ua = n.userAgent || ''
  const isIPhoneOrIPod = /iPhone|iPod/.test(ua)
  const isClassicIPad = /iPad/.test(ua)
  const isIPadOS13Plus = n.platform === 'MacIntel' && n.maxTouchPoints > 1
  return isIPhoneOrIPod || isClassicIPad || isIPadOS13Plus
}

/** Safari on iOS/iPadOS never emits `beforeinstallprompt` — Add to Home Screen is manual-only there. */
export function supportsBeforeInstallPrompt(win?: Window): boolean {
  const w = win ?? (typeof window === 'undefined' ? undefined : window)
  if (!w) return false
  return 'onbeforeinstallprompt' in w
}
