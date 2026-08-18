import { useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { PhoneOtpFlow } from '@/components/PhoneOtpFlow'
import { useAuth } from '@/hooks/use-auth'
import { useLocalCart } from '@/hooks/use-local-cart'
import { usePublicStoreCatalog } from '@/hooks/use-storefront'
import { parseSupabaseError } from '@/lib/supabase-errors'
import {
  addCartItem,
  fetchCartSummary,
  getOrCreateCart,
  submitCommerceOrder,
  type CartSummary,
} from '@/services/customer-commerce-service'
import { formatLrdFromCents } from '@/utils/delivery-schemas'

type SyncState = { status: 'idle' | 'syncing' | 'ready' | 'error'; summary: CartSummary | null; error: string | null }

export function StoreCheckoutPage() {
  const { slug } = useParams()
  const navigate = useNavigate()
  const { user, loading: authLoading } = useAuth()
  const { data: catalog, isLoading: catalogLoading } = usePublicStoreCatalog(slug)
  const localCart = useLocalCart(slug ?? '')

  const [sync, setSync] = useState<SyncState>({ status: 'idle', summary: null, error: null })
  const [customerName, setCustomerName] = useState('')
  const [address, setAddress] = useState('')
  const [areaSummary, setAreaSummary] = useState('')
  const [instructions, setInstructions] = useState('')
  const [coords, setCoords] = useState<{ lat: number; lng: number } | null>(null)
  const [locating, setLocating] = useState(false)
  const [submitError, setSubmitError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)
  const [paymentMethod, setPaymentMethod] = useState<'cod' | 'mtn_momo'>('cod')

  useEffect(() => {
    if (!user || !catalog || sync.status !== 'idle') return

    let cancelled = false
    setSync({ status: 'syncing', summary: null, error: null })
    ;(async () => {
      try {
        const cart = await getOrCreateCart(catalog.store.company_id)
        let summary = await fetchCartSummary(cart.id)

        if (summary.items.length === 0 && localCart.items.length > 0) {
          for (const item of localCart.items) {
            await addCartItem(cart.id, item.productId, item.quantity, item.selectedOptionIds)
          }
          summary = await fetchCartSummary(cart.id)
        }

        if (!cancelled) setSync({ status: 'ready', summary, error: null })
      } catch (err) {
        if (!cancelled) setSync({ status: 'error', summary: null, error: parseSupabaseError(err) })
      }
    })()

    return () => {
      cancelled = true
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user, catalog, sync.status])

  useEffect(() => {
    if (catalog && !catalog.store.allow_cash_on_delivery) {
      setPaymentMethod('mtn_momo')
    }
  }, [catalog])

  function useMyLocation() {
    if (!navigator.geolocation) return
    setLocating(true)
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setCoords({ lat: pos.coords.latitude, lng: pos.coords.longitude })
        setLocating(false)
      },
      () => setLocating(false),
      { enableHighAccuracy: true, timeout: 8000 },
    )
  }

  async function placeOrder() {
    if (!sync.summary) return
    setSubmitError(null)
    if (!customerName.trim()) {
      setSubmitError('Enter your name.')
      return
    }
    setSubmitting(true)
    try {
      const order = await submitCommerceOrder({
        cartId: sync.summary.cart_id,
        customerName: customerName.trim(),
        deliveryAddress: address.trim() || undefined,
        deliveryAreaSummary: areaSummary.trim() || undefined,
        deliveryLatitude: coords?.lat,
        deliveryLongitude: coords?.lng,
        deliveryInstructions: instructions.trim() || undefined,
        paymentMethod,
      })
      localCart.clear()
      // MTN MoMo no longer charges here: the final payable amount (goods +
      // delivery fee) isn't known until a carrier is selected. The order
      // page prompts for payment once that happens — see MtnPaymentStatusPanel.
      navigate(`/orders/${order.id}`)
    } catch (err) {
      setSubmitError(parseSupabaseError(err))
    } finally {
      setSubmitting(false)
    }
  }

  if (authLoading || catalogLoading) {
    return <div className="flex min-h-screen items-center justify-center text-sm text-[var(--color-muted)]">Loading…</div>
  }

  if (!catalog) {
    return (
      <div className="flex min-h-screen items-center justify-center p-6 text-center text-sm text-[var(--color-muted)]">
        Store not found.
      </div>
    )
  }

  if (localCart.items.length === 0 && sync.status !== 'ready') {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center gap-3 p-6 text-center">
        <p className="text-sm text-[var(--color-muted)]">Your cart is empty.</p>
        <Button type="button" onClick={() => navigate(`/store/${slug}`)}>
          Back to {catalog.store.display_name}
        </Button>
      </div>
    )
  }

  return (
    <div className="mx-auto min-h-screen max-w-lg space-y-5 p-4 pb-10">
      <div>
        <button type="button" className="text-sm text-[var(--color-muted)] hover:underline" onClick={() => navigate(`/store/${slug}`)}>
          ← Back to {catalog.store.display_name}
        </button>
        <h1 className="mt-1 text-xl font-semibold">Checkout</h1>
      </div>

      {!user && (
        <Card>
          <CardContent className="pt-6">
            <PhoneOtpFlow
              title="Verify your phone"
              description="We'll text you a one-time code to confirm your order — no password or account needed."
              submitLabel="Send verification code"
              onVerified={() => {
                /* useAuth updates via onAuthStateChange; the sync effect picks it up */
              }}
            />
          </CardContent>
        </Card>
      )}

      {user && sync.status === 'syncing' && (
        <p className="text-sm text-[var(--color-muted)]">Preparing your order…</p>
      )}

      {user && sync.status === 'error' && <p className="text-sm text-red-600">{sync.error}</p>}

      {user && sync.status === 'ready' && sync.summary && (
        <>
          <Card>
            <CardHeader>
              <CardTitle>Order summary</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2">
              {sync.summary.items.map((item) => (
                <div key={item.cart_item_id} className="flex justify-between text-sm">
                  <span>
                    {item.quantity}× {item.product_name}
                    {item.selected_options.length > 0 && (
                      <span className="text-xs text-[var(--color-muted)]"> ({item.selected_options.map((o) => o.name).join(', ')})</span>
                    )}
                  </span>
                  <span className="tabular-nums">{formatLrdFromCents(item.line_total_lrd_cents)}</span>
                </div>
              ))}
              <div className="flex justify-between border-t pt-2 text-sm font-semibold">
                <span>Subtotal</span>
                <span className="tabular-nums">{formatLrdFromCents(sync.summary.subtotal_lrd_cents)}</span>
              </div>
              <p className="text-xs text-[var(--color-muted)]">
                Final total is confirmed by the store when your order is submitted. Delivery fee is not yet included.
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Delivery details</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="customer-name">Your name</Label>
                <Input id="customer-name" value={customerName} onChange={(e) => setCustomerName(e.target.value)} required />
              </div>
              <div className="space-y-2">
                <Label htmlFor="area-summary">Area / landmark</Label>
                <Input
                  id="area-summary"
                  placeholder="e.g. Sinkor, near ELWA junction"
                  value={areaSummary}
                  onChange={(e) => setAreaSummary(e.target.value)}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="address">Directions to you</Label>
                <textarea
                  id="address"
                  className="flex min-h-16 w-full rounded-lg border bg-white px-3 py-2 text-sm"
                  placeholder="Describe how to find you — a street address isn't required."
                  value={address}
                  onChange={(e) => setAddress(e.target.value)}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="instructions">Delivery instructions (optional)</Label>
                <Input id="instructions" value={instructions} onChange={(e) => setInstructions(e.target.value)} />
              </div>
              <Button type="button" variant="outline" size="sm" onClick={useMyLocation} disabled={locating}>
                {locating ? 'Getting location…' : coords ? 'Location added ✓' : 'Share my GPS location (optional)'}
              </Button>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Payment</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              {catalog.store.allow_cash_on_delivery && (
                <label
                  className={`flex items-center gap-2 rounded-lg border px-3 py-2 text-sm ${
                    paymentMethod === 'cod'
                      ? 'border-[var(--color-primary)] bg-[color-mix(in_oklab,var(--color-primary)_8%,white)]'
                      : ''
                  }`}
                >
                  <input type="radio" checked={paymentMethod === 'cod'} onChange={() => setPaymentMethod('cod')} />
                  Cash on Delivery — pay when your order arrives
                </label>
              )}
              <label
                className={`flex items-center gap-2 rounded-lg border px-3 py-2 text-sm ${
                  paymentMethod === 'mtn_momo'
                    ? 'border-[var(--color-primary)] bg-[color-mix(in_oklab,var(--color-primary)_8%,white)]'
                    : ''
                }`}
              >
                <input type="radio" checked={paymentMethod === 'mtn_momo'} onChange={() => setPaymentMethod('mtn_momo')} />
                MTN MoMo
              </label>
              {paymentMethod === 'mtn_momo' && (
                <p className="pl-1 text-xs text-[var(--color-muted)]">
                  You&apos;ll be asked to pay by MTN MoMo once a carrier is assigned to your delivery, for the full
                  order total (goods + delivery fee) — not before.
                </p>
              )}
              {!catalog.store.allow_cash_on_delivery && paymentMethod === 'cod' && (
                <p className="rounded-md bg-amber-50 px-3 py-2 text-sm text-amber-800">
                  This store isn&apos;t accepting Cash on Delivery orders right now.
                </p>
              )}
              <div className="flex items-center gap-2 rounded-lg border px-3 py-2 text-sm text-[var(--color-muted)] opacity-60">
                <input type="radio" disabled />
                Orange Money — coming soon
              </div>
            </CardContent>
          </Card>

          {submitError && <p className="text-sm text-red-600">{submitError}</p>}

          <Button
            type="button"
            className="w-full"
            disabled={submitting || (paymentMethod === 'cod' && !catalog.store.allow_cash_on_delivery)}
            onClick={() => void placeOrder()}
          >
            {submitting ? 'Placing order…' : paymentMethod === 'mtn_momo' ? 'Place order' : 'Place order — Cash on Delivery'}
          </Button>
        </>
      )}
    </div>
  )
}
