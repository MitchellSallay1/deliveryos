import { useState } from 'react'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { useAuth } from '@/hooks/use-auth'
import { setActiveCompanyId } from '@/hooks/use-auth-context'
import {
  useCompanyPayments,
  useCompanySettings,
  useMarkPaymentDeposited,
  useUpdateCompanySettings,
  useUpdateProfile,
} from '@/hooks/use-settings'
import { BillingSettingsSection } from '@/components/BillingSettingsSection'
import { RiderChannelSettingsSection } from '@/components/RiderChannelSettingsSection'
import { DeliveryZonesSection } from '@/components/DeliveryZonesSection'
import { IntegrationsSettingsSection } from '@/components/IntegrationsSettingsSection'
import { MarketplaceProviderSettings } from '@/components/MarketplaceProviderSettings'
import { formatLrdFromCents } from '@/utils/delivery-schemas'

export function SettingsPage() {
  const { context, user, refreshContext } = useAuth()
  const companyId = context?.activeCompanyId ?? null
  const isOwner = context?.activeRole === 'company_owner'
  const businessType = context?.memberships.find((m) => m.company_id === companyId)?.company
    .business_type

  const { data: settings, isLoading } = useCompanySettings(companyId)
  const { data: payments = [] } = useCompanyPayments(companyId)
  const updateCompany = useUpdateCompanySettings(companyId)
  const updateProfile = useUpdateProfile()
  const depositMutation = useMarkPaymentDeposited(companyId)

  const [message, setMessage] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  if (!companyId) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Settings</CardTitle>
          <CardDescription>Join or register a company to manage settings.</CardDescription>
        </CardHeader>
      </Card>
    )
  }

  async function onProfile(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    setError(null)
    setMessage(null)
    const fd = new FormData(e.currentTarget)
    try {
      await updateProfile.mutateAsync({
        full_name: String(fd.get('fullName') || ''),
        phone: String(fd.get('phone') || '') || null,
      })
      refreshContext()
      setMessage('Profile saved.')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Save failed')
    }
  }

  async function onCompany(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    setError(null)
    setMessage(null)
    if (!isOwner) return
    const fd = new FormData(e.currentTarget)
    try {
      await updateCompany.mutateAsync({
        name: String(fd.get('name') || ''),
        phone: String(fd.get('phone') || ''),
        email: String(fd.get('email') || ''),
        address: String(fd.get('address') || '') || null,
      })
      refreshContext()
      setMessage('Company profile saved.')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Save failed')
    }
  }

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      {error && <p className="text-sm text-red-600">{error}</p>}
      {message && <p className="text-sm text-teal-700">{message}</p>}

      {context && context.memberships.length > 1 && (
        <Card>
          <CardHeader>
            <CardTitle>Workspace</CardTitle>
            <CardDescription>Switch active company</CardDescription>
          </CardHeader>
          <CardContent>
            <select
              className="h-10 w-full rounded-md border px-3 text-sm"
              value={companyId}
              onChange={(e) => {
                setActiveCompanyId(e.target.value)
                refreshContext()
              }}
            >
              {context.memberships.map((m) => (
                <option key={m.company_id} value={m.company_id}>
                  {m.company.name} ({m.role})
                </option>
              ))}
            </select>
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader>
          <CardTitle>Your profile</CardTitle>
        </CardHeader>
        <CardContent>
          <form className="space-y-4" onSubmit={onProfile}>
            <div className="space-y-2">
              <Label htmlFor="fullName">Full name</Label>
              <Input
                id="fullName"
                name="fullName"
                defaultValue={context?.profile?.full_name ?? ''}
                required
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="profilePhone">Phone (for rider account linking)</Label>
              <Input
                id="profilePhone"
                name="phone"
                defaultValue={context?.profile?.phone ?? ''}
                placeholder="+231..."
              />
            </div>
            <p className="text-xs text-[var(--color-muted)]">{user?.email}</p>
            <Button type="submit" disabled={updateProfile.isPending}>
              Save profile
            </Button>
          </form>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Company & plan</CardTitle>
          {isLoading && <CardDescription>Loading…</CardDescription>}
          {settings && (
            <CardDescription>
              {settings.subscription.name} · {formatLrdFromCents(settings.subscription.price_lrd_cents)}
              /mo · {settings.sms_credits} SMS credits
            </CardDescription>
          )}
        </CardHeader>
        <CardContent>
          {settings && (
            <dl className="mb-4 grid gap-2 text-sm sm:grid-cols-2">
              <div>
                <dt className="text-[var(--color-muted)]">Rider limit</dt>
                <dd>{settings.subscription.max_riders}</dd>
              </div>
              <div>
                <dt className="text-[var(--color-muted)]">Deliveries / month</dt>
                <dd>
                  {settings.subscription.max_deliveries_per_month ?? 'Unlimited'}
                </dd>
              </div>
              <div>
                <dt className="text-[var(--color-muted)]">Status</dt>
                <dd className="capitalize">{settings.status}</dd>
              </div>
            </dl>
          )}
          {isOwner ? (
            <form className="space-y-4" onSubmit={onCompany}>
              <div className="space-y-2">
                <Label htmlFor="name">Company name</Label>
                <Input id="name" name="name" defaultValue={settings?.name ?? ''} required />
              </div>
              <div className="grid gap-4 sm:grid-cols-2">
                <div className="space-y-2">
                  <Label htmlFor="companyPhone">Phone</Label>
                  <Input id="companyPhone" name="phone" defaultValue={settings?.phone ?? ''} required />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="companyEmail">Email</Label>
                  <Input id="companyEmail" name="email" type="email" defaultValue={settings?.email ?? ''} required />
                </div>
              </div>
              <div className="space-y-2">
                <Label htmlFor="address">Address</Label>
                <Input id="address" name="address" defaultValue={settings?.address ?? ''} />
              </div>
              <Button type="submit" disabled={updateCompany.isPending}>
                Save company
              </Button>
            </form>
          ) : (
            <p className="text-sm text-[var(--color-muted)]">
              Only the company owner can edit company details.
            </p>
          )}
        </CardContent>
      </Card>

      {isOwner && <BillingSettingsSection companyId={companyId} />}
      {isOwner && settings && (
        <RiderChannelSettingsSection
          companyId={companyId}
          settings={{
            allow_smartphone_riders: settings.allow_smartphone_riders,
            allow_button_phone_riders: settings.allow_button_phone_riders,
            enable_rider_sms: settings.enable_rider_sms,
            enable_rider_ussd: settings.enable_rider_ussd,
            require_otp_button_phone_delivery: settings.require_otp_button_phone_delivery,
          }}
        />
      )}
      {isOwner && <DeliveryZonesSection companyId={companyId} />}
      {isOwner && <IntegrationsSettingsSection companyId={companyId} />}
      {isOwner &&
        (businessType === 'logistics_provider' || businessType === 'hybrid') && (
          <MarketplaceProviderSettings companyId={companyId} />
        )}

      <Card>
        <CardHeader>
          <CardTitle>COD payments</CardTitle>
          <CardDescription>Created when a delivery is marked delivered</CardDescription>
        </CardHeader>
        <CardContent className="overflow-x-auto">
          <table className="w-full min-w-[520px] text-left text-sm">
            <thead>
              <tr className="border-b text-xs uppercase text-[var(--color-muted)]">
                <th className="py-2">Delivery</th>
                <th className="py-2">Amount</th>
                <th className="py-2">Status</th>
                <th className="py-2">Action</th>
              </tr>
            </thead>
            <tbody>
              {payments.map((p) => {
                const d = Array.isArray(p.deliveries) ? p.deliveries[0] : p.deliveries
                return (
                  <tr key={p.id} className="border-b">
                    <td className="py-2">
                      <div>{d?.customer_name ?? '—'}</div>
                      <div className="text-xs text-[var(--color-muted)]">{d?.tracking_code}</div>
                    </td>
                    <td className="py-2">{formatLrdFromCents(p.amount_lrd_cents)}</td>
                    <td className="py-2 capitalize">{p.status}</td>
                    <td className="py-2">
                      {p.status === 'collected' && isOwner && (
                        <Button
                          type="button"
                          size="sm"
                          variant="outline"
                          disabled={depositMutation.isPending}
                          onClick={() => depositMutation.mutate(p.id)}
                        >
                          Mark deposited
                        </Button>
                      )}
                    </td>
                  </tr>
                )
              })}
              {payments.length === 0 && (
                <tr>
                  <td colSpan={4} className="py-4 text-center text-[var(--color-muted)]">
                    No payments yet.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </CardContent>
      </Card>
    </div>
  )
}
