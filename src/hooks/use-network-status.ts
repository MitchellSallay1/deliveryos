import { useEffect, useState } from 'react'

/**
 * Browser-level connectivity only — `navigator.onLine` (and the online/
 * offline events) reflect whether the device has a network interface up,
 * NOT whether Supabase itself is reachable. Callers must not treat "online"
 * as proof a request will succeed; it only gates whether to say "you're
 * offline" versus attempting the request at all.
 */
export function useNetworkStatus(): { isOnline: boolean; justReconnected: boolean } {
  const [isOnline, setIsOnline] = useState(() => (typeof navigator === 'undefined' ? true : navigator.onLine))
  const [justReconnected, setJustReconnected] = useState(false)

  useEffect(() => {
    let reconnectTimer: ReturnType<typeof setTimeout> | undefined
    function onOnline() {
      setIsOnline(true)
      setJustReconnected(true)
      reconnectTimer = setTimeout(() => setJustReconnected(false), 4000)
    }
    function onOffline() {
      setIsOnline(false)
      setJustReconnected(false)
    }
    window.addEventListener('online', onOnline)
    window.addEventListener('offline', onOffline)
    return () => {
      window.removeEventListener('online', onOnline)
      window.removeEventListener('offline', onOffline)
      if (reconnectTimer) clearTimeout(reconnectTimer)
    }
  }, [])

  return { isOnline, justReconnected }
}
