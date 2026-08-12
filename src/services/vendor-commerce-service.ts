import { supabase } from '@/lib/supabase/client'
import type {
  CommerceOrderFulfillmentStatus,
  CommerceOrderPaymentStatus,
  CommercePaymentMethod,
  CommerceProductStatus,
  CommerceVendorState,
  Json,
} from '@/types/supabase'

export type StoreProfile = {
  company_id: string
  slug: string
  display_name: string
  description: string | null
  logo_url: string | null
  banner_url: string | null
  business_hours: Json
  allow_cash_on_delivery: boolean
  status: CommerceVendorState
  status_reason: string | null
  reviewed_at: string | null
}

export async function fetchStoreProfile(companyId: string): Promise<StoreProfile | null> {
  // Routed through an RPC rather than a raw table read: status_reason and
  // reviewed_at are admin-internal review fields that Postgres column
  // grants can't restrict to "your own company" (grants aren't row-aware),
  // so a plain `.from('store_profiles').select(...)` would let any
  // authenticated session read them for someone else's active store.
  const { data, error } = await supabase.rpc('get_vendor_store_profile', { p_company_id: companyId })
  if (error) throw error
  if (!data || (data as { company_id: string | null }).company_id === null) return null
  return data as unknown as StoreProfile
}

export async function upsertStoreProfile(payload: {
  company_id: string
  slug?: string
  display_name?: string
  description?: string
  logo_url?: string
  banner_url?: string
  business_hours?: Record<string, unknown>
  allow_cash_on_delivery?: boolean
}) {
  const { data, error } = await supabase.rpc('upsert_store_profile', { p_payload: payload as Json })
  if (error) throw error
  return data as unknown as StoreProfile
}

export async function submitStoreProfileForReview(companyId: string) {
  const { data, error } = await supabase.rpc('submit_store_profile_for_review', { p_company_id: companyId })
  if (error) throw error
  return data as unknown as StoreProfile
}

export type ProductCategory = {
  id: string
  company_id: string
  name: string
  sort_order: number
  is_active: boolean
}

export async function fetchProductCategories(companyId: string): Promise<ProductCategory[]> {
  const { data, error } = await supabase
    .from('product_categories')
    .select('id, company_id, name, sort_order, is_active')
    .eq('company_id', companyId)
    .order('sort_order')
  if (error) throw error
  return data ?? []
}

export async function upsertProductCategory(payload: {
  id?: string
  company_id: string
  name?: string
  sort_order?: number
  is_active?: boolean
}) {
  const { data, error } = await supabase.rpc('upsert_product_category', { p_payload: payload as Json })
  if (error) throw error
  return data as unknown as ProductCategory
}

export type ProductOption = {
  id: string
  option_group_id: string
  name: string
  price_delta_lrd_cents: number
  is_active: boolean
  sort_order: number
}

export type ProductOptionGroup = {
  id: string
  product_id: string
  name: string
  selection_type: string
  is_required: boolean
  sort_order: number
  product_options: ProductOption[]
}

export type ProductImage = {
  id: string
  product_id: string
  storage_path: string
  sort_order: number
}

export type ProductStock = {
  product_id: string
  quantity_on_hand: number
  quantity_reserved: number
}

export type VendorProduct = {
  id: string
  company_id: string
  category_id: string | null
  name: string
  description: string | null
  price_lrd_cents: number
  currency: string
  status: CommerceProductStatus
  tracks_inventory: boolean
  sort_order: number
  product_categories: { name: string } | null
  product_stock: ProductStock | null
  product_images: ProductImage[]
  product_option_groups: ProductOptionGroup[]
}

export async function fetchVendorProducts(companyId: string): Promise<VendorProduct[]> {
  const { data, error } = await supabase
    .from('products')
    .select(
      `id, company_id, category_id, name, description, price_lrd_cents, currency, status, tracks_inventory, sort_order,
      product_categories(name),
      product_stock(product_id, quantity_on_hand, quantity_reserved),
      product_images(id, product_id, storage_path, sort_order),
      product_option_groups(id, product_id, name, selection_type, is_required, sort_order,
        product_options(id, option_group_id, name, price_delta_lrd_cents, is_active, sort_order))`,
    )
    .eq('company_id', companyId)
    .order('sort_order')
    .limit(500)

  if (error) throw error
  return (data ?? []) as unknown as VendorProduct[]
}

export async function upsertProduct(payload: {
  id?: string
  company_id: string
  category_id?: string | null
  name?: string
  description?: string
  price_lrd_cents?: number
  status?: CommerceProductStatus
  tracks_inventory?: boolean
  initial_quantity?: number
  sort_order?: number
}) {
  const { data, error } = await supabase.rpc('upsert_product', { p_payload: payload as Json })
  if (error) throw error
  return data
}

export async function upsertProductOptionGroup(payload: {
  product_id: string
  name: string
  selection_type?: 'single' | 'multiple'
  is_required?: boolean
  sort_order?: number
}) {
  const { data, error } = await supabase.rpc('upsert_product_option_group', { p_payload: payload as Json })
  if (error) throw error
  return data
}

export async function upsertProductOption(payload: {
  option_group_id: string
  name: string
  price_delta_lrd_cents?: number
  is_active?: boolean
  sort_order?: number
}) {
  const { data, error } = await supabase.rpc('upsert_product_option', { p_payload: payload as Json })
  if (error) throw error
  return data
}

export async function upsertProductImage(payload: { product_id: string; storage_path: string; sort_order?: number }) {
  const { data, error } = await supabase.rpc('upsert_product_image', { p_payload: payload as Json })
  if (error) throw error
  return data
}

export async function deleteProductImage(imageId: string) {
  const { error } = await supabase.rpc('delete_product_image', { p_image_id: imageId })
  if (error) throw error
}

export async function adjustProductStock(productId: string, delta: number, reason?: string) {
  const { data, error } = await supabase.rpc('adjust_product_stock', {
    p_product_id: productId,
    p_delta: delta,
    p_reason: reason,
  })
  if (error) throw error
  return data as unknown as ProductStock
}

export type VendorOverview = {
  store: StoreProfile | null
  commerce_enabled: boolean
  orders: {
    new: number
    preparing: number
    ready_for_pickup: number
    completed: number
    cancelled: number
  }
  catalog: {
    product_count: number
    out_of_stock: number
    low_stock: number
  }
}

export async function fetchVendorOverview(companyId: string): Promise<VendorOverview> {
  const { data, error } = await supabase.rpc('get_vendor_commerce_overview', { p_vendor_company_id: companyId })
  if (error) throw error
  return data as unknown as VendorOverview
}

export type VendorOrderItem = {
  id: string
  product_name: string
  unit_price_lrd_cents: number
  quantity: number
  selected_options: Array<{ name: string; price_delta_lrd_cents: number }>
  line_total_lrd_cents: number
}

export type VendorOrder = {
  id: string
  order_number: string
  customer_id: string
  vendor_company_id: string
  subtotal_lrd_cents: number
  delivery_fee_lrd_cents: number
  total_lrd_cents: number
  currency: string
  payment_method: CommercePaymentMethod
  payment_status: CommerceOrderPaymentStatus
  fulfillment_status: CommerceOrderFulfillmentStatus
  customer_name: string
  customer_phone: string
  delivery_address: string | null
  delivery_area_summary: string | null
  delivery_instructions: string | null
  delivery_id: string | null
  delivery_status: string | null
  delivery_request_id: string | null
  delivery_request_status: string | null
  pending_offers_count: number | null
  carrier_name: string | null
  cancelled_at: string | null
  cancellation_reason: string | null
  created_at: string
  items: VendorOrderItem[]
}

export async function fetchVendorOrders(
  companyId: string,
  fulfillmentStatuses: string[] | null,
  page: number,
  pageSize = 25,
): Promise<{ rows: VendorOrder[]; total: number }> {
  const { data, error } = await supabase.rpc('list_vendor_commerce_orders_page', {
    p_vendor_company_id: companyId,
    p_fulfillment_statuses: fulfillmentStatuses,
    p_limit: pageSize,
    p_offset: (page - 1) * pageSize,
  })
  if (error) throw error
  const payload = (data ?? { total: 0, rows: [] }) as unknown as { total: number; rows: VendorOrder[] }
  return { rows: payload.rows ?? [], total: payload.total ?? 0 }
}

export async function vendorAcceptOrder(orderId: string) {
  const { data, error } = await supabase.rpc('vendor_accept_commerce_order', { p_order_id: orderId })
  if (error) throw error
  return data
}

export async function requestCommerceOrderDelivery(orderId: string) {
  const { data, error } = await supabase.rpc('request_commerce_order_delivery', { p_order_id: orderId })
  if (error) throw error
  return data as unknown as { delivery_request: unknown; offers_created: number; already_existed: boolean }
}

export async function vendorRejectOrder(orderId: string, reason?: string) {
  const { data, error } = await supabase.rpc('vendor_reject_commerce_order', { p_order_id: orderId, p_reason: reason })
  if (error) throw error
  return data
}

export async function vendorMarkOrderPreparing(orderId: string) {
  const { data, error } = await supabase.rpc('vendor_mark_order_preparing', { p_order_id: orderId })
  if (error) throw error
  return data
}

export async function vendorMarkOrderReady(orderId: string) {
  const { data, error } = await supabase.rpc('vendor_mark_order_ready', { p_order_id: orderId })
  if (error) throw error
  return data
}

export type VendorBranch = {
  id: string
  company_id: string
  name: string
  code: string
  address: string | null
  city: string | null
  latitude: number | null
  longitude: number | null
  phone: string | null
  is_active: boolean
}

export async function fetchVendorBranches(companyId: string): Promise<VendorBranch[]> {
  const { data, error } = await supabase.rpc('list_company_branches', { p_company_id: companyId })
  if (error) throw error
  return (data ?? []) as unknown as VendorBranch[]
}

export async function upsertVendorBranch(payload: {
  id?: string
  company_id: string
  name?: string
  code?: string
  address?: string
  city?: string
  latitude?: number
  longitude?: number
  phone?: string
  is_active?: boolean
}) {
  const { data, error } = await supabase.rpc('upsert_company_branch', { p_payload: payload as Json })
  if (error) throw error
  return data as unknown as VendorBranch
}

// Super Admin vendor review
export type AdminVendorStoreRow = {
  company_id: string
  slug: string
  display_name: string
  status: CommerceVendorState
  status_reason: string | null
  reviewed_at: string | null
  company_name: string
  company_status: string
  product_count: number
}

export async function adminListVendorStores(params: {
  status?: string | null
  search?: string
  limit?: number
  offset?: number
}): Promise<{ total: number; rows: AdminVendorStoreRow[] }> {
  const { data, error } = await supabase.rpc('admin_list_vendor_stores', {
    p_status: params.status ?? null,
    p_search: params.search ?? null,
    p_limit: params.limit ?? 25,
    p_offset: params.offset ?? 0,
  })
  if (error) throw error
  const payload = (data ?? { total: 0, rows: [] }) as unknown as { total: number; rows: AdminVendorStoreRow[] }
  return { rows: payload.rows ?? [], total: payload.total ?? 0 }
}

export async function adminSetVendorState(companyId: string, state: CommerceVendorState, reason?: string) {
  const { data, error } = await supabase.rpc('admin_set_vendor_state', {
    p_company_id: companyId,
    p_state: state,
    p_reason: reason ?? null,
  })
  if (error) throw error
  return data as unknown as StoreProfile
}
