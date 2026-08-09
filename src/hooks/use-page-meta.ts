import { useEffect } from 'react'
import { setPageMeta } from '@/lib/page-meta'

export function usePageMeta(options: Parameters<typeof setPageMeta>[0]) {
  useEffect(() => {
    setPageMeta(options)
  }, [options.title, options.description, options.path])
}
