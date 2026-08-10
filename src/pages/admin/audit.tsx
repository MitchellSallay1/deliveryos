import { useState } from 'react'
import {
  CommandButton,
  CommandCard,
  CommandCardBody,
  CommandEmptyState,
  CommandInput,
  CommandPagination,
  CommandTable,
  CommandTableHead,
  CommandTd,
  CommandTh,
  CommandTr,
  SectionHeader,
} from '@/components/admin/control-tower'
import { useAuditLogsAdmin } from '@/hooks/use-admin-platform'

export function AdminAuditPage() {
  const [page, setPage] = useState(1)
  const [action, setAction] = useState('')
  const [actionFilter, setActionFilter] = useState<string | undefined>()
  const { data, isLoading } = useAuditLogsAdmin(
    { action: actionFilter, limit: 25, offset: (page - 1) * 25 },
    true,
  )
  const rows = data?.rows ?? []
  const total = data?.total ?? 0

  return (
    <div className="space-y-4">
      <SectionHeader eyebrow="Audit" title="Platform audit log" className="mb-0" />
      <CommandCard>
        <CommandCardBody className="flex max-w-md gap-2 border-b border-white/[0.06] pb-4">
          <CommandInput placeholder="Filter action" value={action} onChange={(e) => setAction(e.target.value)} />
          <CommandButton
            variant="primary"
            onClick={() => {
              setActionFilter(action.trim() || undefined)
              setPage(1)
            }}
          >
            Filter
          </CommandButton>
        </CommandCardBody>
        {isLoading ? (
          <p className="p-4 text-sm text-zinc-500">Loading…</p>
        ) : rows.length === 0 ? (
          <CommandEmptyState label="No audit events match this filter." />
        ) : (
          <CommandTable>
            <CommandTableHead>
              <CommandTh>When</CommandTh>
              <CommandTh>Actor</CommandTh>
              <CommandTh>Action</CommandTh>
              <CommandTh>Entity</CommandTh>
              <CommandTh className="text-right">Company</CommandTh>
            </CommandTableHead>
            <tbody>
              {rows.map((r) => (
                <CommandTr key={String(r.id)}>
                  <CommandTd className="text-xs text-zinc-500">{new Date(String(r.created_at)).toLocaleString()}</CommandTd>
                  <CommandTd className="text-xs text-zinc-400">{String(r.actor_name ?? r.actor_user_id ?? '—')}</CommandTd>
                  <CommandTd>{String(r.action)}</CommandTd>
                  <CommandTd className="text-xs text-zinc-400">
                    {String(r.entity_type)} {String(r.entity_id ?? '')}
                  </CommandTd>
                  <CommandTd className="text-right font-mono text-xs text-zinc-500">{String(r.company_id ?? '—')}</CommandTd>
                </CommandTr>
              ))}
            </tbody>
          </CommandTable>
        )}
        <div className="px-4 pb-4">
          <CommandPagination total={total} page={page} pageSize={25} onPage={setPage} loading={isLoading} />
        </div>
      </CommandCard>
    </div>
  )
}
