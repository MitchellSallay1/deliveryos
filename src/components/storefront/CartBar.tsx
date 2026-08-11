import { Minus, Plus, ShoppingBag, Trash2 } from 'lucide-react'
import { Sheet } from '@/components/ui/Sheet'
import { Button } from '@/components/ui/Button'
import { formatLrdFromCents } from '@/utils/delivery-schemas'
import type { LocalCartItem } from '@/hooks/use-local-cart'
import type { PublicStoreCatalog } from '@/services/storefront-service'

function resolveLine(catalog: PublicStoreCatalog, item: LocalCartItem) {
  const product = catalog.products.find((p) => p.id === item.productId)
  if (!product) return null
  const options = product.option_groups
    .flatMap((g) => g.options)
    .filter((o) => item.selectedOptionIds.includes(o.id))
  const unitPrice = product.price_lrd_cents + options.reduce((sum, o) => sum + o.price_delta_lrd_cents, 0)
  return { product, options, unitPrice, lineTotal: unitPrice * item.quantity }
}

export function cartSubtotal(catalog: PublicStoreCatalog | undefined, items: LocalCartItem[]): number {
  if (!catalog) return 0
  return items.reduce((sum, item) => sum + (resolveLine(catalog, item)?.lineTotal ?? 0), 0)
}

export function CartFab({ itemCount, subtotal, onOpen }: { itemCount: number; subtotal: number; onOpen: () => void }) {
  if (itemCount === 0) return null
  return (
    <button
      type="button"
      onClick={onOpen}
      className="fixed inset-x-4 bottom-4 z-40 flex items-center justify-between rounded-full bg-[var(--color-primary)] px-5 py-3 text-[var(--color-primary-foreground)] shadow-lg sm:inset-x-auto sm:right-4 sm:w-80"
    >
      <span className="flex items-center gap-2 text-sm font-medium">
        <ShoppingBag className="h-4 w-4" />
        {itemCount} item{itemCount === 1 ? '' : 's'}
      </span>
      <span className="text-sm font-semibold tabular-nums">{formatLrdFromCents(subtotal)}</span>
    </button>
  )
}

export function CartDrawer({
  open,
  onClose,
  catalog,
  items,
  onUpdateQuantity,
  onRemove,
  onCheckout,
}: {
  open: boolean
  onClose: () => void
  catalog: PublicStoreCatalog
  items: LocalCartItem[]
  onUpdateQuantity: (key: string, quantity: number) => void
  onRemove: (key: string) => void
  onCheckout: () => void
}) {
  const subtotal = cartSubtotal(catalog, items)

  return (
    <Sheet open={open} onClose={onClose} title="Your cart" description={catalog.store.display_name}>
      <div className="space-y-4">
        {items.length === 0 && <p className="text-sm text-[var(--color-muted)]">Your cart is empty.</p>}
        <ul className="space-y-3">
          {items.map((item) => {
            const line = resolveLine(catalog, item)
            if (!line) return null
            return (
              <li key={item.key} className="flex items-start justify-between gap-3 border-b pb-3">
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-medium">{line.product.name}</p>
                  {line.options.length > 0 && (
                    <p className="text-xs text-[var(--color-muted)]">{line.options.map((o) => o.name).join(', ')}</p>
                  )}
                  <div className="mt-2 flex items-center gap-2">
                    <Button
                      type="button"
                      size="sm"
                      variant="outline"
                      className="h-7 w-7 p-0"
                      onClick={() => onUpdateQuantity(item.key, item.quantity - 1)}
                      aria-label="Decrease quantity"
                    >
                      <Minus className="h-3 w-3" />
                    </Button>
                    <span className="w-5 text-center text-sm tabular-nums">{item.quantity}</span>
                    <Button
                      type="button"
                      size="sm"
                      variant="outline"
                      className="h-7 w-7 p-0"
                      onClick={() => onUpdateQuantity(item.key, item.quantity + 1)}
                      aria-label="Increase quantity"
                    >
                      <Plus className="h-3 w-3" />
                    </Button>
                    <Button
                      type="button"
                      size="sm"
                      variant="ghost"
                      className="ml-1 h-7 w-7 p-0 text-red-600"
                      onClick={() => onRemove(item.key)}
                      aria-label="Remove item"
                    >
                      <Trash2 className="h-3.5 w-3.5" />
                    </Button>
                  </div>
                </div>
                <span className="whitespace-nowrap text-sm font-medium tabular-nums">{formatLrdFromCents(line.lineTotal)}</span>
              </li>
            )
          })}
        </ul>

        {items.length > 0 && (
          <>
            <div className="flex justify-between border-t pt-3 text-sm font-semibold">
              <span>Subtotal</span>
              <span className="tabular-nums">{formatLrdFromCents(subtotal)}</span>
            </div>
            <p className="text-xs text-[var(--color-muted)]">
              Delivery fee is not yet included — it will be confirmed once your order is assigned for delivery.
            </p>
            <Button type="button" className="w-full" onClick={onCheckout}>
              Checkout
            </Button>
          </>
        )}
      </div>
    </Sheet>
  )
}
