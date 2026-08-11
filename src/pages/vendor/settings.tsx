import { useEffect, useState } from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { PageHeader } from '@/components/ui/PageHeader'
import { VendorGuard } from '@/components/vendor/VendorGuard'
import { useVendorContext } from '@/hooks/use-vendor-context'
import { useStoreProfile, useVendorStoreActions } from '@/hooks/use-vendor-commerce'
import { vendorStateLabel, vendorStateVariant } from '@/lib/vendor-commerce-ui'
import { parseSupabaseError } from '@/lib/supabase-errors'

function VendorSettingsContent() {
  const { companyId } = useVendorContext()
  const { data: store, isLoading } = useStoreProfile(companyId)
  const { save, submitForReview } = useVendorStoreActions(companyId)

  const [form, setForm] = useState({
    slug: '',
    display_name: '',
    description: '',
    logo_url: '',
    banner_url: '',
    allow_cash_on_delivery: false,
  })
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)

  useEffect(() => {
    if (!store) return
    setForm({
      slug: store.slug,
      display_name: store.display_name,
      description: store.description ?? '',
      logo_url: store.logo_url ?? '',
      banner_url: store.banner_url ?? '',
      allow_cash_on_delivery: store.allow_cash_on_delivery,
    })
  }, [store])

  async function saveStoreDetails() {
    setError(null)
    setMessage(null)
    if (!companyId) return
    try {
      await save.mutateAsync({
        company_id: companyId,
        slug: form.slug.trim(),
        display_name: form.display_name.trim(),
        description: form.description.trim() || undefined,
        logo_url: form.logo_url.trim() || undefined,
        banner_url: form.banner_url.trim() || undefined,
        allow_cash_on_delivery: form.allow_cash_on_delivery,
      })
      setMessage('Store details saved.')
    } catch (err) {
      setError(parseSupabaseError(err))
    }
  }

  async function onSubmitForReview() {
    setError(null)
    setMessage(null)
    try {
      await submitForReview.mutateAsync()
      setMessage('Submitted for review. A DeliveryOS admin will approve or reject your store.')
    } catch (err) {
      setError(parseSupabaseError(err))
    }
  }

  const canSubmitForReview = store && (store.status === 'draft' || store.status === 'rejected')

  return (
    <div className="mx-auto max-w-2xl space-y-6 animate-fade-in">
      <PageHeader title="Store setup" description="Configure how your storefront appears once published." />

      {store && (
        <Card className="border-dashed">
          <CardContent className="flex flex-wrap items-center justify-between gap-3 pt-6">
            <div>
              <p className="text-sm text-[var(--color-muted)]">Publication status</p>
              <Badge variant={vendorStateVariant(store.status)} className="mt-1">
                {vendorStateLabel(store.status)}
              </Badge>
              {store.status === 'pending_review' && (
                <p className="mt-2 text-sm text-[var(--color-muted)]">
                  Awaiting review by DeliveryOS. You cannot approve your own store.
                </p>
              )}
              {store.status === 'suspended' && (
                <p className="mt-2 text-sm text-red-600">
                  Your storefront is suspended and cannot accept new orders. Contact DeliveryOS support.
                </p>
              )}
              {store.status === 'rejected' && store.status_reason && (
                <p className="mt-2 text-sm text-red-600">Reason: {store.status_reason}</p>
              )}
            </div>
            {canSubmitForReview && (
              <Button type="button" size="sm" onClick={onSubmitForReview} disabled={submitForReview.isPending}>
                {submitForReview.isPending ? 'Submitting…' : 'Submit for review'}
              </Button>
            )}
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader>
          <CardTitle>Store details</CardTitle>
          <CardDescription>Only DeliveryOS can approve, suspend, or reject a store — these fields never change your publication status.</CardDescription>
        </CardHeader>
        <CardContent>
          {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
          {error && <p className="mb-3 text-sm text-red-600">{error}</p>}
          {message && <p className="mb-3 text-sm text-teal-700">{message}</p>}
          <form
            className="space-y-4"
            onSubmit={(e) => {
              e.preventDefault()
              void saveStoreDetails()
            }}
          >
            <div className="space-y-2">
              <Label htmlFor="display_name">Store display name</Label>
              <Input
                id="display_name"
                value={form.display_name}
                onChange={(e) => setForm({ ...form, display_name: e.target.value })}
                required
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="slug">Storefront URL slug</Label>
              <Input
                id="slug"
                value={form.slug}
                onChange={(e) => setForm({ ...form, slug: e.target.value.toLowerCase() })}
                pattern="[a-z0-9]+(-[a-z0-9]+)*"
                required
              />
              <p className="text-xs text-[var(--color-muted)]">deliveryos.app/store/{form.slug || 'your-slug'}</p>
            </div>
            <div className="space-y-2">
              <Label htmlFor="description">Description</Label>
              <textarea
                id="description"
                className="flex min-h-20 w-full rounded-lg border bg-white px-3 py-2 text-sm"
                value={form.description}
                onChange={(e) => setForm({ ...form, description: e.target.value })}
              />
            </div>
            <div className="grid gap-4 sm:grid-cols-2">
              <div className="space-y-2">
                <Label htmlFor="logo_url">Logo URL</Label>
                <Input id="logo_url" value={form.logo_url} onChange={(e) => setForm({ ...form, logo_url: e.target.value })} />
              </div>
              <div className="space-y-2">
                <Label htmlFor="banner_url">Banner URL</Label>
                <Input id="banner_url" value={form.banner_url} onChange={(e) => setForm({ ...form, banner_url: e.target.value })} />
              </div>
            </div>
            <Button type="submit" disabled={save.isPending}>
              {save.isPending ? 'Saving…' : 'Save store details'}
            </Button>
          </form>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Payment methods</CardTitle>
          <CardDescription>
            Cash on Delivery is the only payment method available today. Mobile money (MTN MoMo, Orange Money) is
            planned but not yet enabled.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <label className="flex items-start gap-3 text-sm">
            <input
              type="checkbox"
              className="mt-1"
              checked={form.allow_cash_on_delivery}
              onChange={(e) => setForm({ ...form, allow_cash_on_delivery: e.target.checked })}
            />
            <span>
              <span className="font-medium">Accept Cash on Delivery</span>
              <br />
              <span className="text-[var(--color-muted)]">
                When enabled, customers can place orders and pay in cash when their order is delivered. When
                disabled, customers cannot check out against your store until an online payment method is available.
              </span>
            </span>
          </label>
          <Button type="button" className="mt-4" disabled={save.isPending} onClick={() => void saveStoreDetails()}>
            {save.isPending ? 'Saving…' : 'Save payment settings'}
          </Button>
        </CardContent>
      </Card>
    </div>
  )
}

export function VendorSettingsPage() {
  return (
    <VendorGuard>
      <VendorSettingsContent />
    </VendorGuard>
  )
}
