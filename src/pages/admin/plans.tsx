import { useState } from 'react'
import {
  CommandButton,
  CommandCard,
  CommandCardBody,
  CommandCardHeader,
  CommandEmptyState,
  CommandTable,
  CommandTableHead,
  CommandTd,
  CommandTh,
  CommandTr,
  SectionHeader,
  StatusChip,
} from '@/components/admin/control-tower'
import { useAdminBillingActions, useAdminPlans } from '@/hooks/use-billing'
import { formatLrdFromCents } from '@/utils/delivery-schemas'
import { parseSupabaseError } from '@/lib/supabase-errors'

export function AdminPlansPage() {
  const { data: plansData = [], isLoading } = useAdminPlans(true)
  const plans = plansData as Record<string, unknown>[]
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
    <div className="space-y-4">
      <SectionHeader eyebrow="Billing" title="Plans" className="mb-0" />
      <CommandCard>
        <CommandCardHeader title="Starter, Business, Enterprise" description="Limits enforced in PostgreSQL" />
        <CommandCardBody className="p-0">
          {error && <p className="px-4 pt-3 text-sm text-red-400">{error}</p>}
          {isLoading ? (
            <p className="p-4 text-sm text-zinc-500">Loading…</p>
          ) : plans.length === 0 ? (
            <CommandEmptyState label="No plans configured." />
          ) : (
            <CommandTable>
              <CommandTableHead>
                <CommandTh>Plan</CommandTh>
                <CommandTh>Price</CommandTh>
                <CommandTh>Riders</CommandTh>
                <CommandTh>Deliveries/mo</CommandTh>
                <CommandTh>SMS/mo</CommandTh>
                <CommandTh>Features</CommandTh>
                <CommandTh className="text-right">Active</CommandTh>
              </CommandTableHead>
              <tbody>
                {plans.map((p) => (
                  <CommandTr key={String(p.id)}>
                    <CommandTd>
                      <div className="font-medium text-zinc-100">{String(p.name)}</div>
                      <div className="text-xs text-zinc-500">{String(p.slug)}</div>
                    </CommandTd>
                    <CommandTd>
                      {formatLrdFromCents(Number(p.price_lrd_cents))} {String(p.currency)}
                    </CommandTd>
                    <CommandTd>{String(p.max_riders)}</CommandTd>
                    <CommandTd>{p.max_deliveries_per_month == null ? '∞' : String(p.max_deliveries_per_month)}</CommandTd>
                    <CommandTd>{String(p.monthly_sms_allowance)}</CommandTd>
                    <CommandTd className="text-xs text-zinc-400">
                      {p.advanced_reports ? 'Reports ' : ''}
                      {p.proof_of_delivery ? 'POD ' : ''}
                      {p.api_access ? 'API ' : ''}
                      {p.gps_tracking ? 'GPS* ' : ''}
                    </CommandTd>
                    <CommandTd className="text-right">
                      <div className="flex items-center justify-end gap-2">
                        <StatusChip color={p.is_active ? 'green' : 'gray'} label={p.is_active ? 'active' : 'inactive'} />
                        <CommandButton
                          size="sm"
                          variant={p.is_active ? 'destructive' : 'outline'}
                          onClick={() => toggleActive(String(p.id), Boolean(p.is_active))}
                        >
                          {p.is_active ? 'Deactivate' : 'Activate'}
                        </CommandButton>
                      </div>
                    </CommandTd>
                  </CommandTr>
                ))}
              </tbody>
            </CommandTable>
          )}
        </CommandCardBody>
        <p className="border-t border-white/[0.06] px-4 py-3 text-xs text-zinc-500">
          Edit full plan fields via SQL/RPC payload in ops runbook. UI toggles active flag only (Phase 4).
        </p>
      </CommandCard>
    </div>
  )
}
