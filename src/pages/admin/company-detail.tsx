import { useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import {
  Ban,
  Building2,
  CreditCard,
  KeyRound,
  Mail,
  Plus,
  RotateCcw,
  ScrollText,
  Store,
  Users,
  Webhook,
} from 'lucide-react'
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
  ConfirmDialog,
  MetricList,
  MetricRow,
  SectionHeader,
  StatusChip,
} from '@/components/admin/control-tower'
import { formatLrd, statusColorFor } from '@/lib/admin-control-tower'
import { useCompany360 } from '@/hooks/use-admin-platform'
import { useAdminCompanyActions } from '@/hooks/use-admin'

type PendingAction = { kind: 'activate' | 'suspend' | 'restore' } | null

export function AdminCompanyDetailPage() {
  const { id } = useParams<{ id: string }>()
  const { data, isLoading, error } = useCompany360(id, true)
  const { statusMutation, smsMutation } = useAdminCompanyActions()
  const [pendingAction, setPendingAction] = useState<PendingAction>(null)

  if (isLoading) return <p className="text-sm text-zinc-500">Loading company…</p>
  if (error || !data) {
    return <p className="text-sm text-red-400">{error instanceof Error ? error.message : 'Company not found'}</p>
  }

  const company = data.company as Record<string, unknown>
  const health = data.health as { level: string; reasons: string[] }
  const counts = data.counts as Record<string, number>
  const owner = data.owner as { full_name: string | null; phone: string | null; role: string } | null
  const branches = (data.branches ?? []) as Array<{ id: string; name: string; code: string; city: string | null; is_active: boolean }>
  const webhooks = data.webhooks as Record<string, unknown> | undefined
  const recentErrors = (data.recent_webhook_errors ?? []) as Array<{
    event_type: string
    status: string
    last_error: string | null
    created_at: string
  }>
  const auditRecent = (data.audit_recent ?? []) as Array<{
    action: string
    entity_type: string
    entity_id: string | null
    created_at: string
  }>
  const apiKeys = (data.api_keys ?? []) as Array<{
    name: string
    key_prefix: string
    is_active: boolean
    last_used_at: string | null
    created_at: string
  }>
  const usage = data.usage as Record<string, unknown> | undefined
  const usageDetail = usage?.usage as Record<string, number> | undefined
  const limits = usage?.limits as Record<string, number | null> | undefined
  const trial = usage?.trial as Record<string, unknown> | undefined
  const plan = data.plan as Record<string, unknown> | null
  const subscription = data.subscription as Record<string, unknown> | null
  const marketplace = data.marketplace as Record<string, unknown> | null

  const name = String(company.name ?? 'Company')
  const status = String(company.status ?? '')
  const smsCredits = Number(company.sms_credits ?? 0)

  const runStatusChange = (nextStatus: 'active' | 'suspended') => {
    if (!id) return
    statusMutation.mutate(
      { id, status: nextStatus },
      { onSuccess: () => setPendingAction(null) },
    )
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p className="text-xs font-medium uppercase tracking-wide text-zinc-500">Company 360</p>
          <h2 className="text-2xl font-semibold text-white">{name}</h2>
          <p className="mt-1 text-sm text-zinc-400">
            {String(company.business_type).replace(/_/g, ' ')} · created {new Date(String(company.created_at)).toLocaleDateString()}
          </p>
          <div className="mt-2 flex flex-wrap items-center gap-2">
            <StatusChip color={statusColorFor(status)} label={status} />
            <StatusChip color={statusColorFor(health?.level)} label={`health: ${health?.level ?? 'unknown'}`} />
            {trial && Boolean(trial.is_free_trial) && (
              <StatusChip
                color={Number(trial.days_remaining ?? 0) > 0 ? 'amber' : 'red'}
                label={`trial: ${trial.days_remaining ?? 0}d remaining`}
              />
            )}
          </div>
          {health?.reasons?.length > 0 && (
            <p className="mt-1 text-xs text-zinc-500">{health.reasons.join(' · ')}</p>
          )}
        </div>
        <div className="flex flex-wrap gap-2">
          {status !== 'active' && (
            <button
              onClick={() => setPendingAction({ kind: status === 'suspended' ? 'restore' : 'activate' })}
              className="rounded-lg bg-[#FFCB05] px-3.5 py-2 text-xs font-semibold text-black hover:brightness-95"
            >
              {status === 'suspended' ? (
                <span className="inline-flex items-center gap-1.5">
                  <RotateCcw className="h-3.5 w-3.5" /> Restore
                </span>
              ) : (
                'Activate'
              )}
            </button>
          )}
          {status === 'active' && (
            <button
              onClick={() => setPendingAction({ kind: 'suspend' })}
              className="inline-flex items-center gap-1.5 rounded-lg border border-red-400/30 bg-red-400/[0.08] px-3.5 py-2 text-xs font-semibold text-red-300 hover:bg-red-400/[0.15]"
            >
              <Ban className="h-3.5 w-3.5" /> Suspend
            </button>
          )}
          <button
            disabled={smsMutation.isPending}
            onClick={() => id && smsMutation.mutate({ id, amount: 100 })}
            className="inline-flex items-center gap-1.5 rounded-lg border border-white/10 bg-white/[0.03] px-3.5 py-2 text-xs font-medium text-zinc-300 hover:bg-white/[0.06] disabled:opacity-50"
          >
            <Plus className="h-3.5 w-3.5" /> {smsMutation.isPending ? 'Adding…' : '100 SMS credits'}
          </button>
          <Link
            to="/admin/subscriptions"
            className="inline-flex items-center gap-1.5 rounded-lg border border-white/10 px-3.5 py-2 text-xs font-medium text-zinc-300 hover:bg-white/5"
          >
            <CreditCard className="h-3.5 w-3.5" /> Inspect subscription
          </Link>
        </div>
      </div>

      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
        <CommandKpi label="Deliveries (all-time)" value={String(counts.deliveries)} icon={Building2} />
        <CommandKpi label="Riders" value={String(counts.riders)} icon={Users} />
        <CommandKpi label="Customers" value={String(counts.customers)} icon={Users} />
        <CommandKpi label="Branches" value={String(counts.branches)} icon={Building2} />
        <CommandKpi
          label="SMS credits"
          value={String(smsCredits)}
          color={smsCredits <= 0 ? 'red' : smsCredits < 10 ? 'amber' : undefined}
          icon={Mail}
        />
      </div>

      <div className="grid gap-4 xl:grid-cols-3">
        <CommandCard>
          <CommandCardHeader title="Identity & contact" />
          <CommandCardBody>
            <MetricList>
              <MetricRow label="Business phone" value={String(company.phone ?? '—')} />
              <MetricRow label="Business email" value={String(company.email ?? '—')} />
              <MetricRow label="Address" value={String(company.address ?? '—')} />
              <MetricRow
                label="Owner"
                value={owner?.full_name ?? 'Not on file'}
                hint={owner?.phone ?? undefined}
              />
            </MetricList>
          </CommandCardBody>
        </CommandCard>

        <CommandCard>
          <CommandCardHeader title="Subscription" />
          <CommandCardBody>
            <MetricList>
              <MetricRow label="Plan" value={plan ? String(plan.name) : '—'} />
              <MetricRow label="Status" value={subscription ? String(subscription.status) : String(trial?.status ?? '—')} />
              <MetricRow
                label="Price"
                value={plan?.price_lrd_cents != null ? `${formatLrd(Number(plan.price_lrd_cents))}/mo` : '—'}
              />
              <MetricRow
                label="Trial ends"
                value={trial?.trial_ends_at ? new Date(String(trial.trial_ends_at)).toLocaleDateString() : '—'}
              />
            </MetricList>
          </CommandCardBody>
        </CommandCard>

        <CommandCard>
          <CommandCardHeader title="Usage vs. limits" description="Current billing period" />
          <CommandCardBody>
            <MetricList>
              <UsageRow label="Deliveries" used={usageDetail?.deliveries_created} limit={limits?.max_deliveries_per_month} />
              <UsageRow label="Riders" used={usageDetail?.riders} limit={limits?.max_riders} />
              <UsageRow label="SMS" used={usageDetail?.sms_consumed} limit={limits?.monthly_sms_allowance} />
            </MetricList>
          </CommandCardBody>
        </CommandCard>
      </div>

      <section>
        <SectionHeader eyebrow="Branches" />
        {branches.length === 0 ? (
          <CommandCard>
            <CommandEmptyState label="No branches configured." />
          </CommandCard>
        ) : (
          <CommandCard>
            <CommandTable>
              <CommandTableHead>
                <CommandTh>Name</CommandTh>
                <CommandTh>Code</CommandTh>
                <CommandTh>City</CommandTh>
                <CommandTh className="text-right">Status</CommandTh>
              </CommandTableHead>
              <tbody>
                {branches.map((b) => (
                  <CommandTr key={b.id}>
                    <CommandTd>{b.name}</CommandTd>
                    <CommandTd className="font-mono text-xs text-zinc-400">{b.code}</CommandTd>
                    <CommandTd>{b.city ?? '—'}</CommandTd>
                    <CommandTd className="text-right">
                      <StatusChip color={b.is_active ? 'green' : 'gray'} label={b.is_active ? 'active' : 'inactive'} />
                    </CommandTd>
                  </CommandTr>
                ))}
              </tbody>
            </CommandTable>
          </CommandCard>
        )}
      </section>

      <div className="grid gap-4 xl:grid-cols-2">
        <CommandCard>
          <CommandCardHeader
            title={
              <span className="inline-flex items-center gap-1.5">
                <Webhook className="h-3.5 w-3.5 text-zinc-500" /> Webhook health
              </span>
            }
          />
          <CommandCardBody>
            {webhooks ? (
              <MetricList>
                <MetricRow label="Active endpoints" value={String(webhooks.endpoints_active)} hint={`${webhooks.endpoints_total} total`} />
                <MetricRow label="Delivered (24h)" value={String(webhooks.delivered_24h)} />
                <MetricRow
                  label="Failed (24h)"
                  value={String(webhooks.failed_24h)}
                  hint={Number(webhooks.failed_24h) > 0 ? 'Needs attention' : undefined}
                />
                <MetricRow
                  label="Last failure"
                  value={webhooks.last_failure_at ? new Date(String(webhooks.last_failure_at)).toLocaleString() : 'None recorded'}
                />
              </MetricList>
            ) : (
              <p className="text-sm text-zinc-500">No webhook data.</p>
            )}
            {recentErrors.length > 0 && (
              <div className="mt-4 space-y-2 border-t border-white/[0.06] pt-3">
                <p className="text-xs font-medium uppercase tracking-wide text-zinc-500">Recent errors</p>
                {recentErrors.map((e, i) => (
                  <div key={i} className="rounded-lg border border-red-400/20 bg-red-400/[0.05] px-3 py-2 text-xs">
                    <div className="flex items-center justify-between">
                      <span className="font-medium text-red-300">{e.event_type}</span>
                      <span className="text-zinc-500">{new Date(e.created_at).toLocaleString()}</span>
                    </div>
                    {e.last_error && <p className="mt-1 truncate text-zinc-400">{e.last_error}</p>}
                  </div>
                ))}
              </div>
            )}
          </CommandCardBody>
        </CommandCard>

        <CommandCard>
          <CommandCardHeader
            title={
              <span className="inline-flex items-center gap-1.5">
                <KeyRound className="h-3.5 w-3.5 text-zinc-500" /> API keys
              </span>
            }
          />
          {apiKeys.length === 0 ? (
            <CommandEmptyState label="No API keys issued." />
          ) : (
            <CommandTable>
              <CommandTableHead>
                <CommandTh>Name</CommandTh>
                <CommandTh>Prefix</CommandTh>
                <CommandTh>Last used</CommandTh>
                <CommandTh className="text-right">Status</CommandTh>
              </CommandTableHead>
              <tbody>
                {apiKeys.map((k, i) => (
                  <CommandTr key={i}>
                    <CommandTd>{k.name}</CommandTd>
                    <CommandTd className="font-mono text-xs text-zinc-400">{k.key_prefix}···</CommandTd>
                    <CommandTd className="text-xs text-zinc-500">
                      {k.last_used_at ? new Date(k.last_used_at).toLocaleDateString() : 'Never'}
                    </CommandTd>
                    <CommandTd className="text-right">
                      <StatusChip color={k.is_active ? 'green' : 'gray'} label={k.is_active ? 'active' : 'revoked'} />
                    </CommandTd>
                  </CommandTr>
                ))}
              </tbody>
            </CommandTable>
          )}
        </CommandCard>
      </div>

      <div className="grid gap-4 xl:grid-cols-2">
        <CommandCard>
          <CommandCardHeader
            title={
              <span className="inline-flex items-center gap-1.5">
                <Store className="h-3.5 w-3.5 text-zinc-500" /> Marketplace activity
              </span>
            }
          />
          <CommandCardBody>
            {marketplace ? (
              <MetricList>
                <MetricRow label="Marketplace enabled" value={marketplace.marketplace_enabled ? 'Yes' : 'No'} />
                <MetricRow label="Accepting jobs" value={marketplace.accepting_jobs ? 'Yes' : 'No'} />
                <MetricRow label="Service phone" value={String(marketplace.service_phone ?? '—')} />
              </MetricList>
            ) : (
              <p className="text-sm text-zinc-500">Not participating in the marketplace.</p>
            )}
          </CommandCardBody>
        </CommandCard>

        <CommandCard>
          <CommandCardHeader
            title={
              <span className="inline-flex items-center gap-1.5">
                <ScrollText className="h-3.5 w-3.5 text-zinc-500" /> Audit history
              </span>
            }
          />
          {auditRecent.length === 0 ? (
            <CommandEmptyState label="No audit entries recorded for this company." />
          ) : (
            <CommandTable>
              <CommandTableHead>
                <CommandTh>Action</CommandTh>
                <CommandTh>Entity</CommandTh>
                <CommandTh className="text-right">When</CommandTh>
              </CommandTableHead>
              <tbody>
                {auditRecent.map((a, i) => (
                  <CommandTr key={i}>
                    <CommandTd>{a.action}</CommandTd>
                    <CommandTd className="text-zinc-400">{a.entity_type}</CommandTd>
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

      <ConfirmDialog
        open={pendingAction?.kind === 'suspend'}
        title={`Suspend ${name}?`}
        description="This immediately blocks the company and its riders/dispatchers from using DeliveryOS. Their data is preserved and this can be reversed with Restore."
        confirmLabel="Suspend company"
        danger
        pending={statusMutation.isPending}
        onConfirm={() => runStatusChange('suspended')}
        onCancel={() => setPendingAction(null)}
      />
      <ConfirmDialog
        open={pendingAction?.kind === 'activate' || pendingAction?.kind === 'restore'}
        title={pendingAction?.kind === 'restore' ? `Restore ${name}?` : `Activate ${name}?`}
        description={
          pendingAction?.kind === 'restore'
            ? 'This lifts the suspension and immediately restores access for this company.'
            : 'This grants this company full access to DeliveryOS.'
        }
        confirmLabel={pendingAction?.kind === 'restore' ? 'Restore company' : 'Activate company'}
        danger={false}
        pending={statusMutation.isPending}
        onConfirm={() => runStatusChange('active')}
        onCancel={() => setPendingAction(null)}
      />
    </div>
  )
}

function UsageRow({ label, used, limit }: { label: string; used?: number; limit?: number | null }) {
  const u = used ?? 0
  const hasLimit = limit != null
  const pct = hasLimit && limit! > 0 ? Math.min(100, Math.round((u / limit!) * 100)) : null
  return (
    <MetricRow
      label={label}
      value={hasLimit ? `${u} / ${limit}` : String(u)}
      hint={pct !== null ? `${pct}% of allowance` : 'No limit on this plan'}
    />
  )
}
