import { useState } from 'react'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { useAdminBillingActions, useAdminPlans } from '@/hooks/use-billing'
import { formatLrdFromCents } from '@/utils/delivery-schemas'
import { parseSupabaseError } from '@/lib/supabase-errors'

export function AdminPlansPage() {
  const { data: plans = [], isLoading } = useAdminPlans(true)
  const { upsertPlan } = useAdminBillingActions()
  const [error, setError] = useState<string | null>(null)

  async function toggleActive(id: string, isActive: boolean) {
    setError(null)
    try {
      await upsertPlan.mutateAsync({ id, is_active: !isActive })
    } catch (e) {
      setError(parseSupabaseError(e))
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Plans</CardTitle>
        <CardDescription>Starter, Business, Enterprise — limits enforced in PostgreSQL</CardDescription>
      </CardHeader>
      <CardContent className="overflow-x-auto">
        {error && <p className="mb-2 text-sm text-red-600">{error}</p>}
        {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
        <table className="w-full min-w-[960px] text-left text-sm">
          <thead>
            <tr className="border-b text-xs uppercase text-[var(--color-muted)]">
              <th className="py-2">Plan</th>
              <th className="py-2">Price</th>
              <th className="py-2">Riders</th>
              <th className="py-2">Deliveries/mo</th>
              <th className="py-2">SMS/mo</th>
              <th className="py-2">Features</th>
              <th className="py-2">Active</th>
            </tr>
          </thead>
          <tbody>
            {(plans as Record<string, unknown>[]).map((p) => (
              <tr key={String(p.id)} className="border-b">
                <td className="py-2">
                  <div className="font-medium">{String(p.name)}</div>
                  <div className="text-xs text-[var(--color-muted)]">{String(p.slug)}</div>
                </td>
                <td className="py-2">
                  {formatLrdFromCents(Number(p.price_lrd_cents))} {String(p.currency)}
                </td>
                <td className="py-2">{String(p.max_riders)}</td>
                <td className="py-2">{p.max_deliveries_per_month == null ? '∞' : String(p.max_deliveries_per_month)}</td>
                <td className="py-2">{String(p.monthly_sms_allowance)}</td>
                <td className="py-2 text-xs">
                  {p.advanced_reports ? 'Reports ' : ''}
                  {p.proof_of_delivery ? 'POD ' : ''}
                  {p.api_access ? 'API ' : ''}
                  {p.gps_tracking ? 'GPS* ' : ''}
                </td>
                <td className="py-2">
                  <Button
                    type="button"
                    size="sm"
                    variant="outline"
                    onClick={() => toggleActive(String(p.id), Boolean(p.is_active))}
                  >
                    {p.is_active ? 'Deactivate' : 'Activate'}
                  </Button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        <p className="mt-3 text-xs text-[var(--color-muted)]">
          Edit full plan fields via SQL/RPC payload in ops runbook. UI toggles active flag only (Phase 4).
        </p>
      </CardContent>
    </Card>
  )
}
