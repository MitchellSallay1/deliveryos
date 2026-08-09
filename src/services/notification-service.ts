import { supabase } from '@/lib/supabase/client'
import type { NotificationLog, SmsLog } from '@/types/notifications'

export async function listSmsLogs(companyId: string, limit = 50) {
  const { data, error } = await supabase
    .from('sms_logs')
    .select('*')
    .eq('company_id', companyId)
    .order('created_at', { ascending: false })
    .limit(limit)

  if (error) throw error
  return (data ?? []) as SmsLog[]
}

export async function listNotificationLogs(companyId: string, limit = 50) {
  const { data, error } = await supabase
    .from('notification_logs')
    .select('*')
    .eq('company_id', companyId)
    .order('created_at', { ascending: false })
    .limit(limit)

  if (error) throw error
  return (data ?? []) as NotificationLog[]
}
