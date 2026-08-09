import { useEffect } from 'react'
import { useLocation } from 'react-router-dom'

/** Scroll to hash target after route load (e.g. /features#product-tour). */
export function useMarketingHashScroll() {
  const { pathname, hash } = useLocation()

  useEffect(() => {
    if (!hash) {
      if (pathname === '/features') {
        window.scrollTo({ top: 0, behavior: 'instant' in window ? ('instant' as ScrollBehavior) : 'auto' })
      }
      return
    }
    const id = hash.replace('#', '')
    const run = () => {
      const el = document.getElementById(id)
      if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' })
    }
    requestAnimationFrame(run)
    const t = window.setTimeout(run, 100)
    return () => window.clearTimeout(t)
  }, [pathname, hash])
}
