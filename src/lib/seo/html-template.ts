import type { PageMetaOptions } from '@/lib/page-meta'
import type { JsonLd } from './json-ld'
import { OG_IMAGE_HEIGHT, OG_IMAGE_WIDTH, SITE_NAME } from './config'

/**
 * Pure string-templating used by scripts/prerender.mjs (via the compiled
 * src/entry-server.tsx bundle) to turn the built dist/index.html shell into
 * a real, page-specific static HTML file: title/description/canonical/OG/
 * Twitter/robots/JSON-LD baked into <head>, and the server-rendered page
 * markup baked into <div id="root">. No DOM — index.html is small and
 * well-formed, so targeted regex replacement is simpler and has no jsdom/
 * linkedom dependency to add.
 */
export function renderMarketingHtml(params: {
  template: string
  bodyHtml: string
  head: PageMetaOptions
  origin: string
}): string {
  const { template, bodyHtml, head, origin } = params
  const title = head.title ? (head.titleIsAbsolute ? head.title : `${head.title} · ${SITE_NAME}`) : SITE_NAME
  const description = head.description ?? ''
  const canonical = `${origin}${head.path ?? ''}`
  const robots = head.robots ?? 'index, follow'
  const ogType = head.ogType ?? 'website'
  const ogImage = `${origin}/og-image.png`

  let html = template

  html = replaceTitle(html, title)
  html = setMeta(html, 'name', 'description', description)
  html = setMeta(html, 'name', 'robots', robots)
  html = setMeta(html, 'property', 'og:site_name', SITE_NAME)
  html = setMeta(html, 'property', 'og:type', ogType)
  html = setMeta(html, 'property', 'og:title', title)
  html = setMeta(html, 'property', 'og:description', description)
  html = setMeta(html, 'property', 'og:url', canonical)
  html = setMeta(html, 'property', 'og:image', ogImage)
  html = setMeta(html, 'property', 'og:image:width', String(OG_IMAGE_WIDTH))
  html = setMeta(html, 'property', 'og:image:height', String(OG_IMAGE_HEIGHT))
  html = setMeta(html, 'name', 'twitter:card', 'summary_large_image')
  html = setMeta(html, 'name', 'twitter:title', title)
  html = setMeta(html, 'name', 'twitter:description', description)
  html = setMeta(html, 'name', 'twitter:image', ogImage)
  html = setCanonicalLink(html, canonical)
  html = setJsonLd(html, head.jsonLd)
  html = setRootContent(html, bodyHtml)

  return html
}

function escapeAttr(value: string): string {
  return value.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
}

function replaceTitle(html: string, title: string): string {
  const tag = `<title>${escapeAttr(title)}</title>`
  if (/<title>.*?<\/title>/.test(html)) {
    return html.replace(/<title>.*?<\/title>/, tag)
  }
  return html.replace('</head>', `  ${tag}\n  </head>`)
}

function setMeta(html: string, attr: 'name' | 'property', key: string, content: string): string {
  const pattern = new RegExp(`<meta\\s+${attr}="${escapeRegex(key)}"\\s+content="[^"]*"\\s*/?>`)
  const tag = `<meta ${attr}="${key}" content="${escapeAttr(content)}" />`
  if (pattern.test(html)) {
    return html.replace(pattern, tag)
  }
  return html.replace('</head>', `  ${tag}\n  </head>`)
}

function setCanonicalLink(html: string, href: string): string {
  const pattern = /<link\s+rel="canonical"\s+href="[^"]*"\s*\/?>/
  const tag = `<link rel="canonical" href="${escapeAttr(href)}" />`
  if (pattern.test(html)) {
    return html.replace(pattern, tag)
  }
  return html.replace('</head>', `  ${tag}\n  </head>`)
}

function setJsonLd(html: string, items: JsonLd[] | undefined): string {
  // Idempotent: strip any previously-injected block before re-inserting, so
  // re-running prerender against the same dist/index.html template never
  // accumulates duplicate <script> tags.
  const stripped = html.replace(/\s*<script type="application\/ld\+json" data-seo="prerender">[\s\S]*?<\/script>/g, '')
  if (!items || items.length === 0) return stripped
  const scripts = items
    .map((item) => `  <script type="application/ld+json" data-seo="prerender">${JSON.stringify(item)}</script>`)
    .join('\n')
  return stripped.replace('</head>', `${scripts}\n  </head>`)
}

function setRootContent(html: string, bodyHtml: string): string {
  return html.replace('<div id="root"></div>', `<div id="root">${bodyHtml}</div>`)
}

function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}
