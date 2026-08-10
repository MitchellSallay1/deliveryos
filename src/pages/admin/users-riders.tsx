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
  CommandKpi,
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
import {
  PLATFORM_USER_LIFECYCLE_OPTIONS,
  platformUserLifecycleBadge,
  statusColorFor,
  type PlatformUserLifecycleStatus,
} from '@/lib/admin-control-tower'

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

type PlatformUserRow = {
  id: string
  full_name: string | null
  phone: string | null
  created_at: string
  phone_confirmed_at: string | null
  last_sign_in_at: string | null
  persona: string | null
  is_super_admin: boolean
  has_company_membership: boolean
  is_rider_linked: boolean
  lifecycle_status: string
}

type PlatformUserFunnel = {
  identities: number
  verified: number
  active: number
  unverified_over_30d: number
}

/**
 * Never queries public.profiles directly — a raw profiles row is not a
 * registered DeliveryOS user (signInWithOtp creates an unverified auth.users
 * + profiles row at OTP-request time, before verification). The lifecycle
 * status shown here is derived server-side by admin_list_platform_users, not
 * re-guessed from raw fields on the client.
 */
async function listPlatformUsers(search: string, status: string, page: number) {
  const { data, error } = await supabase.rpc('admin_list_platform_users', {
    p_search: search.trim() || null,
    p_status: status || null,
    p_limit: PAGE,
    p_offset: (page - 1) * PAGE,
  })
  if (error) throw error
  const payload = (data ?? { total: 0, rows: [] }) as { total: number; rows: PlatformUserRow[] }
  return { rows: payload.rows ?? [], total: payload.total ?? 0 }
}

async function fetchPlatformUserFunnel(): Promise<PlatformUserFunnel> {
  const { data, error } = await supabase.rpc('admin_platform_user_funnel')
  if (error) throw error
  return data as unknown as PlatformUserFunnel
}

export function AdminUsersPage() {
  const [search, setSearch] = useState('')
  const [status, setStatus] = useState<PlatformUserLifecycleStatus | ''>('')
  const [page, setPage] = useState(1)

  const { data, isLoading } = useQuery({
    queryKey: ['admin', 'platform-users', search, status, page],
    queryFn: () => listPlatformUsers(search, status, page),
  })
  const { data: funnel, isLoading: funnelLoading } = useQuery({
    queryKey: ['admin', 'platform-users', 'funnel'],
    queryFn: fetchPlatformUserFunnel,
  })
  const rows = data?.rows ?? []
  const total = data?.total ?? 0

  return (
    <div className="space-y-4">
      <SectionHeader eyebrow="Users" title="Platform users" className="mb-0" />

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <CommandKpi
          label="Identities"
          value={String(funnel?.identities ?? 0)}
          loading={funnelLoading}
          hint="Auth identities created, incl. unverified"
        />
        <CommandKpi
          label="Verified"
          value={String(funnel?.verified ?? 0)}
          loading={funnelLoading}
          hint="Phone number confirmed"
          color="amber"
        />
        <CommandKpi
          label="Active"
          value={String(funnel?.active ?? 0)}
          loading={funnelLoading}
          hint="Company or rider membership"
          color="green"
        />
        <CommandKpi
          label="Unverified 30d+"
          value={String(funnel?.unverified_over_30d ?? 0)}
          loading={funnelLoading}
          hint="Never verified, requested 30+ days ago"
          color="gray"
        />
      </div>

      <CommandCard>
        <CommandCardBody className="flex flex-wrap items-center gap-3 border-b border-white/[0.06] pb-4">
          <CommandInput
            className="max-w-sm"
            placeholder="Phone or name"
            value={search}
            onChange={(e) => {
              setSearch(e.target.value)
              setPage(1)
            }}
          />
          <CommandSelect
            className="max-w-[240px]"
            value={status}
            onChange={(e) => {
              setStatus(e.target.value as PlatformUserLifecycleStatus | '')
              setPage(1)
            }}
          >
            <option value="">All statuses</option>
            {PLATFORM_USER_LIFECYCLE_OPTIONS.map((o) => (
              <option key={o.value} value={o.value}>
                {o.label}
              </option>
            ))}
          </CommandSelect>
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
              <CommandTh>Persona</CommandTh>
              <CommandTh>Joined</CommandTh>
              <CommandTh className="text-right">Status</CommandTh>
            </CommandTableHead>
            <tbody>
              {rows.map((u) => {
                const badge = platformUserLifecycleBadge(u.lifecycle_status)
                return (
                  <CommandTr key={u.id}>
                    <CommandTd>{u.full_name ?? '—'}</CommandTd>
                    <CommandTd className="font-mono text-xs text-zinc-400">{u.phone ?? '—'}</CommandTd>
                    <CommandTd className="text-zinc-400">{u.persona ?? '—'}</CommandTd>
                    <CommandTd className="text-zinc-400">{new Date(u.created_at).toLocaleDateString()}</CommandTd>
                    <CommandTd className="text-right">
                      <StatusChip color={badge.color} label={badge.label} />
                    </CommandTd>
                  </CommandTr>
                )
              })}
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
