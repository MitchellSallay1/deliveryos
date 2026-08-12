import { supabase } from '@/lib/supabase/client'
import type { CommerceOrderFulfillmentStatus, CommerceOrderPaymentStatus, CommercePaymentMethod, Json } from '@/types/supabase'

export type Cart = {
  id: string
  customer_id: string
  vendor_company_id: string
  status: string
  created_at: string
  updated_at: string
}

export async function getOrCreateCart(vendorCompanyId: string): Promise<Cart> {
  const { data, error } = await supabase.rpc('get_or_create_cart', { p_vendor_company_id: vendorCompanyId })
  if (error) throw error
  return data as unknown as Cart
}

export async function addCartItem(cartId: string, productId: string, quantity: number, selectedOptionIds: string[]) {
  const { data, error } = await supabase.rpc('add_cart_item', {
    p_cart_id: cartId,
    p_product_id: productId,
    p_quantity: quantity,
    p_selected_options: selectedOptionIds as unknown as Json,
  })
  if (error) throw error
  return data
}

export async function updateCartItemQuantity(cartItemId: string, quantity: number) {
  const { data, error } = await supabase.rpc('update_cart_item_quantity', { p_cart_item_id: cartItemId, p_quantity: quantity })
  if (error) throw error
  return data
}

export async function removeCartItem(cartItemId: string) {
  const { error } = await supabase.rpc('remove_cart_item', { p_cart_item_id: cartItemId })
  if (error) throw error
}

export type CartSummaryItem = {
  cart_item_id: string
  product_id: string
  product_name: string
  product_available: boolean
  unit_price_lrd_cents: number
  quantity: number
  selected_options: { name: string; price_delta_lrd_cents: number }[]
  line_total_lrd_cents: number
}

export type CartSummary = {
  cart_id: string
  vendor_company_id: string
  items: CartSummaryItem[]
  subtotal_lrd_cents: number
}

export async function fetchCartSummary(cartId: string): Promise<CartSummary> {
  const { data, error } = await supabase.rpc('get_cart_summary', { p_cart_id: cartId })
  if (error) throw error
  return data as unknown as CartSummary
}

export type SubmitOrderInput = {
  cartId: string
  customerName: string
  deliveryAddress?: string
  deliveryAreaSummary?: string
  deliveryLatitude?: number
  deliveryLongitude?: number
  deliveryInstructions?: string
  paymentMethod: 'cod'
}

export async function submitCommerceOrder(input: SubmitOrderInput) {
  const { data, error } = await supabase.rpc('submit_commerce_order', {
    p_cart_id: input.cartId,
    p_customer_name: input.customerName,
    p_delivery_address: input.deliveryAddress ?? null,
    p_delivery_area_summary: input.deliveryAreaSummary ?? null,
    p_delivery_latitude: input.deliveryLatitude ?? null,
    p_delivery_longitude: input.deliveryLongitude ?? null,
    p_delivery_instructions: input.deliveryInstructions ?? null,
    p_payment_method: input.paymentMethod,
  })
  if (error) throw error
  return data as unknown as CustomerOrder
}

export type CustomerOrderItem = {
  id: string
  product_name: string
  unit_price_lrd_cents: number
  quantity: number
  selected_options: { name: string; price_delta_lrd_cents: number }[]
  line_total_lrd_cents: number
}

export type CustomerOrder = {
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
  created_at: string
}

/**
 * Explicitly filtered to customer_id = the caller's own id, not just the
 * order id. RLS alone would also let this row through for a user who is
 * the order's VENDOR (not its customer) — e.g. a dual-role identity that
 * owns the selling company. This page renders the customer's view of an
 * order, so it must stay scoped to orders this identity actually placed,
 * never one they can merely see via a vendor relationship.
 */
export async function fetchCustomerOrder(
  orderId: string,
  customerId: string,
): Promise<(CustomerOrder & { items: CustomerOrderItem[] }) | null> {
  const { data: order, error } = await supabase
    .from('commerce_orders')
    .select(
      'id, order_number, customer_id, vendor_company_id, subtotal_lrd_cents, delivery_fee_lrd_cents, total_lrd_cents, currency, payment_method, payment_status, fulfillment_status, customer_name, customer_phone, delivery_address, delivery_area_summary, delivery_instructions, delivery_id, created_at',
    )
    .eq('id', orderId)
    .eq('customer_id', customerId)
    .maybeSingle()
  if (error) throw error
  if (!order) return null

  const { data: items, error: itemsError } = await supabase
    .from('commerce_order_items')
    .select('id, product_name, unit_price_lrd_cents, quantity, selected_options, line_total_lrd_cents')
    .eq('order_id', orderId)
    .order('created_at')
  if (itemsError) throw itemsError

  return { ...(order as unknown as CustomerOrder), items: (items ?? []) as unknown as CustomerOrderItem[] }
}

export async function fetchCustomerOrders(customerId: string): Promise<CustomerOrder[]> {
  const { data, error } = await supabase
    .from('commerce_orders')
    .select(
      'id, order_number, customer_id, vendor_company_id, subtotal_lrd_cents, delivery_fee_lrd_cents, total_lrd_cents, currency, payment_method, payment_status, fulfillment_status, customer_name, customer_phone, delivery_address, delivery_area_summary, delivery_instructions, delivery_id, created_at',
    )
    .eq('customer_id', customerId)
    .order('created_at', { ascending: false })
    .limit(100)
  if (error) throw error
  return (data ?? []) as unknown as CustomerOrder[]
}

export type StoreBrief = { company_id: string; slug: string; display_name: string; logo_url: string | null }

export async function fetchStoreBrief(companyId: string): Promise<StoreBrief | null> {
  const { data, error } = await supabase
    .from('store_profiles')
    .select('company_id, slug, display_name, logo_url')
    .eq('company_id', companyId)
    .maybeSingle()
  if (error) throw error
  return data
}

export type CarrierOffer = {
  offer_id: string
  carrier_company_id: string
  carrier_name: string
  quoted_amount_lrd_cents: number
  estimated_pickup_minutes: number | null
  status: string
  is_selected: boolean
  expires_at: string | null
}

export type CommerceOrderDeliveryStatus = {
  delivery_request: { id: string; status: string } | null
  offers: CarrierOffer[]
  delivery: {
    delivery_id: string
    tracking_code: string
    status: string
    carrier_name: string
    rider_name: string | null
  } | null
}

export async function fetchCommerceOrderDeliveryStatus(orderId: string): Promise<CommerceOrderDeliveryStatus> {
  const { data, error } = await supabase.rpc('get_commerce_order_delivery_status', { p_order_id: orderId })
  if (error) throw error
  return data as unknown as CommerceOrderDeliveryStatus
}

export async function selectCommerceDeliveryOffer(orderId: string, offerId: string) {
  const { data, error } = await supabase.rpc('select_commerce_delivery_offer', {
    p_order_id: orderId,
    p_offer_id: offerId,
  })
  if (error) throw error
  return data
}
