// Runs after both `vite build` (client) and `vite build --ssr src/entry-server.tsx
// --outDir dist-ssr` (server) — see the "build" script in package.json. For
// every public marketing route it renders real HTML via entry-server's
// renderStaticPage() and writes it as a static file under dist/, so
// Vercel serves fully-formed, page-specific HTML (title, description,
// canonical, OG/Twitter tags, JSON-LD, and the actual rendered page body)
// to crawlers that never run JavaScript — this is the whole point; see
// docs/SEO.md for why client-side document.title changes are not enough.
//
// dist/index.html itself is rewritten in place for "/". Every other route
// gets dist/<route>/index.html, which Vercel's static file serving resolves
// automatically for a request to /<route> (directory-index behavior, the
// same mechanism that already made /robots.txt and /sitemap.xml work as
// plain files in public/ — verify in a Preview deployment, per this repo's
// existing convention for anything hosting-behavior-dependent).
import { readFile, writeFile, mkdir } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const rootDir = path.dirname(path.dirname(fileURLToPath(import.meta.url)))
const distDir = path.join(rootDir, 'dist')
const ssrEntry = path.join(rootDir, 'dist-ssr', 'entry-server.js')

async function main() {
  if (!existsSync(path.join(distDir, 'index.html'))) {
    throw new Error('prerender.mjs: dist/index.html not found — run `vite build` first.')
  }
  if (!existsSync(ssrEntry)) {
    throw new Error('prerender.mjs: dist-ssr/entry-server.js not found — run the SSR build first.')
  }

  const template = await readFile(path.join(distDir, 'index.html'), 'utf8')
  const { SSR_PATHS, renderStaticPage } = await import(pathToFileUrl(ssrEntry))

  let ok = 0
  for (const route of SSR_PATHS) {
    const html = renderStaticPage(route, template)
    const outPath = route === '/' ? path.join(distDir, 'index.html') : path.join(distDir, route.slice(1), 'index.html')
    await mkdir(path.dirname(outPath), { recursive: true })
    await writeFile(outPath, html, 'utf8')
    ok += 1
  }

  console.log(`prerender.mjs: wrote ${ok}/${SSR_PATHS.length} static marketing pages.`)
}

function pathToFileUrl(p) {
  return new URL(`file://${p.replace(/\\/g, '/')}`).href
}

main().catch((err) => {
  console.error(err)
  process.exitCode = 1
})
