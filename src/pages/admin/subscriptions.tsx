import { useState } from 'react'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { useAdminCompanies } from '@/hooks/use-admin'
import { useAdminBillingActions, useAdminPlans } from '@/hooks/use-billing'
import type { CompanySubscriptionStatus } from '@/types/supabase'
import { parseSupabaseError } from '@/lib/supabase-errors'

export function AdminSubscriptionsPage() {
  const { data: companies = [] } = useAdminCompanies(true)
  const { data: plans = [] } = useAdminPlans(true)
  const { setSubscription } = useAdminBillingActions()
  const [companyId, setCompanyId] = useState('')
  const [planId, setPlanId] = useState('')
  const [status, setStatus] = useState<CompanySubscriptionStatus>('active')
  const [error, setError] = useState<string | null>(null)

  async function apply() {
    setError(null)
    if (!companyId || !planId) return
    try {
      await setSubscription.mutateAsync({ companyId, planId, status })
    } catch (e) {
      setError(parseSupabaseError(e))
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Company subscriptions</CardTitle>
      </CardHeader>
      <CardContent className="space-y-3 max-w-lg">
        {error && <p className="text-sm text-red-600">{error}</p>}
        <select
          className="h-10 w-full rounded-md border px-3 text-sm"
          value={companyId}
          onChange={(e) => setCompanyId(e.target.value)}
        >
          <option value="">Select company…</option>
          {companies.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </select>
        <select
          className="h-10 w-full rounded-md border px-3 text-sm"
          value={planId}
          onChange={(e) => setPlanId(e.target.value)}
        >
          <option value="">Select plan…</option>
          {(plans as { id: string; name: string }[]).map((p) => (
            <option key={p.id} value={p.id}>
              {p.name}
            </option>
          ))}
        </select>
        <select
          className="h-10 w-full rounded-md border px-3 text-sm"
          value={status}
          onChange={(e) => setStatus(e.target.value as CompanySubscriptionStatus)}
        >
          {['trialing', 'active', 'past_due', 'suspended', 'cancelled', 'expired'].map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </select>
        <Input type="datetime-local" disabled title="Extend via admin_extend_subscription RPC in ops" />
        <Button type="button" onClick={() => void apply()}>
          Apply subscription change
        </Button>
      </CardContent>
    </Card>
  )
}
