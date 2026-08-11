import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  CommandButton,
  CommandCard,
  CommandCardBody,
  CommandDrawer,
  CommandEmptyState,
  CommandInput,
  CommandPagination,
  CommandSelect,
  CommandTable,
  CommandTableHead,
  CommandTd,
  CommandTh,
  CommandTr,
  SectionHeader,
  StatusChip,
} from '@/components/admin/control-tower'
import { adminListVendorStores, adminSetVendorState, type AdminVendorStoreRow } from '@/services/vendor-commerce-service'
import { parseSupabaseError } from '@/lib/supabase-errors'
import type { CommerceVendorState } from '@/types/supabase'
import type { StatusColor } from '@/lib/admin-control-tower'

const PAGE = 25

const STATE_OPTIONS: Array<{ value: CommerceVendorState; label: string }> = [
  { value: 'draft', label: 'Draft' },
  { value: 'pending_review', label: 'Pending review' },
  { value: 'active', label: 'Active' },
  { value: 'suspended', label: 'Suspended' },
  { value: 'rejected', label: 'Rejected' },
]

function stateColor(state: CommerceVendorState): StatusColor {
  switch (state) {
    case 'active':
      return 'green'
    case 'pending_review':
      return 'amber'
    case 'suspended':
    case 'rejected':
      return 'red'
    case 'draft':
      return 'gray'
  }
}

export function AdminVendorsPage() {
  const [search, setSearch] = useState('')
  const [status, setStatus] = useState('')
  const [page, setPage] = useState(1)
  const [reviewing, setReviewing] = useState<AdminVendorStoreRow | null>(null)
  const [reason, setReason] = useState('')
  const [error, setError] = useState<string | null>(null)
  const qc = useQueryClient()

  const { data, isLoading } = useQuery({
    queryKey: ['admin-vendor-stores', search, status, page],
    queryFn: () => adminListVendorStores({ search, status: status || null, limit: PAGE, offset: (page - 1) * PAGE }),
  })

  const setState = useMutation({
    mutationFn: ({ companyId, state, reason: r }: { companyId: string; state: CommerceVendorState; reason?: string }) =>
      adminSetVendorState(companyId, state, r),
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['admin-vendor-stores'] })
      setReviewing(null)
      setReason('')
    },
  })

  const rows = data?.rows ?? []
  const total = data?.total ?? 0

  async function applyState(state: CommerceVendorState) {
    if (!reviewing) return
    setError(null)
    try {
      await setState.mutateAsync({ companyId: reviewing.company_id, state, reason: reason.trim() || undefined })
    } catch (e) {
      setError(parseSupabaseError(e))
    }
  }

  return (
    <div className="space-y-4">
      <SectionHeader eyebrow="Commerce" title="Vendor stores" className="mb-0" />
      <CommandCard>
        <CommandCardBody className="flex flex-wrap items-center gap-3 border-b border-white/[0.06] pb-4">
          <CommandInput
            className="max-w-sm"
            placeholder="Search store or company name"
            value={search}
            onChange={(e) => {
              setSearch(e.target.value)
              setPage(1)
            }}
          />
          <CommandSelect
            className="max-w-[220px]"
            value={status}
            onChange={(e) => {
              setStatus(e.target.value)
              setPage(1)
            }}
          >
            <option value="">All statuses</option>
            {STATE_OPTIONS.map((s) => (
              <option key={s.value} value={s.value}>{s.label}</option>
            ))}
          </CommandSelect>
        </CommandCardBody>
        {isLoading ? (
          <p className="p-4 text-sm text-zinc-500">Loading…</p>
        ) : rows.length === 0 ? (
          <CommandEmptyState label="No vendor stores match this search." />
        ) : (
          <CommandTable>
            <CommandTableHead>
              <CommandTh>Store</CommandTh>
              <CommandTh>Company</CommandTh>
              <CommandTh>Products</CommandTh>
              <CommandTh>Status</CommandTh>
              <CommandTh className="text-right">Review</CommandTh>
            </CommandTableHead>
            <tbody>
              {rows.map((r) => (
                <CommandTr key={r.company_id}>
                  <CommandTd>
                    <div className="font-medium text-zinc-100">{r.display_name}</div>
                    <div className="text-xs text-zinc-500">/store/{r.slug}</div>
                  </CommandTd>
                  <CommandTd className="text-zinc-400">{r.company_name}</CommandTd>
                  <CommandTd>{r.product_count}</CommandTd>
                  <CommandTd>
                    <StatusChip color={stateColor(r.status)} label={r.status.replace(/_/g, ' ')} />
                  </CommandTd>
                  <CommandTd className="text-right">
                    <CommandButton
                      size="sm"
                      onClick={() => {
                        setReviewing(r)
                        setReason('')
                        setError(null)
                      }}
                    >
                      Inspect
                    </CommandButton>
                  </CommandTd>
                </CommandTr>
              ))}
            </tbody>
          </CommandTable>
        )}
        <div className="px-4 pb-4">
          <CommandPagination total={total} page={page} pageSize={PAGE} onPage={setPage} loading={isLoading} />
        </div>
      </CommandCard>

      <CommandDrawer
        open={reviewing != null}
        onClose={() => setReviewing(null)}
        title={reviewing ? reviewing.display_name : 'Vendor store'}
        description={reviewing ? `${reviewing.company_name} · /store/${reviewing.slug} · ${reviewing.product_count} products` : undefined}
      >
        {reviewing && (
          <div className="space-y-4">
            {error && <p className="text-sm text-red-400">{error}</p>}
            <div>
              <p className="text-xs font-medium uppercase tracking-wide text-zinc-500">Current status</p>
              <div className="mt-1">
                <StatusChip color={stateColor(reviewing.status)} label={reviewing.status.replace(/_/g, ' ')} />
              </div>
              {reviewing.status_reason && (
                <p className="mt-2 text-sm text-zinc-400">Last note: {reviewing.status_reason}</p>
              )}
            </div>

            <label className="block space-y-1.5">
              <span className="text-xs font-medium uppercase tracking-wide text-zinc-500">Note (optional)</span>
              <textarea
                className="min-h-20 w-full rounded-lg border border-white/10 bg-white/[0.03] px-3 py-2 text-sm text-zinc-100 outline-none focus:border-[#FFCB05]/40"
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                placeholder="Reason shown to the vendor, e.g. why a store was rejected or suspended"
              />
            </label>

            <div className="flex flex-wrap gap-2 border-t border-white/[0.08] pt-4">
              {reviewing.status === 'pending_review' && (
                <>
                  <CommandButton variant="primary" disabled={setState.isPending} onClick={() => void applyState('active')}>
                    Approve
                  </CommandButton>
                  <CommandButton variant="destructive" disabled={setState.isPending} onClick={() => void applyState('rejected')}>
                    Reject
                  </CommandButton>
                </>
              )}
              {reviewing.status === 'active' && (
                <CommandButton variant="destructive" disabled={setState.isPending} onClick={() => void applyState('suspended')}>
                  Suspend
                </CommandButton>
              )}
              {reviewing.status === 'suspended' && (
                <CommandButton variant="primary" disabled={setState.isPending} onClick={() => void applyState('active')}>
                  Restore to active
                </CommandButton>
              )}
              {reviewing.status === 'rejected' && (
                <CommandButton variant="primary" disabled={setState.isPending} onClick={() => void applyState('active')}>
                  Approve anyway
                </CommandButton>
              )}
              {reviewing.status === 'draft' && (
                <p className="text-sm text-zinc-500">This vendor has not submitted their store for review yet.</p>
              )}
            </div>
          </div>
        )}
      </CommandDrawer>
    </div>
  )
}
