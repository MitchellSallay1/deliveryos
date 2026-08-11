import { useState } from 'react'
import {
  CommandButton,
  CommandCard,
  CommandCardBody,
  CommandCardHeader,
  CommandDrawer,
  CommandEmptyState,
  CommandInput,
  CommandSelect,
  CommandTable,
  CommandTableHead,
  CommandTd,
  CommandTh,
  CommandTr,
  SectionHeader,
  StatusChip,
} from '@/components/admin/control-tower'
import { useCommerceFeeRules, useUpsertCommerceFeeRule } from '@/hooks/use-commerce-finance'
import { parseSupabaseError } from '@/lib/supabase-errors'
import type { CommerceFeeRule } from '@/services/commerce-finance-service'

const FEE_MODELS: Array<{ value: CommerceFeeRule['fee_model']; label: string }> = [
  { value: 'zero_commission', label: 'Zero commission' },
  { value: 'percentage', label: 'Percentage of merchandise subtotal' },
  { value: 'fixed', label: 'Fixed fee per order' },
  { value: 'subscription_only', label: 'Subscription only (no per-order fee)' },
]

function RuleForm({ rule, onDone }: { rule: CommerceFeeRule | null; onDone: () => void }) {
  const upsert = useUpsertCommerceFeeRule()
  const [name, setName] = useState(rule?.name ?? '')
  const [feeModel, setFeeModel] = useState<CommerceFeeRule['fee_model']>(rule?.fee_model ?? 'percentage')
  const [percentagePercent, setPercentagePercent] = useState(rule ? (rule.percentage_bps / 100).toString() : '0')
  const [fixedFeeLrd, setFixedFeeLrd] = useState(rule ? (rule.fixed_fee_lrd_cents / 100).toString() : '0')
  const [isActive, setIsActive] = useState(rule?.is_active ?? true)
  const [isPlatformDefault, setIsPlatformDefault] = useState(rule?.is_platform_default ?? false)
  const [vendorCompanyId, setVendorCompanyId] = useState(rule?.applies_to_vendor_company_id ?? '')
  const [error, setError] = useState<string | null>(null)

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    try {
      await upsert.mutateAsync({
        id: rule?.id,
        name: name.trim(),
        fee_model: feeModel,
        percentage_bps: Math.round((Number(percentagePercent) || 0) * 100),
        fixed_fee_lrd_cents: Math.round((Number(fixedFeeLrd) || 0) * 100),
        is_active: isActive,
        is_platform_default: isPlatformDefault,
        applies_to_vendor_company_id: isPlatformDefault ? null : vendorCompanyId.trim() || null,
      })
      onDone()
    } catch (err) {
      setError(parseSupabaseError(err))
    }
  }

  return (
    <form className="space-y-4" onSubmit={(e) => void onSubmit(e)}>
      {error && <p className="text-sm text-red-400">{error}</p>}
      <label className="block space-y-1.5">
        <span className="text-xs font-medium uppercase tracking-wide text-zinc-500">Name</span>
        <CommandInput value={name} onChange={(e) => setName(e.target.value)} required />
      </label>
      <label className="block space-y-1.5">
        <span className="text-xs font-medium uppercase tracking-wide text-zinc-500">Fee model</span>
        <CommandSelect value={feeModel} onChange={(e) => setFeeModel(e.target.value as CommerceFeeRule['fee_model'])}>
          {FEE_MODELS.map((m) => (
            <option key={m.value} value={m.value}>{m.label}</option>
          ))}
        </CommandSelect>
      </label>
      {feeModel === 'percentage' && (
        <label className="block space-y-1.5">
          <span className="text-xs font-medium uppercase tracking-wide text-zinc-500">Percentage of merchandise subtotal (%)</span>
          <CommandInput type="number" min="0" max="100" step="0.1" value={percentagePercent} onChange={(e) => setPercentagePercent(e.target.value)} />
        </label>
      )}
      {feeModel === 'fixed' && (
        <label className="block space-y-1.5">
          <span className="text-xs font-medium uppercase tracking-wide text-zinc-500">Fixed fee per order (LRD)</span>
          <CommandInput type="number" min="0" step="1" value={fixedFeeLrd} onChange={(e) => setFixedFeeLrd(e.target.value)} />
        </label>
      )}
      <label className="flex items-center gap-2 text-sm text-zinc-300">
        <input type="checkbox" className="accent-[#FFCB05]" checked={isActive} onChange={(e) => setIsActive(e.target.checked)} />
        Active
      </label>
      <label className="flex items-center gap-2 text-sm text-zinc-300">
        <input
          type="checkbox"
          className="accent-[#FFCB05]"
          checked={isPlatformDefault}
          onChange={(e) => setIsPlatformDefault(e.target.checked)}
        />
        Platform default (applies to every vendor without a specific override)
      </label>
      {!isPlatformDefault && (
        <label className="block space-y-1.5">
          <span className="text-xs font-medium uppercase tracking-wide text-zinc-500">Applies to vendor company ID</span>
          <CommandInput value={vendorCompanyId} onChange={(e) => setVendorCompanyId(e.target.value)} placeholder="Leave blank for an inactive/template rule" />
        </label>
      )}
      <p className="text-xs text-zinc-500">
        Changing this rule only affects orders recognized after saving — every already-recognized order keeps the fee
        breakdown that was frozen at the moment it was paid.
      </p>
      <CommandButton type="submit" variant="primary" disabled={upsert.isPending}>
        {upsert.isPending ? 'Saving…' : rule ? 'Save changes' : 'Create rule'}
      </CommandButton>
    </form>
  )
}

export function AdminCommerceFeeRulesPage() {
  const { data: rules, isLoading } = useCommerceFeeRules()
  const [editing, setEditing] = useState<CommerceFeeRule | null>(null)
  const [creating, setCreating] = useState(false)

  function feeLabel(r: CommerceFeeRule): string {
    if (r.fee_model === 'zero_commission') return 'Zero commission'
    if (r.fee_model === 'subscription_only') return 'Subscription only'
    if (r.fee_model === 'fixed') return `LRD ${(r.fixed_fee_lrd_cents / 100).toFixed(0)} / order`
    return `${(r.percentage_bps / 100).toFixed(1)}%`
  }

  return (
    <div className="space-y-4">
      <SectionHeader eyebrow="Commerce" title="Commerce fee rules" className="mb-0" />
      <CommandCard>
        <CommandCardHeader
          title="Vendor commission rules"
          description="Controls the DeliveryOS platform fee on Commerce merchandise sales. Carrier delivery-fee commission is configured separately under the existing B2B marketplace fee rules."
        />
        <CommandCardBody className="flex justify-end border-b border-white/[0.06] pb-4">
          <CommandButton variant="primary" onClick={() => setCreating(true)}>New rule</CommandButton>
        </CommandCardBody>
        {isLoading ? (
          <p className="p-4 text-sm text-zinc-500">Loading…</p>
        ) : (rules ?? []).length === 0 ? (
          <CommandEmptyState label="No fee rules configured yet." />
        ) : (
          <CommandTable>
            <CommandTableHead>
              <CommandTh>Name</CommandTh>
              <CommandTh>Fee</CommandTh>
              <CommandTh>Scope</CommandTh>
              <CommandTh>Status</CommandTh>
              <CommandTh className="text-right">Edit</CommandTh>
            </CommandTableHead>
            <tbody>
              {(rules ?? []).map((r) => (
                <CommandTr key={r.id}>
                  <CommandTd className="font-medium text-zinc-100">{r.name}</CommandTd>
                  <CommandTd className="text-zinc-400">{feeLabel(r)}</CommandTd>
                  <CommandTd className="text-zinc-400">
                    {r.is_platform_default ? 'Platform default' : r.applies_to_vendor_company_id ? 'Specific vendor' : 'Inactive template'}
                  </CommandTd>
                  <CommandTd><StatusChip color={r.is_active ? 'green' : 'gray'} label={r.is_active ? 'active' : 'inactive'} /></CommandTd>
                  <CommandTd className="text-right">
                    <CommandButton size="sm" onClick={() => setEditing(r)}>Edit</CommandButton>
                  </CommandTd>
                </CommandTr>
              ))}
            </tbody>
          </CommandTable>
        )}
      </CommandCard>

      <CommandDrawer open={editing != null} onClose={() => setEditing(null)} title="Edit fee rule">
        {editing && <RuleForm rule={editing} onDone={() => setEditing(null)} />}
      </CommandDrawer>
      <CommandDrawer open={creating} onClose={() => setCreating(false)} title="New fee rule">
        <RuleForm rule={null} onDone={() => setCreating(false)} />
      </CommandDrawer>
    </div>
  )
}
