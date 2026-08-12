import { useState } from 'react'
import { useLocation } from 'react-router-dom'
import { X } from 'lucide-react'
import { usePwaInstall } from '@/hooks/use-pwa-install'
import { InstallButton } from '@/components/pwa/InstallButton'
import { isSafeRouteForInstallPromotion } from '@/lib/pwa/install-state'

/** Dismissible, mobile-only bottom-sheet install promotion. Never blocks the page beneath it. */
export function InstallPromotionBanner() {
  const { pathname } = useLocation()
  const { isStandalone, canPromptInstall, isIos, isRecentlyDismissed, dismissPromotion } = usePwaInstall()
  const [locallyDismissed, setLocallyDismissed] = useState(false)

  const installable = canPromptInstall || isIos
  const shouldShow =
    installable && !isStandalone && !isRecentlyDismissed && !locallyDismissed && isSafeRouteForInstallPromotion(pathname)

  if (!shouldShow) return null

  function onDismiss() {
    setLocallyDismissed(true)
    dismissPromotion()
  }

  return (
    <div className="fixed inset-x-3 bottom-3 z-40 sm:hidden">
      <div className="flex items-center gap-3 rounded-xl border bg-white p-3 shadow-lg">
        <div className="flex-1">
          <p className="text-sm font-medium text-[var(--color-foreground)]">Install DeliveryOS</p>
          <p className="text-xs text-[var(--color-muted)]">Add DeliveryOS to your phone for faster access.</p>
        </div>
        <InstallButton label="Install" size="sm" />
        <button
          type="button"
          aria-label="Dismiss"
          className="shrink-0 rounded-md p-1.5 text-[var(--color-muted)] hover:bg-zinc-100"
          onClick={onDismiss}
        >
          <X className="h-4 w-4" />
        </button>
      </div>
    </div>
  )
}
