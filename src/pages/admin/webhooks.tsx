import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
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

  return (
    <Card>
      <CardHeader>
        <CardTitle>Failed webhook deliveries ({data?.total ?? 0})</CardTitle>
      </CardHeader>
      <CardContent>
        {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
        <ul className="divide-y text-sm">
          {(data?.items ?? []).map((row) => (
            <li key={String(row.id)} className="flex flex-wrap items-center justify-between gap-2 py-2">
              <div>
                <p className="font-medium">{String(row.status)}</p>
                <p className="text-[var(--color-muted)]">{String(row.last_error ?? '—')}</p>
              </div>
              <Button size="sm" variant="outline" onClick={() => retry.mutate(String(row.id))}>
                Retry
              </Button>
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  )
}
