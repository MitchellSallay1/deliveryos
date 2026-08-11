import { useMemo, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { Tabs } from '@/components/ui/Tabs'
import { CartDrawer, CartFab, cartSubtotal } from '@/components/storefront/CartBar'
import { ProductCard } from '@/components/storefront/ProductCard'
import { ProductDetailModal } from '@/components/storefront/ProductDetailModal'
import { useLocalCart } from '@/hooks/use-local-cart'
import { usePublicStoreCatalog } from '@/hooks/use-storefront'
import { parseSupabaseError } from '@/lib/supabase-errors'

const ALL_TAB = '__all__'

export function StorePage() {
  const { slug } = useParams()
  const navigate = useNavigate()
  const { data: catalog, isLoading, error } = usePublicStoreCatalog(slug)
  const cart = useLocalCart(slug ?? '')

  const [activeCategory, setActiveCategory] = useState(ALL_TAB)
  const [openProductId, setOpenProductId] = useState<string | null>(null)
  const [cartOpen, setCartOpen] = useState(false)

  const products = useMemo(() => {
    if (!catalog) return []
    if (activeCategory === ALL_TAB) return catalog.products
    return catalog.products.filter((p) => p.category_id === activeCategory)
  }, [catalog, activeCategory])

  const openProduct = catalog?.products.find((p) => p.id === openProductId) ?? null

  if (isLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center text-sm text-[var(--color-muted)]">Loading store…</div>
    )
  }

  if (error || !catalog) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center gap-2 p-6 text-center">
        <p className="text-lg font-semibold">Store not found</p>
        <p className="max-w-sm text-sm text-[var(--color-muted)]">
          {error ? parseSupabaseError(error) : 'This store is not currently available.'}
        </p>
      </div>
    )
  }

  const { store, categories } = catalog

  return (
    <div className="min-h-screen bg-[var(--color-background)] pb-28">
      {store.banner_url ? (
        <div className="h-36 w-full bg-zinc-100 sm:h-48">
          <img src={store.banner_url} alt="" className="h-full w-full object-cover" />
        </div>
      ) : (
        <div className="h-20 w-full bg-gradient-to-r from-[var(--color-primary)]/10 to-[var(--color-accent)]/10" />
      )}

      <div className="mx-auto max-w-2xl px-4">
        <div className="-mt-8 flex items-end gap-3">
          <div className="h-16 w-16 shrink-0 overflow-hidden rounded-2xl border-4 border-[var(--color-background)] bg-white shadow-sm">
            {store.logo_url ? (
              <img src={store.logo_url} alt={store.display_name} className="h-full w-full object-cover" />
            ) : (
              <div className="flex h-full w-full items-center justify-center text-lg font-semibold text-[var(--color-muted)]">
                {store.display_name.slice(0, 1)}
              </div>
            )}
          </div>
        </div>

        <div className="mt-3 space-y-1">
          <h1 className="text-xl font-semibold">{store.display_name}</h1>
          {store.description && <p className="text-sm text-[var(--color-muted)]">{store.description}</p>}
          {!store.allow_cash_on_delivery && (
            <p className="mt-1 text-xs text-amber-700">This store isn&apos;t accepting online orders right now.</p>
          )}
        </div>

        {categories.length > 0 && (
          <div className="mt-4">
            <Tabs
              value={activeCategory}
              onValueChange={setActiveCategory}
              items={[{ value: ALL_TAB, label: 'All' }, ...categories.map((c) => ({ value: c.id, label: c.name }))]}
            />
          </div>
        )}

        <div className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-3">
          {products.map((product) => (
            <ProductCard key={product.id} product={product} onSelect={() => setOpenProductId(product.id)} />
          ))}
          {products.length === 0 && (
            <p className="col-span-full py-8 text-center text-sm text-[var(--color-muted)]">No products here yet.</p>
          )}
        </div>
      </div>

      <ProductDetailModal
        product={openProduct}
        onClose={() => setOpenProductId(null)}
        onAdd={(productId, quantity, selectedOptionIds) => cart.addItem(productId, quantity, selectedOptionIds)}
      />

      <CartFab itemCount={cart.itemCount} subtotal={cartSubtotal(catalog, cart.items)} onOpen={() => setCartOpen(true)} />
      <CartDrawer
        open={cartOpen}
        onClose={() => setCartOpen(false)}
        catalog={catalog}
        items={cart.items}
        onUpdateQuantity={cart.updateQuantity}
        onRemove={cart.removeItem}
        onCheckout={() => navigate(`/store/${slug}/checkout`)}
      />
    </div>
  )
}
