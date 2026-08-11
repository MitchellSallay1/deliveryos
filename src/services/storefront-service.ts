import { supabase } from '@/lib/supabase/client'
import type { Json } from '@/types/supabase'

export type PublicStoreImage = { id: string; storage_path: string; sort_order: number }

export type PublicStoreOption = { id: string; name: string; price_delta_lrd_cents: number }

export type PublicStoreOptionGroup = {
  id: string
  name: string
  selection_type: 'single' | 'multiple'
  is_required: boolean
  sort_order: number
  options: PublicStoreOption[]
}

export type PublicStoreProduct = {
  id: string
  category_id: string | null
  name: string
  description: string | null
  price_lrd_cents: number
  currency: string
  tracks_inventory: boolean
  sort_order: number
  available: boolean
  images: PublicStoreImage[]
  option_groups: PublicStoreOptionGroup[]
}

export type PublicStoreCategory = { id: string; name: string; sort_order: number }

export type PublicStoreProfile = {
  company_id: string
  slug: string
  display_name: string
  description: string | null
  logo_url: string | null
  banner_url: string | null
  business_hours: Json
  allow_cash_on_delivery: boolean
}

export type PublicStoreCatalog = {
  store: PublicStoreProfile
  categories: PublicStoreCategory[]
  products: PublicStoreProduct[]
}

/** Returns null both when the slug does not exist and when the store is not currently publicly visible — the RPC deliberately does not distinguish the two. */
export async function fetchPublicStoreCatalog(slug: string): Promise<PublicStoreCatalog | null> {
  const { data, error } = await supabase.rpc('get_public_store_catalog', { p_slug: slug })
  if (error) throw error
  return (data as unknown as PublicStoreCatalog | null) ?? null
}

const PRODUCT_IMAGE_BUCKET = 'commerce-product-images'

export function productImagePublicUrl(storagePath: string) {
  const { data } = supabase.storage.from(PRODUCT_IMAGE_BUCKET).getPublicUrl(storagePath)
  return data.publicUrl
}
