import { useState } from 'react'
import { Link } from 'react-router-dom'
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
  StatusChip,
} from '@/components/admin/control-tower'
import { statusColorFor } from '@/lib/admin-control-tower'
import { useAdminCompaniesPage } from '@/hooks/use-admin-platform'
import { useAdminCompanyActions } from '@/hooks/use-admin'

const PAGE = 25

type Props = {
  title: string
  description: string
  businessType?: 'merchant' | 'logistics_provider' | 'hybrid'
}

export function AdminCompanyDirectoryPage({ title, description, businessType }: Props) {
  const [search, setSearch] = useState('')
  const [page, setPage] = useState(1)
  const { data, isLoading } = useAdminCompaniesPage(
    {
      search: search || undefined,
      businessType,
      limit: PAGE,
      offset: (page - 1) * PAGE,
    },
    true,
  )
  const { statusMutation } = useAdminCompanyActions()
  const rows = data?.rows ?? []
  const total = data?.total ?? 0

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <SectionHeader eyebrow="Companies" title={title} className="mb-0" />
        <p className="text-xs text-zinc-500">{description}</p>
      </div>

      <CommandCard>
        <CommandCardBody className="border-b border-white/[0.06] pb-4">
          <CommandInput
            className="max-w-sm"
            placeholder="Search name, phone, email"
            value={search}
            onChange={(e) => {
              setSearch(e.target.value)
              setPage(1)
            }}
          />
        </CommandCardBody>
        {isLoading ? (
          <p className="p-4 text-sm text-zinc-500">Loading…</p>
        ) : rows.length === 0 ? (
          <CommandEmptyState label="No companies match this search." />
        ) : (
          <CommandTable>
            <CommandTableHead>
              <CommandTh>Company</CommandTh>
              <CommandTh>Type</CommandTh>
              <CommandTh>Plan</CommandTh>
              <CommandTh>Status</CommandTh>
              <CommandTh className="text-right">Actions</CommandTh>
            </CommandTableHead>
            <tbody>
              {rows.map((c) => (
                <CommandTr key={String(c.id)}>
                  <CommandTd>
                    <Link className="font-medium text-zinc-100 hover:text-white hover:underline" to={`/admin/companies/${c.id}`}>
                      {String(c.name)}
                    </Link>
                  </CommandTd>
                  <CommandTd className="text-xs capitalize text-zinc-400">{String(c.business_type ?? '—').replace(/_/g, ' ')}</CommandTd>
                  <CommandTd className="text-xs text-zinc-400">{String(c.plan_name ?? '—')}</CommandTd>
                  <CommandTd>
                    <StatusChip color={statusColorFor(String(c.status))} label={String(c.status)} />
                  </CommandTd>
                  <CommandTd className="text-right">
                    <div className="flex flex-wrap justify-end gap-1.5">
                      {c.status !== 'active' && (
                        <CommandButton
                          size="sm"
                          variant="primary"
                          disabled={statusMutation.isPending}
                          onClick={() => statusMutation.mutate({ id: String(c.id), status: 'active' })}
                        >
                          Activate
                        </CommandButton>
                      )}
                      {c.status === 'active' && (
                        <CommandButton
                          size="sm"
                          variant="destructive"
                          disabled={statusMutation.isPending}
                          onClick={() => statusMutation.mutate({ id: String(c.id), status: 'suspended' })}
                        >
                          Suspend
                        </CommandButton>
                      )}
                    </div>
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

export function AdminMerchantsPage() {
  return (
    <AdminCompanyDirectoryPage
      title="Merchants"
      description="Merchant and hybrid workspaces"
      businessType="merchant"
    />
  )
}

export function AdminProvidersPage() {
  return (
    <AdminCompanyDirectoryPage
      title="Logistics providers"
      description="Courier and hybrid providers"
      businessType="logistics_provider"
    />
  )
}
