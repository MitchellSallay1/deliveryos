/**
 * Pure, testable PWA platform-detection helpers. Standards-based capability
 * checks are used wherever one exists; user-agent sniffing is used ONLY for
 * iOS/iPadOS, which never fires `beforeinstallprompt` and exposes no
 * capability API to detect Add-to-Home-Screen support — this is the one
 * unavoidable case, isolated here rather than scattered across components.
 */

/** True once launched from the home screen / installed shortcut, on any platform. */
export function isStandaloneDisplayMode(win: Window = window): boolean {
  const matchesDisplayMode =
    typeof win.matchMedia === 'function' && win.matchMedia('(display-mode: standalone)').matches
  // iOS Safari has no `display-mode: standalone` media query support in all
  // versions; `navigator.standalone` is its own long-standing, non-standard
  // signal for the same state.
  const iosStandalone = (win.navigator as Navigator & { standalone?: boolean }).standalone === true
  return matchesDisplayMode || iosStandalone
}

/**
 * iOS/iPadOS detection. iPadOS 13+ reports as "MacIntel" in the UA string,
 * so touch-point count disambiguates it from a real Mac (which has none).
 */
export function isIosDevice(nav: Navigator = navigator): boolean {
  const ua = nav.userAgent || ''
  const isIPhoneOrIPod = /iPhone|iPod/.test(ua)
  const isClassicIPad = /iPad/.test(ua)
  const isIPadOS13Plus = nav.platform === 'MacIntel' && nav.maxTouchPoints > 1
  return isIPhoneOrIPod || isClassicIPad || isIPadOS13Plus
}

/** Safari on iOS/iPadOS never emits `beforeinstallprompt` — Add to Home Screen is manual-only there. */
export function supportsBeforeInstallPrompt(win: Window = window): boolean {
  return 'onbeforeinstallprompt' in win
}
