# Public website

DeliveryOS marketing site lives in the same Vite SPA as the authenticated product — one build, served on both `https://delivoslib.com` (canonical, indexable) and `https://app.delivoslib.com` (operational app, deliberately noindexed). See [SEO.md](./SEO.md) for the domain/indexing strategy and how marketing routes are prerendered to real static HTML for crawlers.

## Routes

Public pages use `MarketingLayout` (header + footer) and do **not** require login.

| Path | Page |
|------|------|
| `/` | Landing (guests) or redirect to app home (signed in) |
| `/features` | Product features |
| `/solutions` | Industry solutions |
| `/pricing` | Plans + comparison |
| `/about` | About |
| `/contact` | Contact form |
| `/faq` | FAQ |
| `/security` | Security overview |
| `/terms` | Terms (legal draft) |
| `/privacy` | Privacy (legal draft) |
| `/status` | Service status placeholders |
| `/developers` | API pointers |
| `/partners` | Partner narrative |

Auth CTAs: `/register` (trial), `/login` (phone OTP).

## Architecture

- **Layout:** `src/layouts/MarketingLayout.tsx`
- **Components:** `src/components/marketing/*`
- **Branding:** `BrandingProvider` + `BrandLogo` / Powered by MTN
- **SEO:** every route above is registered in `src/lib/seo/routes.ts` and prerendered to real static HTML at build time — see [SEO.md](./SEO.md) for the full system (metadata registry, JSON-LD, sitemap, robots.txt, domain/noindex strategy). Client-side tag updates still go through `src/lib/page-meta.ts` / `usePageMeta`; `index.html` provides fallback defaults only.
- **Pricing data:** `listPublicPlans()` with anon RLS policy (`20260308170000_public_plans_read.sql`) and `PLAN_CATALOG_FALLBACK`
- **Contact:** `VITE_CONTACT_FORM_URL` optional POST endpoint; otherwise provider-ready message

## Performance

Marketing routes are lazy-loaded in `App.tsx`. No Leaflet on homepage. Product preview uses lightweight UI components only.

## Premium landing (2026)

- Art direction: `src/styles/marketing.css` (warm `#faf9f7`, charcoal sections, yellow accents)
- Hero: `MarketingHeroScene` + layered visuals in `src/components/marketing/visuals/`
- Nav: mega menus via `src/lib/marketing-nav.ts`
- Scroll reveals: `Reveal` + `prefers-reduced-motion` in `use-prefers-reduced-motion.ts`

## PWA note

Manifest `start_url` is `/` for the marketing shell. Riders should bookmark `/my-jobs` for field use.

See [MARKETING_COPY.md](./MARKETING_COPY.md).
