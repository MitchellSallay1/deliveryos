export type {
  CustomerRow,
  DeliveryRow,
  RiderRow,
} from '@/types/supabase'

export type DeliveryListParams = {
  page?: number
  pageSize?: number
  search?: string
}

export type DeliveryListResult = {
  rows: import('@/types/supabase').DeliveryRow[]
  total: number
  page: number
  pageSize: number
}

export type TrackingPublic = {
  tracking_code: string
  status: string
  company_name: string
  pickup_area: string
  destination_area: string
  updated_at: string
  status_timeline?: { status: string; at: string }[]
}
