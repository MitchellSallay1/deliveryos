import { useState } from 'react'
import {
  CommandCard,
  CommandEmptyState,
  CommandKpi,
  CommandPagination,
  CommandTable,
  CommandTableHead,
  CommandTd,
  CommandTh,
  CommandTr,
  SectionHeader,
  StatusChip,
} from '@/components/admin/control-tower'
import { useAdminApiKeysPage, useExtendedHealth } from '@/hooks/use-admin-platform'

const PAGE = 25

export function AdminApiPage() {
  const [page, setPage] = useState(1)
  const { data, isLoading } = useAdminApiKeysPage({ limit: PAGE, offset: (page - 1) * PAGE }, true)
  const { data: health } = useExtendedHealth(true)
  const rows = data?.rows ?? []
  const total = data?.total ?? 0
  const authFailures = Number(health?.api_auth_failures_24h ?? 0)

  return (
    <div className="space-y-4">
      <SectionHeader eyebrow="API" title="API keys & auth" className="mb-0" />

      <CommandKpi
        label="Auth failures (24h)"
        value={String(authFailures)}
        color={authFailures >= 20 ? 'red' : authFailures > 0 ? 'amber' : 'green'}
        className="max-w-xs"
      />

      <CommandCard>
        {isLoading ? (
          <p className="p-4 text-sm text-zinc-500">Loading…</p>
        ) : rows.length === 0 ? (
          <CommandEmptyState label="No API keys issued." />
        ) : (
          <CommandTable>
            <CommandTableHead>
              <CommandTh>Company</CommandTh>
              <CommandTh>Name</CommandTh>
              <CommandTh>Prefix</CommandTh>
              <CommandTh>Status</CommandTh>
              <CommandTh className="text-right">Last used</CommandTh>
            </CommandTableHead>
            <tbody>
              {rows.map((r) => (
                <CommandTr key={String(r.id)}>
                  <CommandTd>{String(r.company_name)}</CommandTd>
                  <CommandTd>{String(r.name)}</CommandTd>
                  <CommandTd className="font-mono text-xs text-zinc-400">{String(r.key_prefix)}···</CommandTd>
                  <CommandTd>
                    <StatusChip color={r.is_active ? 'green' : 'gray'} label={r.is_active ? 'active' : 'revoked'} />
                  </CommandTd>
                  <CommandTd className="text-right text-xs text-zinc-500">
                    {r.last_used_at ? new Date(String(r.last_used_at)).toLocaleString() : 'Never'}
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
    </div>
  )
}
