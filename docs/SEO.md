# SEO & search engine discovery

Canonical marketing domain: **`https://delivoslib.com`**. Operational app: **`https://app.delivoslib.com`** — deliberately excluded from search indexing (see "Domains" below). `www.delivoslib.com` redirects to the apex.

## One build, two domains

`delivoslib.com` and `app.delivoslib.com` are **the same Vite SPA build** — one `dist/` output, aliased to both custom domains in Vercel. There is no separate marketing site deployment. This is why the domain strategy below leans on Vercel host-conditional rules (`vercel.json`) rather than build-time branching: the build doesn't know which domain a request came in on, but Vercel's edge does.

## The SPA crawlability problem, and what we did about it

Before this work, every route — marketing or app — served the exact same static `index.html`, with `<title>`/meta tags updated only after React mounted and ran a `useEffect` (`src/lib/page-meta.ts`). Two real problems followed from that:

1. **Social-preview crawlers never run JavaScript.** WhatsApp, Facebook, LinkedIn, and X all fetch a URL once and parse the raw HTML for `og:*`/`twitter:*` tags — they never wait for a script to load. Client-side-only meta tags are invisible to them; every shared link would have shown the same generic homepage preview regardless of which page was shared.
2. **Google's crawler does run JS, but on a delayed second pass**, and other engines (Bing, etc.) are inconsistent about it. Relying on it entirely for indexing is a real risk, not a theoretical one.

We did **not** migrate to Next.js or add SSR to the authenticated app (there was no technical justification strong enough for that — see the report from this phase for the full reasoning). Instead:

- **`src/entry-server.tsx`** renders each public marketing page to a real HTML string at build time via `react-dom/server`'s `renderToString`, wrapped in the same header/footer/providers the browser uses (a `StaticRouter` in place of `BrowserRouter`, a fresh `QueryClientProvider`, `BrandingProvider`, and a Node-safe `PwaInstallProvider` — see `src/lib/pwa/platform.ts`, which now tolerates a missing `window`/`navigator`).
- **`scripts/prerender.mjs`** runs after both the client build (`vite build`) and a dedicated SSR build (`vite build --ssr src/entry-server.tsx --outDir dist-ssr`, wired into `npm run build`). For each route it takes the built `dist/index.html` shell and writes a real static file — `dist/index.html` for `/`, `dist/<route>/index.html` for everything else — with the actual page content in `<div id="root">` and page-specific `<title>`/meta/canonical/OG/Twitter/JSON-LD baked into `<head>`.
- Vercel serves `dist/<route>/index.html` for a request to `/<route>` via ordinary static-file/directory-index resolution — the SPA catch-all rewrite in `vercel.json` only kicks in for paths that don't already exist as a file (in-app client-side navigation to these routes is completely unaffected; React still owns them once JS loads and hydrates).

All 13 public marketing routes (`/`, `/features`, `/solutions`, `/pricing`, `/about`, `/contact`, `/faq`, `/security`, `/status`, `/developers`, `/partners`, `/terms`, `/privacy`) render successfully this way — none needed a fallback. The authenticated app (`/dashboard`, `/admin/*`, `/vendor/*`, etc.) is untouched: still a pure client-rendered SPA, and deliberately noindexed anyway (see below), so there was nothing to gain by prerendering it.

## Page metadata system

One registry, two consumers — they can't drift apart:

- **`src/lib/seo/routes.ts`** — `SEO_ROUTES`: path, title, description, breadcrumb label per marketing route. Titles/descriptions are written for a human reading a search result, not for a keyword list.
- **`src/lib/seo/page-head.ts`** — `getPageHeadData(routeKey)`: adds the right JSON-LD and robots directive on top of the registry entry (home gets Organization/WebSite/SoftwareApplication, FAQ gets FAQPage from the real published Q&A in `src/pages/marketing/faq-content.ts`, `/status` is forced `noindex, follow`).
- **Client-side**: every marketing page calls `usePageMeta(getPageHeadData('key'))` (`src/hooks/use-page-meta.ts` → `src/lib/page-meta.ts`), which updates `document.title` and the meta/link/script tags in place — this matters for in-app SPA navigation between marketing pages (no full reload) and as a second, independent source of the same values.
- **Build-time**: `scripts/prerender.mjs`, via the compiled `entry-server.tsx` (which also calls `getPageHeadData`), and `src/lib/seo/html-template.ts`'s `renderMarketingHtml()` — pure string templating, no DOM dependency, unit-tested in `html-template.test.ts`.

Structured data builders (`src/lib/seo/json-ld.ts`) only ever emit fields DeliveryOS can back up today — no `aggregateRating`, `review`, `offers`, `address`, or `sameAs`. `json-ld.test.ts` asserts those keys never appear.

## Domains, robots.txt, and noindex

- **`delivoslib.com`** — `public/robots-marketing.txt`, served at `/robots.txt` via a host-conditional rewrite in `vercel.json`. Allows the marketing pages and public storefronts (`/store/:slug`); disallows login/registration, auth callback, per-delivery tracking codes, invite links, checkout, customer order history, and every authenticated-app path prefix. Points to `Sitemap: https://delivoslib.com/sitemap.xml`.
- **`www.delivoslib.com`** — 301 redirect to the apex (`vercel.json` `redirects`, host-conditional).
- **`app.delivoslib.com`** — `public/robots-app.txt` (`Disallow: /`), served the same way, **plus** an `X-Robots-Tag: noindex, nofollow` response header set for every path on that host (`vercel.json` `headers`, host-conditional). The header is the layer that actually matters — robots.txt is a hint a crawler can ignore; a response header is not, and it works even if a crawler somehow already has a URL indexed. `src/lib/page-meta.ts` adds a third, client-side layer (`isNonCanonicalHost()` in `src/lib/seo/config.ts` forces a `noindex` meta tag when `window.location.hostname` is `app.delivoslib.com` or any `*.vercel.app` preview). None of this is a security boundary — Supabase Auth/RLS remain the only thing that actually protects private data; robots.txt and noindex only keep search engines from listing pages that require login anyway.

**Why not a literal `public/robots.txt`?** Vercel serves real static files before evaluating rewrites, which would make a literal file at that exact path win over the host-conditional rewrite on *every* domain, including `app.delivoslib.com`. The two source files are named `robots-marketing.txt` / `robots-app.txt` specifically so no literal `/robots.txt` file exists to shadow the rewrite.

**Verify in a Preview deployment before this is live** — this repo's existing convention (see `docs/PRODUCTION_RUNBOOK.md` re: the CSP) — specifically: `curl -I https://<preview>/robots.txt` with a `Host: app.delivoslib.com` override, and confirm the `X-Robots-Tag` header appears only on the app host.

## Sitemap

`public/sitemap.xml` — static, hand-maintained, lists the 13 canonical marketing URLs (`/status` is excluded — it's noindex). This is deliberately simple: the marketing route set is small and fixed, so a generator would be pure overhead right now.

**Future work, not built**: public vendor storefronts (`/store/:slug`) are crawlable per robots.txt but have no sitemap entries yet. When storefronts should be actively promoted in search, add a job (build-time or a small serverless function) that lists active, publicly-visible vendor slugs — companies with `commerce_enabled` and a published storefront — and either appends them to this file or serves them from a separate `/sitemap-stores.xml` referenced by a sitemap index. Do not hand-maintain a per-vendor list.

## Social sharing

`public/og-image.png` (1200×630, generated once from an SVG via a one-time local `sharp` install — same pattern used for the PWA icons; `sharp` is not a project dependency) is referenced by every page's `og:image`/`twitter:image` (`twitter:card` is `summary_large_image`). Because it's baked into the prerendered `<head>` of every marketing page, WhatsApp/Facebook/LinkedIn/X previews work correctly per-page, not just on the homepage.

## Search Console / Bing Webmaster Tools

Not yet configured — no verification token exists to put anywhere, and none is fabricated here. Once `delivoslib.com` is live and DNS-verified in Vercel:

1. **Google Search Console**: add the property, verify via the HTML tag method (Google gives you a `<meta name="google-site-verification" content="...">` value) or DNS TXT record. If using the meta-tag method, add it to `index.html`'s `<head>` — it's a static value, no code change beyond that one line — **and** it needs to survive `scripts/prerender.mjs`'s templating (it's not one of the tags that function replaces, so it will pass through untouched). Then submit `https://delivoslib.com/sitemap.xml`.
2. **Bing Webmaster Tools**: same shape — either import the already-verified Search Console property, or verify independently via an XML/meta tag Bing provides, then submit the same sitemap URL.

## What was deliberately not done

- No dynamic per-vendor storefront sitemap (see "Sitemap" above).
- No redirect from `app.delivoslib.com/<marketing-route>` to the canonical `delivoslib.com` equivalent — those paths are noindexed (robots.txt + `X-Robots-Tag`), which fully solves the indexing/duplicate-content problem; a redirect would add more `vercel.json` surface for a case (someone directly visiting a marketing URL on the app subdomain) that essentially never happens today.
- No SSR/prerendering for the authenticated app — it's noindexed anyway, and there is no crawlability problem worth solving for pages nobody but a logged-in user should ever see.
