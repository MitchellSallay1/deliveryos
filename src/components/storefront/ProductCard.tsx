import { Badge } from '@/components/ui/Badge'
import { productImagePublicUrl } from '@/services/storefront-service'
import { formatLrdFromCents } from '@/utils/delivery-schemas'
import type { PublicStoreProduct } from '@/services/storefront-service'

export function ProductCard({ product, onSelect }: { product: PublicStoreProduct; onSelect: () => void }) {
  const image = product.images[0]

  return (
    <button
      type="button"
      onClick={onSelect}
      className="flex flex-col overflow-hidden rounded-[var(--radius-lg)] border bg-[var(--color-card)] text-left shadow-sm transition-transform active:scale-[0.98]"
    >
      <div className="relative aspect-square w-full bg-zinc-100">
        {image ? (
          <img
            src={productImagePublicUrl(image.storage_path)}
            alt={product.name}
            loading="lazy"
            className="h-full w-full object-cover"
          />
        ) : (
          <div className="flex h-full w-full items-center justify-center text-xs text-[var(--color-muted)]">No image</div>
        )}
        {!product.available && (
          <Badge variant="danger" className="absolute right-2 top-2">
            Out of stock
          </Badge>
        )}
      </div>
      <div className="flex flex-1 flex-col gap-1 p-3">
        <p className="line-clamp-2 text-sm font-medium">{product.name}</p>
        <p className="mt-auto text-sm font-semibold tabular-nums">{formatLrdFromCents(product.price_lrd_cents)}</p>
      </div>
    </button>
  )
}
