import path from 'node:path'
import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'
import { VitePWA } from 'vite-plugin-pwa'

export default defineConfig({
  plugins: [
    react(),
    tailwindcss(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['favicon.svg'],
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
        name: 'DeliveryOS Rider',
        short_name: 'DeliveryOS',
        description: 'Field delivery operations for riders and dispatchers',
        theme_color: '#FFCB05',
        background_color: '#ffffff',
        display: 'standalone',
        start_url: '/',
        icons: [
          {
            src: '/favicon.svg',
            sizes: 'any',
            type: 'image/svg+xml',
            purpose: 'any',
          },
        ],
      },
      workbox: {
        navigateFallback: '/index.html',
        globPatterns: ['**/*.{js,css,html,ico,svg,woff2}'],
        runtimeCaching: [
          {
            urlPattern: /^https:\/\/.*\.supabase\.co\/rest\/v1\/.*/i,
            handler: 'NetworkOnly',
          },
        ],
      },
    }),
  ],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  build: {
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
})
