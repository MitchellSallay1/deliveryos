/**
 * Single source of truth for site-wide SEO facts. Every value here must be
 * real and currently true — this file feeds meta tags, JSON-LD, and the
 * sitemap, so a fabricated or aspirational value here becomes a fabricated
 * or aspirational claim in search results.
 */

/** Canonical public marketing domain — see docs/PRODUCTION_RUNBOOK.md "Domains". */
export const SITE_URL = 'https://delivoslib.com'

/** Operational application domain — deliberately excluded from indexing. */
export const APP_URL = 'https://app.delivoslib.com'

export const SITE_NAME = 'DeliveryOS'

export const DEFAULT_TITLE = 'DeliveryOS — Delivery management software for Liberia'

export const DEFAULT_DESCRIPTION =
  'DeliveryOS is delivery and logistics operations software for dispatch, riders, live tracking, cash-on-delivery, and vendor commerce — built for delivery businesses and merchants in Monrovia and across Liberia.'

/** 1200x630 — the universally-supported OG/Twitter preview image size. */
export const DEFAULT_OG_IMAGE = `${SITE_URL}/og-image.png`
export const OG_IMAGE_WIDTH = 1200
export const OG_IMAGE_HEIGHT = 630

/**
 * Hostnames that must never be indexed, regardless of which path is
 * requested — the operational app, and any Vercel preview/deployment URL.
 * Checked against `window.location.hostname` (client) and used to decide
 * the X-Robots-Tag / robots.txt strategy (vercel.json, docs).
 */
export function isNonCanonicalHost(hostname: string): boolean {
  if (hostname === 'app.delivoslib.com') return true
  // Vercel preview/production deployment URLs, e.g. *.vercel.app.
  if (hostname.endsWith('.vercel.app')) return true
  return false
}
