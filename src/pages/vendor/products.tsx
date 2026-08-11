import { useState } from 'react'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { PageHeader } from '@/components/ui/PageHeader'
import { Badge } from '@/components/ui/Badge'
import { VendorGuard } from '@/components/vendor/VendorGuard'
import { ProductImageUploader } from '@/components/vendor/ProductImageUploader'
import { useVendorContext } from '@/hooks/use-vendor-context'
import { useProductCategories, useVendorProductActions, useVendorProducts } from '@/hooks/use-vendor-commerce'
import { parseSupabaseError } from '@/lib/supabase-errors'
import { removeProductImageFile } from '@/services/storage-service'
import { formatLrdFromCents } from '@/utils/delivery-schemas'
import { productDisplayStatus } from '@/lib/vendor-commerce-ui'
import type { ProductImage, VendorProduct } from '@/services/vendor-commerce-service'
import type { CommerceProductStatus } from '@/types/supabase'

function NewProductForm({ companyId, categories }: { companyId: string; categories: { id: string; name: string }[] }) {
  const { saveProduct } = useVendorProductActions(companyId)
  const [name, setName] = useState('')
  const [price, setPrice] = useState('')
  const [categoryId, setCategoryId] = useState('')
  const [tracksInventory, setTracksInventory] = useState(false)
  const [initialQuantity, setInitialQuantity] = useState('0')
  const [error, setError] = useState<string | null>(null)

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    setError(null)
    const priceLrd = Number(price)
    if (!Number.isFinite(priceLrd) || priceLrd < 0) {
      setError('Enter a valid price.')
      return
    }
    try {
      await saveProduct.mutateAsync({
        company_id: companyId,
        name: name.trim(),
        category_id: categoryId || null,
        price_lrd_cents: Math.round(priceLrd * 100),
        status: 'draft',
        tracks_inventory: tracksInventory,
        initial_quantity: tracksInventory ? Number(initialQuantity) || 0 : undefined,
      })
      setName('')
      setPrice('')
      setCategoryId('')
      setTracksInventory(false)
      setInitialQuantity('0')
    } catch (err) {
      setError(parseSupabaseError(err))
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Add product</CardTitle>
        <CardDescription>New products start as Draft — set status to Active when ready to sell.</CardDescription>
      </CardHeader>
      <CardContent>
        <form className="grid gap-4 md:grid-cols-2" onSubmit={onSubmit}>
          {error && <p className="text-sm text-red-600 md:col-span-2">{error}</p>}
          <div className="space-y-2">
            <Label htmlFor="product-name">Name</Label>
            <Input id="product-name" value={name} onChange={(e) => setName(e.target.value)} required />
          </div>
          <div className="space-y-2">
            <Label htmlFor="product-price">Price (LRD)</Label>
            <Input id="product-price" type="number" min="0" step="1" value={price} onChange={(e) => setPrice(e.target.value)} required />
          </div>
          <div className="space-y-2">
            <Label htmlFor="product-category">Category</Label>
            <select
              id="product-category"
              className="flex h-10 w-full rounded-lg border bg-white px-3 text-sm"
              value={categoryId}
              onChange={(e) => setCategoryId(e.target.value)}
            >
              <option value="">No category</option>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>{c.name}</option>
              ))}
            </select>
          </div>
          <div className="flex items-end gap-3">
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={tracksInventory} onChange={(e) => setTracksInventory(e.target.checked)} />
              Track stock quantity
            </label>
            {tracksInventory && (
              <div className="space-y-2">
                <Label htmlFor="initial-qty">Starting quantity</Label>
                <Input id="initial-qty" type="number" min="0" step="1" value={initialQuantity} onChange={(e) => setInitialQuantity(e.target.value)} className="w-28" />
              </div>
            )}
          </div>
          <div className="md:col-span-2">
            <Button type="submit" disabled={saveProduct.isPending}>
              {saveProduct.isPending ? 'Adding…' : 'Add product'}
            </Button>
          </div>
        </form>
      </CardContent>
    </Card>
  )
}

function ProductManagePanel({ companyId, product }: { companyId: string; product: VendorProduct }) {
  const { saveOptionGroup, saveOption, saveImage, removeImage, adjustStock } = useVendorProductActions(companyId)
  const [groupName, setGroupName] = useState('')
  const [optionDrafts, setOptionDrafts] = useState<Record<string, { name: string; delta: string }>>({})
  const [removingImageId, setRemovingImageId] = useState<string | null>(null)
  const [stockDelta, setStockDelta] = useState('')
  const [stockReason, setStockReason] = useState('')
  const [error, setError] = useState<string | null>(null)

  async function addGroup() {
    setError(null)
    try {
      await saveOptionGroup.mutateAsync({ product_id: product.id, name: groupName.trim() })
      setGroupName('')
    } catch (err) {
      setError(parseSupabaseError(err))
    }
  }

  async function addOption(groupId: string) {
    setError(null)
    const draft = optionDrafts[groupId]
    if (!draft?.name) return
    try {
      await saveOption.mutateAsync({
        option_group_id: groupId,
        name: draft.name.trim(),
        price_delta_lrd_cents: Math.round((Number(draft.delta) || 0) * 100),
      })
      setOptionDrafts((prev) => ({ ...prev, [groupId]: { name: '', delta: '' } }))
    } catch (err) {
      setError(parseSupabaseError(err))
    }
  }

  async function uploadImage(args: { storage_path: string; sort_order: number }) {
    setError(null)
    try {
      await saveImage.mutateAsync({ product_id: product.id, ...args })
    } catch (err) {
      setError(parseSupabaseError(err))
      throw err
    }
  }

  async function removeImageAndFile(image: ProductImage) {
    setError(null)
    setRemovingImageId(image.id)
    try {
      // Best-effort storage cleanup first; the RPC delete of the DB row is
      // the authoritative removal (what actually stops it from showing up
      // anywhere), so it still proceeds even if the file was already gone.
      await removeProductImageFile(image.storage_path).catch(() => undefined)
      await removeImage.mutateAsync(image.id)
    } catch (err) {
      setError(parseSupabaseError(err))
    } finally {
      setRemovingImageId(null)
    }
  }

  async function submitStockAdjustment() {
    setError(null)
    const delta = Number(stockDelta)
    if (!delta) return
    try {
      await adjustStock.mutateAsync({ productId: product.id, delta, reason: stockReason.trim() || undefined })
      setStockDelta('')
      setStockReason('')
    } catch (err) {
      setError(parseSupabaseError(err))
    }
  }

  return (
    <div className="space-y-4 border-t pt-4">
      {error && <p className="text-sm text-red-600">{error}</p>}

      {product.tracks_inventory && (
        <div>
          <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-[var(--color-muted)]">Stock</p>
          <div className="flex flex-wrap items-end gap-2">
            <Input
              placeholder="+10 or -3"
              type="number"
              step="1"
              value={stockDelta}
              onChange={(e) => setStockDelta(e.target.value)}
              className="w-32"
            />
            <Input placeholder="Reason (optional)" value={stockReason} onChange={(e) => setStockReason(e.target.value)} className="w-52" />
            <Button type="button" size="sm" onClick={() => void submitStockAdjustment()} disabled={adjustStock.isPending}>
              Adjust stock
            </Button>
          </div>
        </div>
      )}

      <ProductImageUploader
        companyId={companyId}
        productId={product.id}
        images={product.product_images}
        onUpload={uploadImage}
        onRemove={removeImageAndFile}
        uploading={saveImage.isPending}
        removingId={removingImageId}
      />

      <div>
        <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-[var(--color-muted)]">Options / add-ons</p>
        {product.product_option_groups.map((g) => (
          <div key={g.id} className="mb-3 rounded-lg border p-3">
            <p className="text-sm font-medium">{g.name} <span className="text-xs text-[var(--color-muted)]">({g.selection_type})</span></p>
            <ul className="my-2 space-y-1">
              {g.product_options.map((o) => (
                <li key={o.id} className="text-sm text-[var(--color-muted)]">
                  {o.name} {o.price_delta_lrd_cents !== 0 ? `(+${formatLrdFromCents(o.price_delta_lrd_cents)})` : ''}
                </li>
              ))}
            </ul>
            <div className="flex flex-wrap gap-2">
              <Input
                placeholder="Option name"
                value={optionDrafts[g.id]?.name ?? ''}
                onChange={(e) => setOptionDrafts((prev) => ({ ...prev, [g.id]: { name: e.target.value, delta: prev[g.id]?.delta ?? '' } }))}
                className="max-w-[160px]"
              />
              <Input
                placeholder="+ price (LRD)"
                type="number"
                step="1"
                value={optionDrafts[g.id]?.delta ?? ''}
                onChange={(e) => setOptionDrafts((prev) => ({ ...prev, [g.id]: { name: prev[g.id]?.name ?? '', delta: e.target.value } }))}
                className="max-w-[120px]"
              />
              <Button type="button" size="sm" variant="outline" onClick={() => void addOption(g.id)}>
                Add option
              </Button>
            </div>
          </div>
        ))}
        <div className="flex gap-2">
          <Input placeholder="New option group (e.g. Size)" value={groupName} onChange={(e) => setGroupName(e.target.value)} />
          <Button type="button" size="sm" variant="outline" onClick={() => void addGroup()}>
            Add group
          </Button>
        </div>
      </div>
    </div>
  )
}

function VendorProductsContent() {
  const { companyId } = useVendorContext()
  const { data: products = [], isLoading, error } = useVendorProducts(companyId)
  const { data: categories = [] } = useProductCategories(companyId)
  const { saveProduct } = useVendorProductActions(companyId!)

  const [expanded, setExpanded] = useState<string | null>(null)
  const [statusError, setStatusError] = useState<string | null>(null)

  async function changeStatus(product: VendorProduct, status: CommerceProductStatus) {
    if (!companyId) return
    setStatusError(null)
    try {
      await saveProduct.mutateAsync({ id: product.id, company_id: companyId, status })
    } catch (err) {
      setStatusError(parseSupabaseError(err))
    }
  }

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader title="Products" description="Manage what customers will see on your storefront." />

      {error && <p className="text-sm text-red-600">{parseSupabaseError(error)}</p>}
      {statusError && <p className="text-sm text-red-600">{statusError}</p>}

      {companyId && <NewProductForm companyId={companyId} categories={categories} />}

      <Card>
        <CardHeader>
          <CardTitle>Products</CardTitle>
        </CardHeader>
        <CardContent>
          {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
          {!isLoading && products.length === 0 && (
            <p className="text-sm text-[var(--color-muted)]">No products yet — add one above.</p>
          )}
          <ul className="divide-y">
            {products.map((p) => {
              const stock = p.product_stock
              const available = stock ? stock.quantity_on_hand - stock.quantity_reserved : null
              const display = productDisplayStatus(p.status, p.tracks_inventory, available)
              const isOpen = expanded === p.id
              return (
                <li key={p.id} className="py-3">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div>
                      <div className="flex items-center gap-2 font-medium">
                        {p.name}
                        <Badge variant={display.variant}>{display.label}</Badge>
                      </div>
                      <div className="text-xs text-[var(--color-muted)]">
                        {formatLrdFromCents(p.price_lrd_cents)} · {p.product_categories?.name ?? 'No category'}
                        {p.tracks_inventory && stock && (
                          <> · On hand {stock.quantity_on_hand} · Reserved {stock.quantity_reserved} · Available {available}</>
                        )}
                      </div>
                    </div>
                    <div className="flex flex-wrap gap-2">
                      <select
                        className="h-8 rounded-md border px-2 text-xs"
                        value={p.status}
                        onChange={(e) => void changeStatus(p, e.target.value as CommerceProductStatus)}
                      >
                        <option value="draft">Draft</option>
                        <option value="active">Active</option>
                        <option value="paused">Paused</option>
                      </select>
                      <Button type="button" size="sm" variant="outline" onClick={() => setExpanded(isOpen ? null : p.id)}>
                        {isOpen ? 'Close' : 'Manage'}
                      </Button>
                    </div>
                  </div>
                  {isOpen && companyId && <ProductManagePanel companyId={companyId} product={p} />}
                </li>
              )
            })}
          </ul>
        </CardContent>
      </Card>
    </div>
  )
}

export function VendorProductsPage() {
  return (
    <VendorGuard>
      <VendorProductsContent />
    </VendorGuard>
  )
}
