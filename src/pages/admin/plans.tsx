import { useState } from 'react'
import {
  CommandButton,
  CommandCard,
  CommandCardBody,
  CommandCardHeader,
  CommandDrawer,
  CommandEmptyState,
  CommandInput,
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

type PlanRow = {
  id: string
  slug: string
  name: string
  price_lrd_cents: number
  currency: string
  max_riders: number
  max_deliveries_per_month: number | null
  monthly_sms_allowance: number
  proof_of_delivery: boolean
  advanced_reports: boolean
  api_access: boolean
  gps_tracking: boolean
  custom_branding: boolean
  is_active: boolean
}

type PlanFormState = {
  name: string
  priceLrd: string
  maxRiders: string
  maxDeliveriesPerMonth: string
  monthlySmsAllowance: string
  proofOfDelivery: boolean
  advancedReports: boolean
  apiAccess: boolean
  gpsTracking: boolean
  customBranding: boolean
}

function planToFormState(p: PlanRow): PlanFormState {
  return {
    name: p.name,
    priceLrd: String(p.price_lrd_cents / 100),
    maxRiders: String(p.max_riders),
    maxDeliveriesPerMonth: p.max_deliveries_per_month == null ? '' : String(p.max_deliveries_per_month),
    monthlySmsAllowance: String(p.monthly_sms_allowance),
    proofOfDelivery: p.proof_of_delivery,
    advancedReports: p.advanced_reports,
    apiAccess: p.api_access,
    gpsTracking: p.gps_tracking,
    customBranding: p.custom_branding,
  }
}

export function AdminPlansPage() {
  const { data: plansData = [], isLoading } = useAdminPlans(true)
  const plans = plansData as unknown as PlanRow[]
  const { upsertPlan } = useAdminBillingActions()
  const [error, setError] = useState<string | null>(null)
  const [editing, setEditing] = useState<PlanRow | null>(null)
  const [form, setForm] = useState<PlanFormState | null>(null)

  async function toggleActive(id: string, isActive: boolean) {
    setError(null)
    try {
      await upsertPlan.mutateAsync({ id, is_active: !isActive })
    } catch (e) {
      setError(parseSupabaseError(e))
    }
  }

  function openEdit(p: PlanRow) {
    setError(null)
    setEditing(p)
    setForm(planToFormState(p))
  }

  function closeEdit() {
    setEditing(null)
    setForm(null)
  }

  async function onSave(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    if (!editing || !form) return
    setError(null)

    const priceLrd = Number(form.priceLrd)
    const maxRiders = Number(form.maxRiders)
    const monthlySmsAllowance = Number(form.monthlySmsAllowance)
    const maxDeliveriesPerMonth =
      form.maxDeliveriesPerMonth.trim() === '' ? null : Number(form.maxDeliveriesPerMonth)

    if (!Number.isFinite(priceLrd) || priceLrd < 0) {
      setError('Price must be a non-negative number.')
      return
    }
    if (!Number.isInteger(maxRiders) || maxRiders < 1) {
      setError('Rider limit must be a whole number of at least 1.')
      return
    }
    if (!Number.isInteger(monthlySmsAllowance) || monthlySmsAllowance < 0) {
      setError('SMS allowance must be a non-negative whole number.')
      return
    }
    if (maxDeliveriesPerMonth !== null && (!Number.isInteger(maxDeliveriesPerMonth) || maxDeliveriesPerMonth < 0)) {
      setError('Delivery limit must be blank (unlimited) or a non-negative whole number.')
      return
    }

    try {
      await upsertPlan.mutateAsync({
        id: editing.id,
        name: form.name.trim(),
        price_lrd_cents: Math.round(priceLrd * 100),
        max_riders: maxRiders,
        max_deliveries_per_month: maxDeliveriesPerMonth,
        monthly_sms_allowance: monthlySmsAllowance,
        proof_of_delivery: form.proofOfDelivery,
        advanced_reports: form.advancedReports,
        api_access: form.apiAccess,
        gps_tracking: form.gpsTracking,
        custom_branding: form.customBranding,
      })
      closeEdit()
    } catch (e) {
      setError(parseSupabaseError(e))
    }
  }

  return (
    <div className="space-y-4">
      <SectionHeader eyebrow="Billing" title="Plans" className="mb-0" />
      <CommandCard>
        <CommandCardHeader
          title="Starter, Business, Enterprise"
          description="Source of truth for pricing, allowances, and entitlements — nothing in application code hardcodes these values."
        />
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
                  <CommandTr key={p.id}>
                    <CommandTd>
                      <div className="font-medium text-zinc-100">{p.name}</div>
                      <div className="text-xs text-zinc-500">{p.slug}</div>
                    </CommandTd>
                    <CommandTd>
                      {formatLrdFromCents(p.price_lrd_cents)} {p.currency}
                    </CommandTd>
                    <CommandTd>{p.max_riders}</CommandTd>
                    <CommandTd>{p.max_deliveries_per_month == null ? '∞' : p.max_deliveries_per_month}</CommandTd>
                    <CommandTd>{p.monthly_sms_allowance}</CommandTd>
                    <CommandTd className="text-xs text-zinc-400">
                      {p.advanced_reports ? 'Reports ' : ''}
                      {p.proof_of_delivery ? 'POD ' : ''}
                      {p.api_access ? 'API ' : ''}
                      {p.gps_tracking ? 'GPS ' : ''}
                      {p.custom_branding ? 'Branding ' : ''}
                    </CommandTd>
                    <CommandTd className="text-right">
                      <div className="flex items-center justify-end gap-2">
                        <StatusChip color={p.is_active ? 'green' : 'gray'} label={p.is_active ? 'active' : 'inactive'} />
                        <CommandButton size="sm" onClick={() => openEdit(p)}>
                          Edit
                        </CommandButton>
                        <CommandButton
                          size="sm"
                          variant={p.is_active ? 'destructive' : 'outline'}
                          onClick={() => toggleActive(p.id, p.is_active)}
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
      </CommandCard>

      <CommandDrawer
        open={editing != null}
        onClose={closeEdit}
        title={editing ? `Edit ${editing.name}` : 'Edit plan'}
        description="Changes apply immediately for new provisioning (new trials, admin plan assignments). They do not rewrite historical invoices or ledger entries."
      >
        {editing && form && (
          <form className="space-y-4" onSubmit={onSave}>
            {error && <p className="text-sm text-red-400">{error}</p>}

            <Field label="Plan name">
              <CommandInput
                value={form.name}
                onChange={(e) => setForm({ ...form, name: e.target.value })}
                required
              />
            </Field>

            <Field label={`Price (${editing.currency}/month)`}>
              <CommandInput
                type="number"
                min="0"
                step="1"
                value={form.priceLrd}
                onChange={(e) => setForm({ ...form, priceLrd: e.target.value })}
                required
              />
            </Field>

            <Field label="Monthly SMS allowance" hint="Included credits granted per billing period — does not roll over.">
              <CommandInput
                type="number"
                min="0"
                step="1"
                value={form.monthlySmsAllowance}
                onChange={(e) => setForm({ ...form, monthlySmsAllowance: e.target.value })}
                required
              />
            </Field>

            <Field label="Rider limit">
              <CommandInput
                type="number"
                min="1"
                step="1"
                value={form.maxRiders}
                onChange={(e) => setForm({ ...form, maxRiders: e.target.value })}
                required
              />
            </Field>

            <Field label="Deliveries per month" hint="Leave blank for unlimited.">
              <CommandInput
                type="number"
                min="0"
                step="1"
                placeholder="Unlimited"
                value={form.maxDeliveriesPerMonth}
                onChange={(e) => setForm({ ...form, maxDeliveriesPerMonth: e.target.value })}
              />
            </Field>

            <div className="space-y-2">
              <p className="text-xs font-medium uppercase tracking-wide text-zinc-500">Feature entitlements</p>
              <CheckboxRow
                label="Proof of delivery"
                checked={form.proofOfDelivery}
                onChange={(v) => setForm({ ...form, proofOfDelivery: v })}
              />
              <CheckboxRow
                label="Advanced reports"
                checked={form.advancedReports}
                onChange={(v) => setForm({ ...form, advancedReports: v })}
              />
              <CheckboxRow
                label="API access"
                checked={form.apiAccess}
                onChange={(v) => setForm({ ...form, apiAccess: v })}
              />
              <CheckboxRow
                label="GPS tracking"
                checked={form.gpsTracking}
                onChange={(v) => setForm({ ...form, gpsTracking: v })}
              />
              <CheckboxRow
                label="Custom branding"
                checked={form.customBranding}
                onChange={(v) => setForm({ ...form, customBranding: v })}
              />
            </div>

            <div className="flex gap-2 border-t border-white/[0.08] pt-4">
              <CommandButton type="submit" variant="primary" disabled={upsertPlan.isPending}>
                {upsertPlan.isPending ? 'Saving…' : 'Save changes'}
              </CommandButton>
              <CommandButton type="button" onClick={closeEdit}>
                Cancel
              </CommandButton>
            </div>
          </form>
        )}
      </CommandDrawer>
    </div>
  )
}

function Field({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <label className="block space-y-1.5">
      <span className="text-xs font-medium uppercase tracking-wide text-zinc-500">{label}</span>
      {children}
      {hint && <span className="block text-[11px] text-zinc-600">{hint}</span>}
    </label>
  )
}

function CheckboxRow({
  label,
  checked,
  onChange,
}: {
  label: string
  checked: boolean
  onChange: (v: boolean) => void
}) {
  return (
    <label className="flex items-center gap-2 text-sm text-zinc-300">
      <input
        type="checkbox"
        className="h-4 w-4 rounded border-white/20 bg-white/[0.03] accent-[#FFCB05]"
        checked={checked}
        onChange={(e) => onChange(e.target.checked)}
      />
      {label}
    </label>
  )
}
