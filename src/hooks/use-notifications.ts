import { useEffect } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase/client'
import {
  listNotificationLogs,
  listSmsLogs,
} from '@/services/notification-service'

export function useSmsLogs(companyId: string | null) {
  const queryClient = useQueryClient()

  const query = useQuery({
    queryKey: ['sms-logs', companyId],
    queryFn: () => listSmsLogs(companyId!),
    enabled: !!companyId,
  })

  useEffect(() => {
    if (!companyId) return

    const channel = supabase
      .channel(`sms-logs:${companyId}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'sms_logs',
          filter: `company_id=eq.${companyId}`,
        },
        () => {
          void queryClient.invalidateQueries({ queryKey: ['sms-logs', companyId] })
          void queryClient.invalidateQueries({ queryKey: ['notification-logs', companyId] })
        },
      )
      .subscribe()

    return () => {
      void supabase.removeChannel(channel)
    }
  }, [companyId, queryClient])

  return query
}

export function useNotificationLogs(companyId: string | null) {
  return useQuery({
    queryKey: ['notification-logs', companyId],
    queryFn: () => listNotificationLogs(companyId!),
    enabled: !!companyId,
  })
}
