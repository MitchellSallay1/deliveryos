import { useMemo, useState } from 'react'
import { Minus, Plus } from 'lucide-react'
import { Sheet } from '@/components/ui/Sheet'
import { Button } from '@/components/ui/Button'
import { productImagePublicUrl } from '@/services/storefront-service'
import { formatLrdFromCents } from '@/utils/delivery-schemas'
import type { PublicStoreProduct } from '@/services/storefront-service'

export function ProductDetailModal({
  product,
  onClose,
  onAdd,
}: {
  product: PublicStoreProduct | null
  onClose: () => void
  onAdd: (productId: string, quantity: number, selectedOptionIds: string[]) => void
}) {
  const [selected, setSelected] = useState<Record<string, string[]>>({})
  const [quantity, setQuantity] = useState(1)

  const currentProductId = product?.id ?? null
  useMemo(() => {
    // Reset local selection state whenever a different product is opened.
    if (currentProductId) {
      setSelected({})
      setQuantity(1)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentProductId])

  if (!product) return null

  const selectedIds = Object.values(selected).flat()
  const optionDelta = product.option_groups
    .flatMap((g) => g.options)
    .filter((o) => selectedIds.includes(o.id))
    .reduce((sum, o) => sum + o.price_delta_lrd_cents, 0)
  const unitPrice = product.price_lrd_cents + optionDelta

  const missingRequired = product.option_groups.some((g) => g.is_required && !(selected[g.id]?.length > 0))
  const canAdd = product.available && !missingRequired

  function toggleSingle(groupId: string, optionId: string) {
    setSelected((prev) => ({ ...prev, [groupId]: [optionId] }))
  }

  function toggleMultiple(groupId: string, optionId: string) {
    setSelected((prev) => {
      const current = prev[groupId] ?? []
      const next = current.includes(optionId) ? current.filter((id) => id !== optionId) : [...current, optionId]
      return { ...prev, [groupId]: next }
    })
  }

  return (
    <Sheet open={!!product} onClose={onClose} title={product.name} description={product.description ?? undefined}>
      <div className="space-y-5">
        {product.images.length > 0 && (
          <div className="overflow-hidden rounded-lg bg-zinc-100">
            <img
              src={productImagePublicUrl(product.images[0].storage_path)}
              alt={product.name}
              className="aspect-video w-full object-cover"
            />
          </div>
        )}

        {!product.available && (
          <p className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">This item is currently out of stock.</p>
        )}

        {product.option_groups.map((group) => (
          <div key={group.id}>
            <p className="mb-2 text-sm font-medium">
              {group.name}
              {group.is_required && <span className="ml-1 text-xs text-red-600">Required</span>}
            </p>
            <div className="space-y-1.5">
              {group.options.map((option) => {
                const checked = (selected[group.id] ?? []).includes(option.id)
                return (
                  <label
                    key={option.id}
                    className="flex cursor-pointer items-center justify-between rounded-lg border px-3 py-2 text-sm has-[:checked]:border-[var(--color-primary)] has-[:checked]:bg-[color-mix(in_oklab,var(--color-primary)_8%,white)]"
                  >
                    <span className="flex items-center gap-2">
                      <input
                        type={group.selection_type === 'single' ? 'radio' : 'checkbox'}
                        name={group.id}
                        checked={checked}
                        onChange={() =>
                          group.selection_type === 'single' ? toggleSingle(group.id, option.id) : toggleMultiple(group.id, option.id)
                        }
                      />
                      {option.name}
                    </span>
                    {option.price_delta_lrd_cents !== 0 && (
                      <span className="tabular-nums text-[var(--color-muted)]">
                        +{formatLrdFromCents(option.price_delta_lrd_cents)}
                      </span>
                    )}
                  </label>
                )
              })}
            </div>
          </div>
        ))}

        <div className="flex items-center justify-between border-t pt-4">
          <span className="text-sm font-medium">Quantity</span>
          <div className="flex items-center gap-3">
            <Button type="button" size="sm" variant="outline" onClick={() => setQuantity((q) => Math.max(1, q - 1))} aria-label="Decrease quantity">
              <Minus className="h-4 w-4" />
            </Button>
            <span className="w-6 text-center tabular-nums">{quantity}</span>
            <Button type="button" size="sm" variant="outline" onClick={() => setQuantity((q) => q + 1)} aria-label="Increase quantity">
              <Plus className="h-4 w-4" />
            </Button>
          </div>
        </div>

        <Button
          type="button"
          className="w-full"
          disabled={!canAdd}
          onClick={() => {
            onAdd(product.id, quantity, selectedIds)
            onClose()
          }}
        >
          {product.available
            ? `Add to cart — ${formatLrdFromCents(unitPrice * quantity)}`
            : 'Out of stock'}
        </Button>
      </div>
    </Sheet>
  )
}
