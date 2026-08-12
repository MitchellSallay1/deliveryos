import { useNetworkStatus } from '@/hooks/use-network-status'

/** Concise, non-noisy connectivity signal — no repeated banners while stably offline or online. */
export function NetworkStatusBanner() {
  const { isOnline, justReconnected } = useNetworkStatus()

  if (isOnline && !justReconnected) return null

  return (
    <div
      className={
        isOnline
          ? 'w-full bg-emerald-600 px-4 py-1.5 text-center text-xs font-medium text-white'
          : 'w-full bg-amber-600 px-4 py-1.5 text-center text-xs font-medium text-white'
      }
      role="status"
    >
      {isOnline ? 'Back online' : "You're offline. Some DeliveryOS actions require a connection."}
    </div>
  )
}
