import { useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { TabPanel, Tabs } from '@/components/ui/Tabs'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { Button } from '@/components/ui/Button'
import { AdminHealthBadge, AdminHealthReasons } from '@/components/admin/AdminHealthBadge'
import { useCompany360 } from '@/hooks/use-admin-platform'
import { useAdminCompanyActions } from '@/hooks/use-admin'

export function AdminCompanyDetailPage() {
  const { id } = useParams<{ id: string }>()
  const { data, isLoading, error } = useCompany360(id, true)
  const { statusMutation, smsMutation } = useAdminCompanyActions()

  const [tab, setTab] = useState('overview')

  if (isLoading) return <p className="text-sm text-[var(--color-muted)]">Loading company…</p>
  if (error || !data) {
    return <p className="text-sm text-red-600">{error instanceof Error ? error.message : 'Not found'}</p>
  }

  const company = data.company as Record<string, unknown>
  const health = data.health as { level: string; reasons: string[] }
  const counts = data.counts as Record<string, number>
  const name = String(company.name ?? 'Company')

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p className="text-xs uppercase text-[var(--color-muted)]">Company 360</p>
          <h2 className="text-2xl font-semibold">{name}</h2>
          <p className="text-sm text-[var(--color-muted)]">
            {String(company.business_type)} · {String(company.status)} · created {String(company.created_at)}
          </p>
          <div className="mt-2">
            <AdminHealthBadge level={health.level} />
            <AdminHealthReasons reasons={health.reasons ?? []} />
          </div>
        </div>
        <div className="flex flex-wrap gap-2">
          {company.status !== 'active' && (
            <Button
              size="sm"
              disabled={statusMutation.isPending}
              onClick={() => id && statusMutation.mutate({ id, status: 'active' })}
            >
              Activate
            </Button>
          )}
          {company.status === 'active' && (
            <Button
              size="sm"
              variant="outline"
              disabled={statusMutation.isPending}
              onClick={() => id && statusMutation.mutate({ id, status: 'suspended' })}
            >
              Suspend
            </Button>
          )}
          <Button
            size="sm"
            variant="outline"
            disabled={smsMutation.isPending}
            onClick={() => id && smsMutation.mutate({ id, amount: 100 })}
          >
            +100 SMS credits
          </Button>
          <Link to="/admin/subscriptions">
            <Button size="sm" variant="ghost">
              Change plan
            </Button>
          </Link>
        </div>
      </div>

      <div className="grid gap-4 sm:grid-cols-4">
        <Stat label="Deliveries" value={counts.deliveries} />
        <Stat label="Riders" value={counts.riders} />
        <Stat label="Users" value={counts.users} />
        <Stat label="API keys" value={counts.api_keys} />
      </div>

      <Tabs
        value={tab}
        onValueChange={setTab}
        items={[
          { value: 'overview', label: 'Overview' },
          { value: 'usage', label: 'Usage' },
          { value: 'billing', label: 'Billing' },
          { value: 'marketplace', label: 'Marketplace' },
          { value: 'audit', label: 'Audit' },
        ]}
      />
      <TabPanel value="overview" active={tab}>
        <OverviewTab data={data} />
      </TabPanel>
      <TabPanel value="usage" active={tab}>
        <pre className="overflow-auto rounded-lg bg-zinc-50 p-3 text-xs">{JSON.stringify(data.usage, null, 2)}</pre>
      </TabPanel>
      <TabPanel value="billing" active={tab}>
        <pre className="overflow-auto rounded-lg bg-zinc-50 p-3 text-xs">{JSON.stringify(data.subscription, null, 2)}</pre>
      </TabPanel>
      <TabPanel value="marketplace" active={tab}>
        <pre className="overflow-auto rounded-lg bg-zinc-50 p-3 text-xs">{JSON.stringify(data.marketplace, null, 2)}</pre>
      </TabPanel>
      <TabPanel value="audit" active={tab}>
        <p className="text-sm text-[var(--color-muted)]">
          <Link to="/admin/audit" className="underline">
            Open platform audit
          </Link>{' '}
          — filter by company ID {id} manually for now.
        </p>
      </TabPanel>
    </div>
  )
}

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-xs font-medium uppercase text-[var(--color-muted)]">{label}</CardTitle>
      </CardHeader>
      <CardContent>
        <p className="text-2xl font-semibold tabular-nums">{value}</p>
      </CardContent>
    </Card>
  )
}

function OverviewTab({ data }: { data: Record<string, unknown> }) {
  const plan = data.plan as Record<string, unknown> | null
  return (
    <Card>
      <CardContent className="pt-6 text-sm">
        <dl className="grid gap-2 sm:grid-cols-2">
          <div>
            <dt className="text-xs text-[var(--color-muted)]">Plan</dt>
            <dd>{plan ? String(plan.name) : '—'}</dd>
          </div>
          <div>
            <dt className="text-xs text-[var(--color-muted)]">SMS credits</dt>
            <dd>{String((data.company as Record<string, unknown>).sms_credits ?? 0)}</dd>
          </div>
        </dl>
      </CardContent>
    </Card>
  )
}
