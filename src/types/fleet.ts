export type Rider = {
  id: string
  company_id: string
  user_id?: string | null
  rider_code: string
  full_name: string
  phone: string
  status: string
  access_mode?: 'smartphone' | 'button_phone' | 'both'
  invite_code?: string | null
  sms_channel_enabled?: boolean
  ussd_channel_enabled?: boolean
  completed_deliveries: number
  rating: number
  created_at: string
}

export type Customer = {
  id: string
  company_id: string
  full_name: string
  phone: string
  address: string | null
  landmark: string | null
  notes: string | null
  created_at: string
}

export type CompanyPlanUsage = {
  company_id: string
  status: string
  sms_credits: number
  rider_count: number
  max_riders: number
  plan_name: string
}
