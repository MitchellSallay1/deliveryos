import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { Link } from 'react-router-dom'
import { useBillingPaymentsPage, useCompanyUsage, useInvoicesPage, usePublicPlans } from '@/hooks/use-billing'
import { formatTrialEndsAt, trialBannerMessage } from '@/lib/trial-display'
import { formatLrdFromCents } from '@/utils/delivery-schemas'
import { Button } from '@/components/ui/Button'

export function BillingSettingsSection({ companyId }: { companyId: string }) {
  const { data: usage, isLoading } = useCompanyUsage(companyId)
  const { data: invoices } = useInvoicesPage({ companyId, page: 1 }, true)
  const { data: payments } = useBillingPaymentsPage(companyId, 1, true)
  const { data: plans = [] } = usePublicPlans(!!companyId)

  const plan = usage?.plan as Record<string, unknown> | undefined
  const sub = usage?.subscription as Record<string, unknown> | undefined
  const trialMsg = trialBannerMessage(usage?.trial)
  const limits = usage?.limits
  const u = usage?.usage
  const period = usage?.period

  return (
    <Card>
      <CardHeader>
        <CardTitle>Billing & subscription</CardTitle>
        <CardDescription>Usage and invoices for the current billing period</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4 text-sm">
        {isLoading && <p className="text-[var(--color-muted)]">Loading usage…</p>}
        {trialMsg && (
          <div className="rounded-md border border-sky-200 bg-sky-50 px-3 py-2 text-sm">
            <p className="font-medium">{trialMsg.headline}</p>
            <p className="text-[var(--color-muted)]">{trialMsg.detail}</p>
            {usage?.trial?.trial_ends_at && (
              <p className="mt-1 text-xs text-[var(--color-muted)]">
                Trial ends: {formatTrialEndsAt(usage.trial.trial_ends_at)}
              </p>
            )}
            <Link to="/billing" className="mt-2 inline-block">
              <Button type="button" size="sm" variant="outline">
                Choose plan
              </Button>
            </Link>
          </div>
        )}
        {plan && (
          <>
            <div>
              <p className="font-medium">{String(plan.name)} plan</p>
              <p className="text-[var(--color-muted)]">
                Status: <span className="capitalize">{String(sub?.status ?? 'legacy')}</span> ·{' '}
                {formatLrdFromCents(Number(plan.price_lrd_cents))} {String(plan.currency)}/mo
              </p>
              {period && (
                <p className="text-xs text-[var(--color-muted)]">
                  Billing period: {new Date(period.start).toLocaleDateString()} –{' '}
                  {new Date(period.end).toLocaleDateString()}
                </p>
              )}
            </div>
            {limits && u && (
              <dl className="grid gap-2 sm:grid-cols-3">
                <UsageStat
                  label="Deliveries"
                  value={u.deliveries_created}
                  max={limits.max_deliveries_per_month}
                />
                <UsageStat label="Riders" value={u.riders} max={limits.max_riders} />
                <UsageStat
                  label="SMS"
                  value={u.sms_consumed}
                  max={limits.monthly_sms_allowance}
                />
              </dl>
            )}
            <div>
              <p className="mb-1 text-xs font-medium uppercase text-[var(--color-muted)]">
                Plan features
              </p>
              <ul className="list-inside list-disc text-xs text-[var(--color-muted)]">
                {plan.proof_of_delivery ? <li>Proof of delivery</li> : null}
                {plan.advanced_reports ? <li>Advanced reports</li> : null}
                {plan.custom_branding ? <li>Custom branding</li> : null}
                {plan.api_access ? <li>API access (future)</li> : null}
                {plan.gps_tracking ? <li>GPS tracking (future)</li> : null}
              </ul>
            </div>
            <div>
              <p className="mb-2 font-medium">Upgrade plan</p>
              <p className="text-xs text-[var(--color-muted)]">
                Online checkout is not enabled yet. Contact DeliveryOS administration to change
                plan. Available plans:{' '}
                {(plans as unknown as { name: string }[]).length
                  ? (plans as unknown as { name: string }[]).map((p) => p.name).join(', ')
                  : 'Starter, Business, Enterprise'}
              </p>
            </div>
            <div>
              <p className="mb-1 font-medium">Recent subscription payments</p>
              <ul className="text-xs text-[var(--color-muted)]">
                {((payments?.rows ?? []) as Record<string, unknown>[]).slice(0, 5).map((p) => (
                  <li key={String(p.id)}>
                    {formatLrdFromCents(Number(p.amount_cents))} · {String(p.payment_method)} ·{' '}
                    {p.paid_at ? new Date(String(p.paid_at)).toLocaleDateString() : '—'}
                  </li>
                ))}
                {!payments?.rows?.length && <li>No recorded payments yet.</li>}
              </ul>
            </div>
            <div>
              <p className="mb-1 font-medium">Recent invoices</p>
              <ul className="text-xs text-[var(--color-muted)]">
                {((invoices?.rows ?? []) as Record<string, unknown>[]).slice(0, 5).map((inv) => (
                  <li key={String(inv.id)}>
                    {String(inv.invoice_number)} · {String(inv.status)} ·{' '}
                    {formatLrdFromCents(Number(inv.amount_cents))}
                  </li>
                ))}
                {!invoices?.rows?.length && <li>No invoices yet.</li>}
              </ul>
            </div>
          </>
        )}
      </CardContent>
    </Card>
  )
}

function UsageStat({
  label,
  value,
  max,
}: {
  label: string
  value: number
  max: number | null
}) {
  return (
    <div className="rounded-lg border p-3">
      <dt className="text-xs uppercase text-[var(--color-muted)]">{label}</dt>
      <dd className="mt-1 font-semibold">
        {value} / {max == null ? '∞' : max}
      </dd>
    </div>
  )
}
