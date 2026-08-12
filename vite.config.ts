import path from 'node:path'
import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'
import { VitePWA } from 'vite-plugin-pwa'

// isSsrBuild is true only for the dedicated `vite build --ssr src/entry-server.tsx`
// invocation (see scripts/prerender.mjs and the "build" script in package.json) —
// the normal client build (`vite build`) is completely unaffected. The SSR
// build produces a Node-runnable module used solely to prerender public
// marketing pages at build time; it must not carry the PWA plugin (which
// assumes a browser target and injects browser-only registration code) or
// the client's manualChunks splitting (meaningless for a single Node entry).
export default defineConfig(({ isSsrBuild }) => ({
  plugins: [
    react(),
    tailwindcss(),
    ...(isSsrBuild
      ? []
      : [
          VitePWA({
            // Was 'autoUpdate': the generated service worker called
            // self.skipWaiting() unconditionally, so a new version took control
            // in the background the moment it finished downloading — before any
            // user action. 'prompt' holds the new worker in a waiting state
            // until the app explicitly calls updateServiceWorker() (wired to the
            // "Update now" action in src/components/pwa/UpdateToast.tsx), so
            // activation itself — not just the page reload — is gated on the
            // user's click.
            registerType: 'prompt',
            // Registration is now handled explicitly via virtual:pwa-register/react
            // (src/components/pwa/UpdateToast.tsx) so the app can offer that real
            // "Update now" action instead of updating silently — injecting the
            // default auto-registration script here too would register the
            // service worker twice.
            injectRegister: false,
            includeAssets: ['favicon.svg', 'apple-touch-icon-180.png'],
            // Without this, vite-plugin-pwa only generates/serves the manifest
            // and service worker for a production build. In `vite dev`, the
            // manifest link in index.html then resolves via Vite's SPA fallback
            // to index.html itself (text/html), which is exactly what produced
            // "Manifest: Line: 1, column: 1, Syntax error" in the browser —
            // confirmed by requesting /manifest.webmanifest against the dev
            // server and observing Content-Type: text/html.
            devOptions: {
              enabled: true,
            },
            manifest: {
              // Was "DeliveryOS Rider" — installable by every persona now
              // (customers, vendors, carriers, riders, company users, Super
              // Admin), not just riders.
              name: 'DeliveryOS',
              short_name: 'DeliveryOS',
              description: 'DeliveryOS — dispatch, riders, tracking, COD, and Commerce in one platform.',
              theme_color: '#FFCB05',
              background_color: '#ffffff',
              display: 'standalone',
              start_url: '/',
              scope: '/',
              icons: [
                {
                  src: '/favicon.svg',
                  sizes: 'any',
                  type: 'image/svg+xml',
                  purpose: 'any',
                },
                // Rasterized from favicon.svg/maskable-icon.svg (same #FFCB05 +
                // "DO" branding) via a one-time local sharp run — see the PWA
                // report for how, and why sharp is not a project dependency.
                {
                  src: '/icon-192.png',
                  sizes: '192x192',
                  type: 'image/png',
                  purpose: 'any',
                },
                {
                  src: '/icon-512.png',
                  sizes: '512x512',
                  type: 'image/png',
                  purpose: 'any',
                },
                {
                  src: '/maskable-icon-192.png',
                  sizes: '192x192',
                  type: 'image/png',
                  purpose: 'maskable',
                },
                {
                  src: '/maskable-icon-512.png',
                  sizes: '512x512',
                  type: 'image/png',
                  purpose: 'maskable',
                },
              ],
              // Only one shortcut: it must make sense for every persona that
              // installs the app, and the manifest has no way to vary shortcuts
              // by role. "/dashboard" already resolves correctly for everyone —
              // it redirects a signed-in user to their real home (vendor/admin/
              // rider/etc. via resolvePostAuthPath) or bounces a signed-out user
              // to /login. Role-specific shortcuts ("Create delivery", "Vendor
              // orders", ...) were deliberately omitted: they would be broken or
              // misleading for every persona who isn't that one role, and the
              // manifest can't express "only show this to vendors."
              shortcuts: [
                {
                  name: 'Open DeliveryOS',
                  short_name: 'Open',
                  url: '/dashboard',
                },
              ],
            },
            workbox: {
              navigateFallback: '/index.html',
              globPatterns: ['**/*.{js,css,html,ico,svg,png,woff2}'],
              // public/marketing/*.png are large hero photos on public marketing
              // pages, not app-shell assets — precaching them (~3.5MB) would
              // bloat the service worker's initial install on exactly the
              // mobile/slow-network conditions this app cares about, for content
              // that was never meant to be available offline. Only the small
              // PWA icon PNGs at the site root should be precached.
              globIgnores: ['marketing/**'],
              runtimeCaching: [
                {
                  urlPattern: /^https:\/\/.*\.supabase\.co\/rest\/v1\/.*/i,
                  handler: 'NetworkOnly',
                },
              ],
            },
          }),
        ]),
  ],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  build: isSsrBuild
    ? undefined
    : {
        rollupOptions: {
          output: {
            manualChunks: {
              vendor: ['react', 'react-dom', 'react-router-dom'],
              supabase: ['@supabase/supabase-js'],
              query: ['@tanstack/react-query'],
            },
          },
        },
      },
}))
