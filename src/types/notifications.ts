export type SmsLog = {
  id: string
  company_id: string
  direction: 'outbound' | 'inbound'
  phone: string
  body: string
  credits_used: number
  delivery_id: string | null
  created_at: string
}

export type NotificationLog = {
  id: string
  company_id: string | null
  channel: string
  recipient: string
  body: string
  status: string
  created_at: string
}
