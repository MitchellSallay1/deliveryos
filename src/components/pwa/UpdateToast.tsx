import { useRegisterSW } from 'virtual:pwa-register/react'

/**
 * The only service-worker registration point in the app (vite.config.ts
 * sets injectRegister: false so nothing double-registers, and
 * registerType: 'prompt' so a new service worker sits waiting rather than
 * taking over automatically). Update is never automatic or forced —
 * clicking "Update now" is what tells the waiting worker to activate and
 * reloads the page; until then the current tab keeps running the version
 * it started with. Not showing anything for `offlineReady`: this app does
 * not promise offline operation, so there is nothing honest to say when
 * precaching finishes.
 */
export function UpdateToast() {
  const { needRefresh: [needRefresh, setNeedRefresh], updateServiceWorker } = useRegisterSW({
    immediate: true,
  })

  if (!needRefresh) return null

  return (
    <div className="fixed inset-x-3 top-3 z-50 mx-auto max-w-sm sm:left-auto sm:right-3">
      <div className="flex items-center gap-3 rounded-xl border bg-white p-3 shadow-lg">
        <div className="flex-1">
          <p className="text-sm font-medium text-[var(--color-foreground)]">A new version of DeliveryOS is available.</p>
        </div>
        <button
          type="button"
          className="shrink-0 rounded-lg bg-[var(--color-accent)] px-3 py-1.5 text-xs font-semibold text-black hover:opacity-90"
          onClick={() => void updateServiceWorker(true)}
        >
          Update now
        </button>
        <button
          type="button"
          aria-label="Dismiss"
          className="shrink-0 text-xs text-[var(--color-muted)] hover:text-[var(--color-foreground)]"
          onClick={() => setNeedRefresh(false)}
        >
          Later
        </button>
      </div>
    </div>
  )
}
