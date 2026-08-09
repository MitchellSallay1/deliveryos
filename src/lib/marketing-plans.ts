import { formatLrdFromCents } from '@/utils/delivery-schemas'

export type PublicPlanRow = {
  id: string
  slug: string
  name: string
  price_lrd_cents: number
  currency?: string | null
  max_riders: number
  max_deliveries_per_month: number | null
  monthly_sms_allowance?: number | null
  proof_of_delivery?: boolean | null
  advanced_reports?: boolean | null
  api_access?: boolean | null
  gps_tracking?: boolean | null
  custom_branding?: boolean | null
}

/** Seed-aligned fallback when Supabase is unreachable (matches initial migration defaults). */
export const PLAN_CATALOG_FALLBACK: PublicPlanRow[] = [
  {
    id: 'fallback-starter',
    slug: 'starter',
    name: 'Starter',
    price_lrd_cents: 200_000,
    max_riders: 5,
    max_deliveries_per_month: 200,
    monthly_sms_allowance: 100,
    proof_of_delivery: true,
    advanced_reports: false,
    api_access: false,
    gps_tracking: true,
    custom_branding: false,
  },
  {
    id: 'fallback-business',
    slug: 'business',
    name: 'Business',
    price_lrd_cents: 500_000,
    max_riders: 20,
    max_deliveries_per_month: null,
    monthly_sms_allowance: 500,
    proof_of_delivery: true,
    advanced_reports: true,
    api_access: true,
    gps_tracking: true,
    custom_branding: false,
  },
  {
    id: 'fallback-enterprise',
    slug: 'enterprise',
    name: 'Enterprise',
    price_lrd_cents: 0,
    max_riders: 2147483647,
    max_deliveries_per_month: null,
    monthly_sms_allowance: null,
    proof_of_delivery: true,
    advanced_reports: true,
    api_access: true,
    gps_tracking: true,
    custom_branding: true,
  },
]

export function formatPublicPlanPrice(plan: PublicPlanRow): string {
  if (plan.slug === 'enterprise' && plan.price_lrd_cents <= 0) {
    return 'Contact us'
  }
  return formatLrdFromCents(plan.price_lrd_cents)
}

export function formatPlanLimit(value: number | null | undefined, unlimitedLabel = 'Unlimited'): string {
  if (value == null) return unlimitedLabel
  if (value >= 1_000_000) return unlimitedLabel
  return String(value)
}
