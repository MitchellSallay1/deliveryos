import { useEffect, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { useAuth } from '@/hooks/use-auth'
import { parseSupabaseError } from '@/lib/supabase-errors'
import { fetchProviderMarketplaceProfile, upsertProviderMarketplaceProfile } from '@/services/marketplace-service'

export function MarketplaceSettingsPage() {
  const { context } = useAuth()
  const companyId = context?.activeCompanyId
  const qc = useQueryClient()

  const { data: profile, isLoading } = useQuery({
    queryKey: ['provider-marketplace-profile', companyId],
    queryFn: () => fetchProviderMarketplaceProfile(companyId!),
    enabled: !!companyId,
  })

  const [marketplaceEnabled, setMarketplaceEnabled] = useState(false)
  const [acceptingJobs, setAcceptingJobs] = useState(false)
  // Kept as a string, not a number, so the field starts genuinely empty
  // rather than silently defaulting to "0" — an owner must type a value
  // before they can save, so a fee is never set by accident.
  const [minimumFeeLrd, setMinimumFeeLrd] = useState('')
  const [serviceDescription, setServiceDescription] = useState('')
  const [servicePhone, setServicePhone] = useState('')
  const [serviceEmail, setServiceEmail] = useState('')
  const [message, setMessage] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!profile) return
    setMarketplaceEnabled(profile.marketplace_enabled)
    setAcceptingJobs(profile.accepting_jobs)
    setMinimumFeeLrd((profile.minimum_delivery_fee_lrd_cents / 100).toString())
    setServiceDescription(profile.service_description ?? '')
    setServicePhone(profile.service_phone ?? '')
    setServiceEmail(profile.service_email ?? '')
  }, [profile])

  const save = useMutation({
    mutationFn: (payload: Record<string, unknown>) => upsertProviderMarketplaceProfile(payload),
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['provider-marketplace-profile', companyId] }),
  })

  const feeValue = Number(minimumFeeLrd)
  const feeIsValid = minimumFeeLrd.trim() !== '' && Number.isFinite(feeValue) && feeValue >= 0
  const feeIsZero = feeIsValid && feeValue === 0

  async function onSave() {
    setError(null)
    setMessage(null)
    if (!companyId) return
    if (!feeIsValid) {
      setError('Enter your minimum delivery fee (0 or more) before saving.')
      return
    }
    try {
      await save.mutateAsync({
        company_id: companyId,
        marketplace_enabled: marketplaceEnabled,
        accepting_jobs: acceptingJobs,
        minimum_delivery_fee_lrd_cents: Math.round(feeValue * 100),
        service_description: serviceDescription.trim() || undefined,
        service_phone: servicePhone.trim() || undefined,
        service_email: serviceEmail.trim() || undefined,
      })
      setMessage('Marketplace settings saved.')
    } catch (err) {
      setError(parseSupabaseError(err))
    }
  }

  return (
    <div className="mx-auto max-w-2xl space-y-6 animate-fade-in">
      <div>
        <h2 className="text-xl font-semibold">Marketplace settings</h2>
        <p className="text-sm text-[var(--color-muted)]">
          Control whether your company appears in the delivery marketplace, and what you charge to accept a job.
        </p>
      </div>

      {profile?.admin_marketplace_disabled && (
        <p className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">
          A DeliveryOS administrator has disabled marketplace access for your company. Contact support for details.
        </p>
      )}

      <Card>
        <CardHeader>
          <CardTitle>Availability</CardTitle>
          <CardDescription>
            You only receive jobs — including from Commerce vendors&apos; storefronts — when both are on.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={marketplaceEnabled} onChange={(e) => setMarketplaceEnabled(e.target.checked)} />
            List my company on the delivery marketplace
          </label>
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={acceptingJobs} onChange={(e) => setAcceptingJobs(e.target.checked)} />
            Currently accepting new jobs
          </label>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Pricing</CardTitle>
          <CardDescription>
            Your minimum delivery fee is quoted automatically on every matching job — including to Commerce customers
            comparing carriers at checkout.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-2">
          <Label htmlFor="min-fee">Minimum delivery fee (LRD)</Label>
          <Input
            id="min-fee"
            type="number"
            min="0"
            step="1"
            inputMode="decimal"
            placeholder="e.g. 250"
            value={minimumFeeLrd}
            onChange={(e) => setMinimumFeeLrd(e.target.value)}
            required
          />
          {feeIsZero && (
            <p className="text-sm text-amber-700">
              A minimum fee of 0 means you are offering free delivery on every job you&apos;re matched to. Only save
              this if that&apos;s intentional.
            </p>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Contact &amp; description</CardTitle>
          <CardDescription>Shown to merchants browsing the provider directory.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="service-description">Description</Label>
            <textarea
              id="service-description"
              className="flex min-h-16 w-full rounded-lg border bg-white px-3 py-2 text-sm"
              value={serviceDescription}
              onChange={(e) => setServiceDescription(e.target.value)}
            />
          </div>
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="space-y-2">
              <Label htmlFor="service-phone">Service phone</Label>
              <Input id="service-phone" value={servicePhone} onChange={(e) => setServicePhone(e.target.value)} />
            </div>
            <div className="space-y-2">
              <Label htmlFor="service-email">Service email</Label>
              <Input id="service-email" type="email" value={serviceEmail} onChange={(e) => setServiceEmail(e.target.value)} />
            </div>
          </div>
        </CardContent>
      </Card>

      {error && <p className="text-sm text-red-600">{error}</p>}
      {message && <p className="text-sm text-teal-700">{message}</p>}

      <Button type="button" disabled={save.isPending || !companyId} onClick={() => void onSave()}>
        {save.isPending ? 'Saving…' : 'Save marketplace settings'}
      </Button>
    </div>
  )
}
