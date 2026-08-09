import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { useAuth } from '@/hooks/use-auth'
import {
  listCashSettlements,
  reconcileCashSettlement,
} from '@/services/operations-service'
import { formatLrdFromCents } from '@/utils/delivery-schemas'

export function CashSettlementsPage() {
  const companyId = useAuth().context?.activeCompanyId ?? null
  const qc = useQueryClient()
  const { data = [], isLoading } = useQuery({
    queryKey: ['cash-settlements', companyId],
    queryFn: () => listCashSettlements(companyId!),
    enabled: !!companyId,
  })

  const reconcile = useMutation({
    mutationFn: (id: string) => reconcileCashSettlement(id),
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['cash-settlements', companyId] }),
  })

  return (
    <Card>
      <CardHeader>
        <CardTitle>COD cash settlements</CardTitle>
      </CardHeader>
      <CardContent className="text-sm">
        {isLoading && <p className="text-[var(--color-muted)]">Loading…</p>}
        <ul className="space-y-2">
          {(data as Record<string, unknown>[]).map((s) => (
            <li key={String(s.id)} className="flex flex-wrap items-center justify-between gap-2 border-b py-2">
              <span>
                {(s.riders as { full_name?: string })?.full_name ?? 'Rider'} · {String(s.status)} ·{' '}
                {formatLrdFromCents(Number(s.total_expected_cents))}
              </span>
              {s.status === 'submitted' && (
                <Button size="sm" onClick={() => reconcile.mutate(String(s.id))}>
                  Reconcile
                </Button>
              )}
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  )
}
