import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  CommandButton,
  CommandCard,
  CommandEmptyState,
  CommandTable,
  CommandTableHead,
  CommandTd,
  CommandTh,
  CommandTr,
  SectionHeader,
  StatusChip,
} from '@/components/admin/control-tower'
import { statusColorFor } from '@/lib/admin-control-tower'
import { supabase } from '@/lib/supabase/client'

export function AdminWebhooksPage() {
  const qc = useQueryClient()
  const { data, isLoading } = useQuery({
    queryKey: ['admin-webhook-failures'],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('admin_list_webhook_failures', {
        p_limit: 50,
        p_offset: 0,
      })
      if (error) throw error
      return data as { items: Record<string, unknown>[]; total: number }
    },
  })

  const retry = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.rpc('admin_retry_webhook_delivery', { p_delivery_id: id })
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['admin-webhook-failures'] }),
  })

  const items = data?.items ?? []

  return (
    <div className="space-y-4">
      <SectionHeader eyebrow="Webhooks" title={`Failed deliveries (${data?.total ?? 0})`} className="mb-0" />
      <CommandCard>
        {isLoading ? (
          <p className="p-4 text-sm text-zinc-500">Loading…</p>
        ) : items.length === 0 ? (
          <CommandEmptyState label="No failed webhook deliveries." />
        ) : (
          <CommandTable>
            <CommandTableHead>
              <CommandTh>Status</CommandTh>
              <CommandTh>Error</CommandTh>
              <CommandTh className="text-right">Action</CommandTh>
            </CommandTableHead>
            <tbody>
              {items.map((row) => (
                <CommandTr key={String(row.id)}>
                  <CommandTd>
                    <StatusChip color={statusColorFor(String(row.status))} label={String(row.status)} />
                  </CommandTd>
                  <CommandTd className="max-w-md truncate text-xs text-zinc-500">{String(row.last_error ?? '—')}</CommandTd>
                  <CommandTd className="text-right">
                    <CommandButton size="sm" disabled={retry.isPending} onClick={() => retry.mutate(String(row.id))}>
                      Retry
                    </CommandButton>
                  </CommandTd>
                </CommandTr>
              ))}
            </tbody>
          </CommandTable>
        )}
      </CommandCard>
    </div>
  )
}
