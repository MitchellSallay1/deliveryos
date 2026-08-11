import { useState } from 'react'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { PageHeader } from '@/components/ui/PageHeader'
import { Badge } from '@/components/ui/Badge'
import { VendorGuard } from '@/components/vendor/VendorGuard'
import { useVendorContext } from '@/hooks/use-vendor-context'
import { useProductCategories, useUpsertProductCategory, useVendorProducts } from '@/hooks/use-vendor-commerce'
import { parseSupabaseError } from '@/lib/supabase-errors'
import type { ProductCategory } from '@/services/vendor-commerce-service'

function VendorCatalogContent() {
  const { companyId } = useVendorContext()
  const { data: categories = [], isLoading, error } = useProductCategories(companyId)
  const { data: products = [] } = useVendorProducts(companyId)
  const upsert = useUpsertProductCategory(companyId)

  const [editing, setEditing] = useState<ProductCategory | null>(null)
  const [name, setName] = useState('')
  const [formError, setFormError] = useState<string | null>(null)

  const productCountByCategory = new Map<string, number>()
  for (const p of products) {
    if (!p.category_id) continue
    productCountByCategory.set(p.category_id, (productCountByCategory.get(p.category_id) ?? 0) + 1)
  }

  function startEdit(c: ProductCategory) {
    setEditing(c)
    setName(c.name)
    setFormError(null)
  }

  function startCreate() {
    setEditing(null)
    setName('')
    setFormError(null)
  }

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    if (!companyId) return
    setFormError(null)
    try {
      await upsert.mutateAsync({ id: editing?.id, company_id: companyId, name: name.trim() })
      setEditing(null)
      setName('')
    } catch (err) {
      setFormError(parseSupabaseError(err))
    }
  }

  async function toggleActive(c: ProductCategory) {
    if (!companyId) return
    setFormError(null)
    try {
      await upsert.mutateAsync({ id: c.id, company_id: companyId, is_active: !c.is_active })
    } catch (err) {
      setFormError(parseSupabaseError(err))
    }
  }

  async function moveOrder(c: ProductCategory, direction: -1 | 1) {
    if (!companyId) return
    try {
      await upsert.mutateAsync({ id: c.id, company_id: companyId, sort_order: c.sort_order + direction })
    } catch (err) {
      setFormError(parseSupabaseError(err))
    }
  }

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader title="Catalog" description="Organize products into categories customers will browse." />

      {error && <p className="text-sm text-red-600">{parseSupabaseError(error)}</p>}

      <Card>
        <CardHeader>
          <CardTitle>{editing ? `Rename ${editing.name}` : 'New category'}</CardTitle>
        </CardHeader>
        <CardContent>
          <form className="flex flex-wrap items-end gap-3" onSubmit={onSubmit}>
            {formError && <p className="w-full text-sm text-red-600">{formError}</p>}
            <div className="flex-1 space-y-2">
              <Label htmlFor="category-name">Category name</Label>
              <Input id="category-name" value={name} onChange={(e) => setName(e.target.value)} required />
            </div>
            <Button type="submit" disabled={upsert.isPending}>
              {editing ? 'Save' : 'Add category'}
            </Button>
            {editing && (
              <Button type="button" variant="outline" onClick={startCreate}>
                Cancel
              </Button>
            )}
          </form>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Categories</CardTitle>
        </CardHeader>
        <CardContent>
          {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
          {!isLoading && categories.length === 0 && (
            <p className="text-sm text-[var(--color-muted)]">No categories yet — add one above.</p>
          )}
          <ul className="divide-y">
            {categories.map((c) => (
              <li key={c.id} className="flex flex-wrap items-center justify-between gap-2 py-3">
                <div className="flex items-center gap-2">
                  <span className="font-medium">{c.name}</span>
                  <Badge variant={c.is_active ? 'success' : 'outline'}>{c.is_active ? 'Active' : 'Inactive'}</Badge>
                  <span className="text-xs text-[var(--color-muted)]">
                    {productCountByCategory.get(c.id) ?? 0} products
                  </span>
                </div>
                <div className="flex gap-2">
                  <Button type="button" size="sm" variant="outline" onClick={() => void moveOrder(c, -1)}>
                    ↑
                  </Button>
                  <Button type="button" size="sm" variant="outline" onClick={() => void moveOrder(c, 1)}>
                    ↓
                  </Button>
                  <Button type="button" size="sm" variant="outline" onClick={() => startEdit(c)}>
                    Rename
                  </Button>
                  <Button type="button" size="sm" variant="outline" onClick={() => void toggleActive(c)}>
                    {c.is_active ? 'Deactivate' : 'Activate'}
                  </Button>
                </div>
              </li>
            ))}
          </ul>
        </CardContent>
      </Card>
    </div>
  )
}

export function VendorCatalogPage() {
  return (
    <VendorGuard>
      <VendorCatalogContent />
    </VendorGuard>
  )
}
