import { useState } from 'react'
import { supabase } from '@/lib/supabase/client'
import { sanitizeIlikeSearchTerm } from '@/lib/postgrest-search'
import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import {
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

const PAGE = 25

async function listRiders(search: string, page: number) {
  let q = supabase
    .from('riders')
    .select('id, full_name, rider_code, phone, status, company_id', { count: 'exact' })
    .order('created_at', { ascending: false })
    .range((page - 1) * PAGE, page * PAGE - 1)
  const s = sanitizeIlikeSearchTerm(search.trim())
  if (s) {
    q = q.or(`rider_code.ilike.%${s}%,phone.ilike.%${s}%,full_name.ilike.%${s}%`)
  }
  const { data, error, count } = await q
  if (error) throw error
  return { rows: data ?? [], total: count ?? 0 }
}

export function AdminRidersPage() {
  const [search, setSearch] = useState('')
  const [page, setPage] = useState(1)
  const { data, isLoading } = useQuery({
    queryKey: ['admin', 'riders', search, page],
    queryFn: () => listRiders(search, page),
  })
  const rows = data?.rows ?? []
  const total = data?.total ?? 0

  return (
    <div className="space-y-4">
      <SectionHeader eyebrow="Riders" title="Platform riders" className="mb-0" />
      <CommandCard>
        <CommandCardBody className="border-b border-white/[0.06] pb-4">
          <CommandInput
            className="max-w-sm"
            placeholder="Search rider code, phone, name"
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
          <CommandEmptyState label="No riders match this search." />
        ) : (
          <CommandTable>
            <CommandTableHead>
              <CommandTh>Rider</CommandTh>
              <CommandTh>Company</CommandTh>
              <CommandTh className="text-right">Status</CommandTh>
            </CommandTableHead>
            <tbody>
              {rows.map((r) => (
                <CommandTr key={r.id}>
                  <CommandTd>{r.full_name}</CommandTd>
                  <CommandTd>
                    <Link className="font-mono text-xs text-zinc-400 hover:text-white hover:underline" to={`/admin/companies/${r.company_id}`}>
                      {r.company_id.slice(0, 8)}…
                    </Link>
                  </CommandTd>
                  <CommandTd className="text-right">
                    <StatusChip color={statusColorFor(r.status)} label={r.status} />
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

async function listUsers(search: string, page: number) {
  let q = supabase
    .from('profiles')
    .select('id, full_name, phone, is_super_admin, created_at', { count: 'exact' })
    .order('created_at', { ascending: false })
    .range((page - 1) * PAGE, page * PAGE - 1)
  const s = sanitizeIlikeSearchTerm(search.trim())
  if (s) q = q.or(`phone.ilike.%${s}%,full_name.ilike.%${s}%`)
  const { data, error, count } = await q
  if (error) throw error
  return { rows: data ?? [], total: count ?? 0 }
}

export function AdminUsersPage() {
  const [search, setSearch] = useState('')
  const [page] = useState(1)
  const { data, isLoading } = useQuery({
    queryKey: ['admin', 'users', search, page],
    queryFn: () => listUsers(search, page),
  })
  const rows = data?.rows ?? []

  return (
    <div className="space-y-4">
      <SectionHeader eyebrow="Users" title="Platform users" className="mb-0" />
      <CommandCard>
        <CommandCardBody className="border-b border-white/[0.06] pb-4">
          <CommandInput
            className="max-w-sm"
            placeholder="Phone or name"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </CommandCardBody>
        {isLoading ? (
          <p className="p-4 text-sm text-zinc-500">Loading…</p>
        ) : rows.length === 0 ? (
          <CommandEmptyState label="No users match this search." />
        ) : (
          <CommandTable>
            <CommandTableHead>
              <CommandTh>Name</CommandTh>
              <CommandTh>Phone</CommandTh>
              <CommandTh className="text-right">Super admin</CommandTh>
            </CommandTableHead>
            <tbody>
              {rows.map((u) => (
                <CommandTr key={u.id}>
                  <CommandTd>{u.full_name ?? '—'}</CommandTd>
                  <CommandTd className="font-mono text-xs text-zinc-400">{u.phone ?? '—'}</CommandTd>
                  <CommandTd className="text-right">
                    {u.is_super_admin ? <StatusChip color="amber" label="Super admin" /> : <span className="text-zinc-600">—</span>}
                  </CommandTd>
                </CommandTr>
              ))}
            </tbody>
          </CommandTable>
        )}
      </CommandCard>
    </div>
  )
}
