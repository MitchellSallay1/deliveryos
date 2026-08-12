import { describe, expect, it } from 'vitest'
import { renderMarketingHtml } from './html-template'

const TEMPLATE = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="description" content="default description" />
    <meta property="og:type" content="website" />
    <meta property="og:title" content="default title" />
    <meta property="og:description" content="default description" />
    <meta name="twitter:card" content="summary" />
    <title>Default</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/assets/index.js"></script>
  </body>
</html>
`

describe('renderMarketingHtml', () => {
  it('sets a suffixed title by default, and the verbatim title when titleIsAbsolute', () => {
    const suffixed = renderMarketingHtml({
      template: TEMPLATE,
      bodyHtml: '<p>x</p>',
      head: { title: 'Features', path: '/features' },
      origin: 'https://delivoslib.com',
    })
    expect(suffixed).toContain('<title>Features · DeliveryOS</title>')

    const absolute = renderMarketingHtml({
      template: TEMPLATE,
      bodyHtml: '<p>x</p>',
      head: { title: 'DeliveryOS — Home', titleIsAbsolute: true, path: '/' },
      origin: 'https://delivoslib.com',
    })
    expect(absolute).toContain('<title>DeliveryOS — Home</title>')
  })

  it('replaces existing meta tags rather than duplicating them', () => {
    const html = renderMarketingHtml({
      template: TEMPLATE,
      bodyHtml: '<p>x</p>',
      head: { title: 'Pricing', description: 'Plans and pricing.', path: '/pricing' },
      origin: 'https://delivoslib.com',
    })
    expect(html.match(/<meta name="description"/g)).toHaveLength(1)
    expect(html).toContain('content="Plans and pricing."')
  })

  it('inserts og:url/og:image and canonical, which the template did not already have', () => {
    const html = renderMarketingHtml({
      template: TEMPLATE,
      bodyHtml: '<p>x</p>',
      head: { title: 'Pricing', description: 'd', path: '/pricing' },
      origin: 'https://delivoslib.com',
    })
    expect(html).toContain('<meta property="og:url" content="https://delivoslib.com/pricing" />')
    expect(html).toContain('<meta property="og:image" content="https://delivoslib.com/og-image.png" />')
    expect(html).toContain('<link rel="canonical" href="https://delivoslib.com/pricing" />')
  })

  it('defaults robots to index, follow, and honors an explicit override', () => {
    const indexed = renderMarketingHtml({
      template: TEMPLATE,
      bodyHtml: '<p>x</p>',
      head: { title: 'Features', path: '/features' },
      origin: 'https://delivoslib.com',
    })
    expect(indexed).toContain('<meta name="robots" content="index, follow" />')

    const noindexed = renderMarketingHtml({
      template: TEMPLATE,
      bodyHtml: '<p>x</p>',
      head: { title: 'Status', path: '/status', robots: 'noindex, follow' },
      origin: 'https://delivoslib.com',
    })
    expect(noindexed).toContain('<meta name="robots" content="noindex, follow" />')
  })

  it('injects one script tag per JSON-LD object, and stays idempotent across repeated calls on its own output', () => {
    const head = {
      title: 'Home',
      titleIsAbsolute: true,
      path: '/',
      jsonLd: [{ '@type': 'Organization' }, { '@type': 'WebSite' }],
    }
    const once = renderMarketingHtml({ template: TEMPLATE, bodyHtml: '<p>x</p>', head, origin: 'https://delivoslib.com' })
    expect(once.match(/application\/ld\+json/g)).toHaveLength(2)

    // Re-running against the ALREADY-prerendered output (not the original
    // template) must not accumulate a second copy of each script tag —
    // this is what makes re-running `npm run build` idempotent.
    const twice = renderMarketingHtml({ template: once, bodyHtml: '<p>x</p>', head, origin: 'https://delivoslib.com' })
    expect(twice.match(/application\/ld\+json/g)).toHaveLength(2)
  })

  it('places the rendered body inside div#root', () => {
    const html = renderMarketingHtml({
      template: TEMPLATE,
      bodyHtml: '<header>hi</header><main>content</main>',
      head: { title: 'Home', titleIsAbsolute: true, path: '/' },
      origin: 'https://delivoslib.com',
    })
    expect(html).toContain('<div id="root"><header>hi</header><main>content</main></div>')
  })

  it('escapes HTML-significant characters in titles/descriptions', () => {
    const html = renderMarketingHtml({
      template: TEMPLATE,
      bodyHtml: '<p>x</p>',
      head: { title: 'A & B <script>', path: '/x' },
      origin: 'https://delivoslib.com',
    })
    expect(html).not.toContain('<title>A & B <script></title>')
    expect(html).toContain('A &amp; B &lt;script&gt;')
  })
})
