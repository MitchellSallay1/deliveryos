import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react'
import { isIosDevice, isStandaloneDisplayMode } from '@/lib/pwa/platform'
import { isWithinDismissalCooldown } from '@/lib/pwa/install-state'

/** Not yet in TS's lib.dom.d.ts. */
interface BeforeInstallPromptEvent extends Event {
  readonly platforms: string[]
  readonly userChoice: Promise<{ outcome: 'accepted' | 'dismissed'; platform: string }>
  prompt(): Promise<void>
}

const DISMISS_STORAGE_KEY = 'deliveryos:pwa-install-dismissed-at'

type PwaInstallState = {
  /** True once launched from the home screen — never show install UI in this state. */
  isStandalone: boolean
  /** True when the browser has offered a native install prompt we can trigger on demand. */
  canPromptInstall: boolean
  /** iOS/iPadOS never fires beforeinstallprompt — Add to Home Screen is manual-only there. */
  isIos: boolean
  /** True if the user dismissed an install promotion within the cooldown window. */
  isRecentlyDismissed: boolean
  /** Triggers the native browser prompt. No-op (returns 'unavailable') if none is currently available. */
  promptInstall: () => Promise<'accepted' | 'dismissed' | 'unavailable'>
  /** Records a local, timestamped dismissal so promotional UI backs off for the cooldown window. */
  dismissPromotion: () => void
}

const PwaInstallContext = createContext<PwaInstallState | null>(null)

function readDismissedAt(): number | null {
  try {
    const raw = window.localStorage.getItem(DISMISS_STORAGE_KEY)
    return raw ? Number(raw) : null
  } catch {
    return null
  }
}

export function PwaInstallProvider({ children }: { children: React.ReactNode }) {
  const [deferredPrompt, setDeferredPrompt] = useState<BeforeInstallPromptEvent | null>(null)
  const [isStandalone, setIsStandalone] = useState(() => isStandaloneDisplayMode())
  const [dismissedAt, setDismissedAt] = useState<number | null>(() => readDismissedAt())

  useEffect(() => {
    function onBeforeInstallPrompt(e: Event) {
      // Do not interrupt the visitor: capture the event for later, on-demand
      // use rather than showing the browser's default mini-infobar-adjacent UI.
      e.preventDefault()
      setDeferredPrompt(e as BeforeInstallPromptEvent)
    }
    function onAppInstalled() {
      setDeferredPrompt(null)
      setIsStandalone(true)
    }
    window.addEventListener('beforeinstallprompt', onBeforeInstallPrompt)
    window.addEventListener('appinstalled', onAppInstalled)
    return () => {
      window.removeEventListener('beforeinstallprompt', onBeforeInstallPrompt)
      window.removeEventListener('appinstalled', onAppInstalled)
    }
  }, [])

  useEffect(() => {
    if (typeof window.matchMedia !== 'function') return
    const mql = window.matchMedia('(display-mode: standalone)')
    const onChange = () => setIsStandalone(isStandaloneDisplayMode())
    mql.addEventListener('change', onChange)
    return () => mql.removeEventListener('change', onChange)
  }, [])

  const promptInstall = useCallback(async (): Promise<'accepted' | 'dismissed' | 'unavailable'> => {
    if (!deferredPrompt) return 'unavailable'
    await deferredPrompt.prompt()
    const { outcome } = await deferredPrompt.userChoice
    // A captured prompt event can only be used once — clear it either way.
    setDeferredPrompt(null)
    if (outcome === 'dismissed') {
      setDismissedAt(Date.now())
      try {
        window.localStorage.setItem(DISMISS_STORAGE_KEY, String(Date.now()))
      } catch {
        // Best-effort only — a lost dismissal preference just means the
        // promotion may reappear sooner, never a functional break.
      }
    }
    return outcome
  }, [deferredPrompt])

  const dismissPromotion = useCallback(() => {
    const now = Date.now()
    setDismissedAt(now)
    try {
      window.localStorage.setItem(DISMISS_STORAGE_KEY, String(now))
    } catch {
      // Best-effort only, see above.
    }
  }, [])

  const value = useMemo<PwaInstallState>(() => {
    const isRecentlyDismissed = isWithinDismissalCooldown(dismissedAt, Date.now())
    return {
      isStandalone,
      canPromptInstall: deferredPrompt != null,
      isIos: isIosDevice(),
      isRecentlyDismissed,
      promptInstall,
      dismissPromotion,
    }
  }, [deferredPrompt, isStandalone, dismissedAt, promptInstall, dismissPromotion])

  return <PwaInstallContext.Provider value={value}>{children}</PwaInstallContext.Provider>
}

export function usePwaInstall(): PwaInstallState {
  const ctx = useContext(PwaInstallContext)
  if (!ctx) throw new Error('usePwaInstall must be used within a PwaInstallProvider')
  return ctx
}
