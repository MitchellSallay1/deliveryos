import { useState } from 'react'
import {
  CommandButton,
  CommandCard,
  CommandCardBody,
  CommandCardHeader,
  CommandSelect,
  ConfirmDialog,
  SectionHeader,
} from '@/components/admin/control-tower'
import { useAdminCompanies } from '@/hooks/use-admin'
import { useAdminBillingActions, useAdminPlans } from '@/hooks/use-billing'
import type { CompanySubscriptionStatus } from '@/types/supabase'
import { parseSupabaseError } from '@/lib/supabase-errors'

const STATUSES: CompanySubscriptionStatus[] = ['trialing', 'active', 'past_due', 'suspended', 'cancelled', 'expired']

export function AdminSubscriptionsPage() {
  const { data: companies = [] } = useAdminCompanies(true)
  const { data: plans = [] } = useAdminPlans(true)
  const { setSubscription } = useAdminBillingActions()
  const [companyId, setCompanyId] = useState('')
  const [planId, setPlanId] = useState('')
  const [status, setStatus] = useState<CompanySubscriptionStatus>('active')
  const [error, setError] = useState<string | null>(null)
  const [confirmOpen, setConfirmOpen] = useState(false)

  const selectedCompany = companies.find((c) => c.id === companyId)
  const selectedPlan = (plans as { id: string; name: string }[]).find((p) => p.id === planId)

  async function apply() {
    setError(null)
    if (!companyId || !planId) return
    try {
      await setSubscription.mutateAsync({ companyId, planId, status })
      setConfirmOpen(false)
    } catch (e) {
      setError(parseSupabaseError(e))
    }
  }

  return (
    <div className="space-y-4">
      <SectionHeader eyebrow="Billing" title="Company subscriptions" className="mb-0" />
      <CommandCard className="max-w-lg">
        <CommandCardHeader title="Change a company's plan or status" description="Applies immediately — affects billing enforcement" />
        <CommandCardBody className="space-y-3">
          {error && <p className="text-sm text-red-400">{error}</p>}
          <CommandSelect value={companyId} onChange={(e) => setCompanyId(e.target.value)}>
            <option value="">Select company…</option>
            {companies.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </CommandSelect>
          <CommandSelect value={planId} onChange={(e) => setPlanId(e.target.value)}>
            <option value="">Select plan…</option>
            {(plans as { id: string; name: string }[]).map((p) => (
              <option key={p.id} value={p.id}>
                {p.name}
              </option>
            ))}
          </CommandSelect>
          <CommandSelect value={status} onChange={(e) => setStatus(e.target.value as CompanySubscriptionStatus)}>
            {STATUSES.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </CommandSelect>
          <p className="text-xs text-zinc-600">Extend the billing period via the admin_extend_subscription RPC in the ops runbook.</p>
          <CommandButton
            variant="primary"
            disabled={!companyId || !planId || setSubscription.isPending}
            onClick={() => setConfirmOpen(true)}
          >
            Apply subscription change
          </CommandButton>
        </CommandCardBody>
      </CommandCard>

      <ConfirmDialog
        open={confirmOpen}
        title="Change this company's subscription?"
        description={
          selectedCompany && selectedPlan
            ? `${selectedCompany.name} will be moved to ${selectedPlan.name} with status "${status}". This affects billing enforcement immediately.`
            : 'This affects billing enforcement immediately.'
        }
        confirmLabel="Apply change"
        danger={status === 'suspended' || status === 'cancelled' || status === 'expired'}
        pending={setSubscription.isPending}
        onConfirm={() => void apply()}
        onCancel={() => setConfirmOpen(false)}
      />
    </div>
  )
}
