import { useState } from 'react'
import { supabase } from '@/lib/supabase/client'
import { useQuery } from '@tanstack/react-query'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { Button } from '@/components/ui/Button'
import { Link } from 'react-router-dom'

const PAGE = 25

async function listRiders(search: string, page: number) {
  let q = supabase
    .from('riders')
    .select('id, full_name, rider_code, phone, status, company_id', { count: 'exact' })
    .order('created_at', { ascending: false })
    .range((page - 1) * PAGE, page * PAGE - 1)
  const s = search.trim()
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

  return (
    <Card>
      <CardHeader>
        <CardTitle>Platform riders</CardTitle>
      </CardHeader>
      <CardContent>
        <Input className="mb-3 max-w-sm" placeholder="Search" value={search} onChange={(e) => setSearch(e.target.value)} />
        {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
        <table className="w-full text-left text-sm">
          <thead>
            <tr className="border-b text-xs uppercase text-[var(--color-muted)]">
              <th className="py-2">Rider</th>
              <th className="py-2">Company</th>
              <th className="py-2">Status</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.id} className="border-b">
                <td className="py-2">{r.full_name}</td>
                <td className="py-2">
                  <Link className="underline" to={`/admin/companies/${r.company_id}`}>
                    {r.company_id.slice(0, 8)}…
                  </Link>
                </td>
                <td className="py-2 capitalize">{r.status}</td>
              </tr>
            ))}
          </tbody>
        </table>
        <div className="mt-2 flex gap-2">
          <Button size="sm" variant="outline" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>
            Previous
          </Button>
          <Button size="sm" variant="outline" onClick={() => setPage((p) => p + 1)}>
            Next
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}

async function listUsers(search: string, page: number) {
  let q = supabase
    .from('profiles')
    .select('id, full_name, phone, is_super_admin, created_at', { count: 'exact' })
    .order('created_at', { ascending: false })
    .range((page - 1) * PAGE, page * PAGE - 1)
  const s = search.trim()
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

  return (
    <Card>
      <CardHeader>
        <CardTitle>Platform users</CardTitle>
      </CardHeader>
      <CardContent>
        <Input className="mb-3 max-w-sm" placeholder="Phone or name" value={search} onChange={(e) => setSearch(e.target.value)} />
        {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
        <table className="w-full text-left text-sm">
          <thead>
            <tr className="border-b text-xs uppercase text-[var(--color-muted)]">
              <th className="py-2">Name</th>
              <th className="py-2">Phone</th>
              <th className="py-2">Super admin</th>
            </tr>
          </thead>
          <tbody>
            {(data?.rows ?? []).map((u) => (
              <tr key={u.id} className="border-b">
                <td className="py-2">{u.full_name ?? '—'}</td>
                <td className="py-2 font-mono text-xs">{u.phone ?? '—'}</td>
                <td className="py-2">{u.is_super_admin ? 'Yes' : '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </CardContent>
    </Card>
  )
}
