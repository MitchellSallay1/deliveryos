import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { Button } from '@/components/ui/Button'
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
    <Card>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        <CardDescription>{description}</CardDescription>
      </CardHeader>
      <CardContent>
        <Input
          className="mb-3 max-w-sm"
          placeholder="Search name, phone, email"
          value={search}
          onChange={(e) => {
            setSearch(e.target.value)
            setPage(1)
          }}
        />
        {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
        <DirectoryTable rows={rows} busy={statusMutation.isPending} onStatus={(id, status) => statusMutation.mutate({ id, status })} />
        <Pager total={total} page={page} pageSize={PAGE} onPage={setPage} />
      </CardContent>
    </Card>
  )
}

function DirectoryTable({
  rows,
  busy,
  onStatus,
}: {
  rows: Record<string, unknown>[]
  busy: boolean
  onStatus: (id: string, status: 'pending' | 'active' | 'suspended') => void
}) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[800px] text-left text-sm">
        <thead>
          <tr className="border-b text-xs uppercase text-[var(--color-muted)]">
            <th className="py-2">Company</th>
            <th className="py-2">Type</th>
            <th className="py-2">Plan</th>
            <th className="py-2">Status</th>
            <th className="py-2">Actions</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((c) => (
            <tr key={String(c.id)} className="border-b">
              <td className="py-2">
                <Link className="font-medium text-[var(--color-primary)] hover:underline" to={`/admin/companies/${c.id}`}>
                  {String(c.name)}
                </Link>
              </td>
              <td className="py-2 text-xs">{String(c.business_type ?? '—')}</td>
              <td className="py-2 text-xs">{String(c.plan_name ?? '—')}</td>
              <td className="py-2 capitalize">{String(c.status)}</td>
              <td className="py-2">
                <div className="flex flex-wrap gap-1">
                  {c.status !== 'active' && (
                    <Button size="sm" disabled={busy} onClick={() => onStatus(String(c.id), 'active')}>
                      Activate
                    </Button>
                  )}
                  {c.status === 'active' && (
                    <Button size="sm" variant="outline" disabled={busy} onClick={() => onStatus(String(c.id), 'suspended')}>
                      Suspend
                    </Button>
                  )}
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function Pager({
  total,
  page,
  pageSize,
  onPage,
}: {
  total: number
  page: number
  pageSize: number
  onPage: (p: number) => void
}) {
  return (
    <>
      <p className="mt-2 text-xs text-[var(--color-muted)]">
        {total} results · page {page}
      </p>
      <div className="mt-2 flex gap-2">
        <Button size="sm" variant="outline" disabled={page <= 1} onClick={() => onPage(page - 1)}>
          Previous
        </Button>
        <Button size="sm" variant="outline" disabled={page * pageSize >= total} onClick={() => onPage(page + 1)}>
          Next
        </Button>
      </div>
    </>
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
