import { useEffect } from 'react'
import { setPageMeta, type PageMetaOptions } from '@/lib/page-meta'

export function usePageMeta(options: PageMetaOptions) {
  // JSON.stringify gives the effect a stable, primitive dependency for
  // jsonLd instead of re-running on every render because callers pass a
  // fresh array/object literal each time.
  const jsonLdKey = options.jsonLd ? JSON.stringify(options.jsonLd) : ''
  useEffect(() => {
    setPageMeta(options)
  }, [options.title, options.titleIsAbsolute, options.description, options.path, options.robots, options.ogType, jsonLdKey])
}
