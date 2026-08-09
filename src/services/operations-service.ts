import { supabase } from '@/lib/supabase/client'
import type { Json } from '@/types/supabase'

export async function listBranches(companyId: string) {
  const { data, error } = await supabase.rpc('list_company_branches', { p_company_id: companyId })
  if (error) throw error
  return data ?? []
}

export async function upsertBranch(payload: Json) {
  const { data, error } = await supabase.rpc('upsert_company_branch', { p_payload: payload })
  if (error) throw error
  return data
}

export async function listVehiclesPage(companyId: string, search: string, page: number) {
  const { data, error } = await supabase.rpc('list_vehicles_page', {
    p_company_id: companyId,
    p_search: search || null,
    p_limit: 25,
    p_offset: (page - 1) * 25,
  })
  if (error) throw error
  return data as { total: number; rows: Json[] }
}

export async function upsertVehicle(payload: Json) {
  const { data, error } = await supabase.rpc('upsert_vehicle', { p_payload: payload })
  if (error) throw error
  return data
}

export async function assignRiderVehicle(riderId: string, vehicleId: string) {
  const { data, error } = await supabase.rpc('assign_rider_vehicle', {
    p_rider_id: riderId,
    p_vehicle_id: vehicleId,
  })
  if (error) throw error
  return data
}

export async function recordMaintenance(payload: Json) {
  const { data, error } = await supabase.rpc('record_vehicle_maintenance', { p_payload: payload })
  if (error) throw error
  return data
}

export async function listWarehouses(companyId: string) {
  const { data, error } = await supabase
    .from('warehouses')
    .select('*')
    .eq('company_id', companyId)
    .eq('is_active', true)
    .order('name')
  if (error) throw error
  return data ?? []
}

export async function upsertWarehouse(payload: Json) {
  const { data, error } = await supabase.rpc('upsert_warehouse', { p_payload: payload })
  if (error) throw error
  return data
}

export async function listInventoryItems(companyId: string) {
  const { data, error } = await supabase
    .from('inventory_items')
    .select('*')
    .eq('company_id', companyId)
    .eq('is_active', true)
    .order('name')
  if (error) throw error
  return data ?? []
}

export async function upsertInventoryItem(payload: Json) {
  const { data, error } = await supabase.rpc('upsert_inventory_item', { p_payload: payload })
  if (error) throw error
  return data
}

export async function receiveStock(
  warehouseId: string,
  itemId: string,
  quantity: number,
  notes?: string,
) {
  const { data, error } = await supabase.rpc('inventory_receive_stock', {
    p_warehouse_id: warehouseId,
    p_item_id: itemId,
    p_quantity: quantity,
    p_notes: notes ?? null,
  })
  if (error) throw error
  return data
}

export async function listStock(companyId: string) {
  const { data, error } = await supabase
    .from('inventory_stock')
    .select('*, inventory_items(name, sku), warehouses(name, code)')
    .eq('company_id', companyId)
  if (error) throw error
  return data ?? []
}

export async function listMovements(companyId: string, limit = 50) {
  const { data, error } = await supabase
    .from('inventory_movements')
    .select('*')
    .eq('company_id', companyId)
    .order('created_at', { ascending: false })
    .limit(limit)
  if (error) throw error
  return data ?? []
}

export async function createCashSettlement(riderId: string) {
  const { data, error } = await supabase.rpc('create_cash_settlement', { p_rider_id: riderId })
  if (error) throw error
  return data
}

export async function submitCashSettlement(settlementId: string, receivedCents: number) {
  const { data, error } = await supabase.rpc('submit_cash_settlement', {
    p_settlement_id: settlementId,
    p_received_cents: receivedCents,
  })
  if (error) throw error
  return data
}

export async function reconcileCashSettlement(settlementId: string) {
  const { data, error } = await supabase.rpc('reconcile_cash_settlement', {
    p_settlement_id: settlementId,
  })
  if (error) throw error
  return data
}

export async function listCashSettlements(companyId: string) {
  const { data, error } = await supabase
    .from('cash_settlements')
    .select('*, riders(full_name, rider_code)')
    .eq('company_id', companyId)
    .order('created_at', { ascending: false })
    .limit(50)
  if (error) throw error
  return data ?? []
}

export async function getProfitability(companyId: string, branchId: string | null, days = 30) {
  const { data, error } = await supabase.rpc('get_profitability_report', {
    p_company_id: companyId,
    p_branch_id: branchId,
    p_days: days,
  })
  if (error) throw error
  return data as Json
}

export async function requestReturn(deliveryId: string, reason: string) {
  const { data, error } = await supabase.rpc('request_delivery_return', {
    p_delivery_id: deliveryId,
    p_reason: reason,
  })
  if (error) throw error
  return data
}
