import { AlertTriangle, CreditCard, Gauge, ReceiptText, TrendingUp, Wallet } from 'lucide-react'
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
import { formatLrd, formatPercent, trialConversionRate } from '@/lib/admin-control-tower'
import { useCommandCenter, useTrialFunnel } from '@/hooks/use-admin-platform'
import { useBillingPaymentsPage, usePlatformBillingMetrics } from '@/hooks/use-billing'

export function AdminRevenuePage() {
  const { data: billingData, isLoading: billingLoading } = usePlatformBillingMetrics(true)
  const { data: cmd } = useCommandCenter(true)
  const { data: funnel } = useTrialFunnel(true)
  const { data: payments, isLoading: paymentsLoading } = useBillingPaymentsPage(null, 1, true)

  const billing = billingData as Record<string, unknown> | undefined
  const planBreakdown = (billing?.plan_breakdown ?? {}) as Record<string, number>
  const trialing = Number(funnel?.trialing ?? 0)
  const activatedActive = Number(funnel?.activated_active ?? 0)
  const conversion = trialConversionRate(trialing, activatedActive)

  const paymentRows = (payments?.rows ?? []) as Array<{
    id: string
    company_name: string
    amount_cents: number
    payment_method: string
    reference: string | null
    paid_at: string
  }>

  const planEntries = Object.entries(planBreakdown).sort((a, b) => b[1] - a[1])
  const maxPlanCount = Math.max(1, ...planEntries.map(([, count]) => count))

  return (
    <div className="space-y-8">
      <SectionHeader eyebrow="Revenue center" title="Commercial performance" className="mb-0" />

      <section>
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
          <CommandKpi
            label="Est. subscription MRR"
            value={cmd ? formatLrd(Number(cmd.subscription_mrr_estimate_cents)) : '—'}
            hint="Sum of active plan prices"
            icon={Wallet}
          />
          <CommandKpi
            label="MTD revenue"
            value={billing ? formatLrd(Number(billing.monthly_revenue_cents ?? 0)) : '—'}
            hint="Cash collected this calendar month"
            icon={CreditCard}
            loading={billingLoading}
          />
          <CommandKpi
            label="Active subscriptions"
            value={billing ? String(billing.active_subscriptions ?? 0) : '—'}
            icon={TrendingUp}
            loading={billingLoading}
          />
          <CommandKpi
            label="Trial → paid conversion"
            value={formatPercent(conversion)}
            hint={conversion === null ? 'No trial data yet' : `${activatedActive} of ${trialing + activatedActive}`}
            icon={Gauge}
          />
          <CommandKpi
            label="Past due"
            value={billing ? String(billing.past_due ?? 0) : '—'}
            icon={AlertTriangle}
            color={billing && Number(billing.past_due ?? 0) > 0 ? 'amber' : undefined}
            loading={billingLoading}
          />
        </div>
      </section>

      <div className="grid gap-4 xl:grid-cols-3">
        <CommandCard className="xl:col-span-1">
          <CommandCardHeader title="Subscription distribution" description="By plan, currently active/trialing/past-due" />
          <CommandCardBody>
            {planEntries.length === 0 ? (
              <p className="text-sm text-zinc-500">No subscriptions yet.</p>
            ) : (
              <div className="space-y-3">
                {planEntries.map(([slug, count]) => (
                  <div key={slug}>
                    <div className="flex items-center justify-between text-xs">
                      <span className="capitalize text-zinc-400">{slug.replace(/_/g, ' ')}</span>
                      <span className="font-medium tabular-nums text-zinc-200">{count}</span>
                    </div>
                    <div className="mt-1 h-2 overflow-hidden rounded-full bg-white/[0.05]">
                      <div
                        className="h-full rounded-full bg-[#FFCB05]"
                        style={{ width: `${Math.max(4, (count / maxPlanCount) * 100)}%` }}
                      />
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CommandCardBody>
        </CommandCard>

        <CommandCard className="xl:col-span-1">
          <CommandCardHeader title="Trial funnel" description={String(funnel?.note ?? '')} />
          <CommandCardBody className="space-y-2 text-sm">
            <FunnelRow label="Trialing now" value={trialing} />
            <FunnelRow label="Reached day 3" value={Number(funnel?.trial_day_3_reached ?? 0)} />
            <FunnelRow label="Reached day 7" value={Number(funnel?.trial_day_7_reached ?? 0)} />
            <FunnelRow label="Converted to active" value={activatedActive} />
            <FunnelRow label="Paid at least once" value={Number(funnel?.paid_from_trial ?? 0)} />
          </CommandCardBody>
        </CommandCard>

        <CommandCard className="xl:col-span-1">
          <CommandCardHeader title="SMS credit usage" description="Not sold separately — bundled into plan pricing" />
          <CommandCardBody className="space-y-2 text-sm">
            <FunnelRow label="Sent today, platform-wide" value={Number(cmd?.sms_sent_today ?? 0)} />
            <FunnelRow label="Sent yesterday" value={Number(cmd?.sms_sent_yesterday ?? 0)} />
            <p className="mt-2 text-xs text-zinc-500">
              SMS credit revenue is not tracked as a separate line item — allowances are part of each subscription plan.
            </p>
          </CommandCardBody>
        </CommandCard>
      </div>

      <section>
        <SectionHeader eyebrow="Billing events" title="Recent payments" />
        <CommandCard>
          {paymentsLoading ? (
            <p className="p-4 text-sm text-zinc-500">Loading…</p>
          ) : paymentRows.length === 0 ? (
            <CommandEmptyState label="No billing payments recorded yet." />
          ) : (
            <CommandTable>
              <CommandTableHead>
                <CommandTh>Company</CommandTh>
                <CommandTh>Amount</CommandTh>
                <CommandTh>Method</CommandTh>
                <CommandTh>Reference</CommandTh>
                <CommandTh className="text-right">Paid</CommandTh>
              </CommandTableHead>
              <tbody>
                {paymentRows.map((p) => (
                  <CommandTr key={p.id}>
                    <CommandTd>{p.company_name}</CommandTd>
                    <CommandTd className="font-medium tabular-nums text-zinc-100">{formatLrd(p.amount_cents)}</CommandTd>
                    <CommandTd className="capitalize text-zinc-400">{p.payment_method.replace(/_/g, ' ')}</CommandTd>
                    <CommandTd className="font-mono text-xs text-zinc-500">{p.reference ?? '—'}</CommandTd>
                    <CommandTd className="text-right text-xs text-zinc-500">
                      {new Date(p.paid_at).toLocaleString()}
                    </CommandTd>
                  </CommandTr>
                ))}
              </tbody>
            </CommandTable>
          )}
        </CommandCard>
      </section>

      <p className="flex items-center gap-1.5 text-xs text-zinc-600">
        <ReceiptText className="h-3.5 w-3.5" />
        Revenue figures reflect recorded payments and active plan pricing only — no projected or historical revenue is
        estimated beyond what's captured here.
      </p>
    </div>
  )
}

function FunnelRow({ label, value }: { label: string; value: number }) {
  return (
    <div className="flex items-center justify-between">
      <span className="text-zinc-400">{label}</span>
      <span className="font-medium tabular-nums text-zinc-100">{value}</span>
    </div>
  )
}
