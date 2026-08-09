const DEFAULT_TITLE = 'DeliveryOS — The operating system for modern delivery businesses'
const DEFAULT_DESCRIPTION =
  'Manage dispatch, riders, live tracking, customers, COD, fleet operations, and logistics from one platform. Powered by MTN.'

export function setPageMeta(options: {
  title?: string
  description?: string
  path?: string
}) {
  const title = options.title ? `${options.title} · DeliveryOS` : DEFAULT_TITLE
  const description = options.description ?? DEFAULT_DESCRIPTION
  document.title = title

  setMetaTag('name', 'description', description)
  setMetaTag('property', 'og:title', title)
  setMetaTag('property', 'og:description', description)
  setMetaTag('name', 'twitter:title', title)
  setMetaTag('name', 'twitter:description', description)

  if (options.path) {
    const origin = window.location.origin
    setMetaTag('property', 'og:url', `${origin}${options.path}`)
    let link = document.querySelector<HTMLLinkElement>('link[rel="canonical"]')
    if (!link) {
      link = document.createElement('link')
      link.rel = 'canonical'
      document.head.appendChild(link)
    }
    link.href = `${origin}${options.path}`
  }
}

function setMetaTag(attr: 'name' | 'property', key: string, content: string) {
  let el = document.querySelector<HTMLMetaElement>(`meta[${attr}="${key}"]`)
  if (!el) {
    el = document.createElement('meta')
    el.setAttribute(attr, key)
    document.head.appendChild(el)
  }
  el.content = content
}
