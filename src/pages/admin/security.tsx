import { KeyRound, Lock, ShieldAlert, ShieldCheck, UserCog } from 'lucide-react'
import {
  CommandCard,
  CommandCardBody,
  CommandCardHeader,
  CommandEmptyState,
  CommandKpi,
  CommandTable,
  CommandTableHead,
  CommandTd,
  CommandTh,
  CommandTr,
  SectionHeader,
} from '@/components/admin/control-tower'
import { useExtendedHealth, useSecuritySnapshot } from '@/hooks/use-admin-platform'

export function AdminSecurityPage() {
  const { data: health } = useExtendedHealth(true)
  const { data, isLoading } = useSecuritySnapshot(true)

  const authFailures24h = Number(health?.api_auth_failures_24h ?? 0)
  const failingPrefixes24h = Number(data?.distinct_failing_key_prefixes_24h ?? 0)
  const recentFailures = (data?.recent_auth_failures ?? []) as Array<{
    key_prefix: string | null
    error_code: string | null
    company_name: string | null
    created_at: string
  }>
  const recentAdminActions = (data?.recent_admin_actions ?? []) as Array<{
    actor_name: string | null
    action: string
    entity_type: string
    company_name: string | null
    created_at: string
  }>

  return (
    <div className="space-y-8">
      <SectionHeader eyebrow="Security" title="Security posture" className="mb-0" />

      <div className="grid gap-3 sm:grid-cols-3">
        <CommandKpi
          label="API auth failures (24h)"
          value={String(authFailures24h)}
          icon={ShieldAlert}
          color={authFailures24h >= 20 ? 'red' : authFailures24h > 0 ? 'amber' : 'green'}
          loading={!health}
        />
        <CommandKpi
          label="Distinct failing key prefixes (24h)"
          value={String(failingPrefixes24h)}
          hint="Concentrated failures can indicate credential stuffing"
          icon={KeyRound}
          color={failingPrefixes24h >= 5 ? 'red' : undefined}
          loading={isLoading}
        />
        <CommandKpi label="RLS enforcement" value="Enabled" hint="All tenant tables" icon={Lock} color="green" />
      </div>

      <div className="grid gap-4 xl:grid-cols-2">
        <CommandCard>
          <CommandCardHeader title="Recent API auth failures" description="Most recent, most recent first — no key material shown" />
          {recentFailures.length === 0 ? (
            <CommandEmptyState label="No API auth failures recorded." />
          ) : (
            <CommandTable>
              <CommandTableHead>
                <CommandTh>Key prefix</CommandTh>
                <CommandTh>Error</CommandTh>
                <CommandTh>Company</CommandTh>
                <CommandTh className="text-right">When</CommandTh>
              </CommandTableHead>
              <tbody>
                {recentFailures.map((f, i) => (
                  <CommandTr key={i}>
                    <CommandTd className="font-mono text-xs text-zinc-400">{f.key_prefix ?? '—'}···</CommandTd>
                    <CommandTd className="text-red-300">{f.error_code ?? 'unknown'}</CommandTd>
                    <CommandTd>{f.company_name ?? '—'}</CommandTd>
                    <CommandTd className="text-right text-xs text-zinc-500">
                      {new Date(f.created_at).toLocaleString()}
                    </CommandTd>
                  </CommandTr>
                ))}
              </tbody>
            </CommandTable>
          )}
        </CommandCard>

        <CommandCard>
          <CommandCardHeader
            title={
              <span className="inline-flex items-center gap-1.5">
                <UserCog className="h-3.5 w-3.5 text-zinc-500" /> Super-admin actions
              </span>
            }
            description="Privileged actions performed by super-admin accounts, from the audit log"
          />
          {recentAdminActions.length === 0 ? (
            <CommandEmptyState label="No super-admin actions recorded yet." />
          ) : (
            <CommandTable>
              <CommandTableHead>
                <CommandTh>Admin</CommandTh>
                <CommandTh>Action</CommandTh>
                <CommandTh>Company</CommandTh>
                <CommandTh className="text-right">When</CommandTh>
              </CommandTableHead>
              <tbody>
                {recentAdminActions.map((a, i) => (
                  <CommandTr key={i}>
                    <CommandTd>{a.actor_name ?? 'Unknown'}</CommandTd>
                    <CommandTd className="text-zinc-300">{a.action}</CommandTd>
                    <CommandTd>{a.company_name ?? '—'}</CommandTd>
                    <CommandTd className="text-right text-xs text-zinc-500">
                      {new Date(a.created_at).toLocaleString()}
                    </CommandTd>
                  </CommandTr>
                ))}
              </tbody>
            </CommandTable>
          )}
        </CommandCard>
      </div>

      <CommandCard>
        <CommandCardHeader
          title={
            <span className="inline-flex items-center gap-1.5">
              <ShieldCheck className="h-3.5 w-3.5 text-zinc-500" /> Tenant isolation & RLS posture
            </span>
          }
        />
        <CommandCardBody className="space-y-2 text-sm text-zinc-400">
          <p>
            Every tenant-scoped table enforces row-level security keyed off <code className="text-zinc-300">company_id</code>,
            checked against <code className="text-zinc-300">user_company_ids()</code> and role via{' '}
            <code className="text-zinc-300">has_company_role()</code>. Super-admin reads and actions run through{' '}
            <code className="text-zinc-300">SECURITY DEFINER</code> functions gated by{' '}
            <code className="text-zinc-300">is_super_admin()</code>.
          </p>
          <p>
            This is a static description of the enforced architecture, not a live penetration test. Secret values (API keys,
            webhook signing secrets, service credentials) are never returned by any admin surface — only prefixes,
            presence/absence, and failure metadata are shown.
          </p>
          <p className="text-zinc-500">
            Sensitive configuration readiness (which Edge Function secrets are set) is not observable from the database and
            is not instrumented here — see Integrations → MTN for what is tracked.
          </p>
        </CommandCardBody>
      </CommandCard>
    </div>
  )
}
