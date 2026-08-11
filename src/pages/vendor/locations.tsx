import { useState } from 'react'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { PageHeader } from '@/components/ui/PageHeader'
import { Badge } from '@/components/ui/Badge'
import { VendorGuard } from '@/components/vendor/VendorGuard'
import { useVendorContext } from '@/hooks/use-vendor-context'
import { useUpsertVendorBranch, useVendorBranches } from '@/hooks/use-vendor-commerce'
import { parseSupabaseError } from '@/lib/supabase-errors'
import type { VendorBranch } from '@/services/vendor-commerce-service'

function VendorLocationsContent() {
  const { companyId } = useVendorContext()
  const { data: branches = [], isLoading, error } = useVendorBranches(companyId)
  const upsert = useUpsertVendorBranch(companyId)

  const [editing, setEditing] = useState<VendorBranch | null>(null)
  const [showForm, setShowForm] = useState(false)
  const [formError, setFormError] = useState<string | null>(null)

  function startCreate() {
    setEditing(null)
    setShowForm(true)
    setFormError(null)
  }

  function startEdit(b: VendorBranch) {
    setEditing(b)
    setShowForm(true)
    setFormError(null)
  }

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    if (!companyId) return
    setFormError(null)
    const fd = new FormData(e.currentTarget)
    try {
      await upsert.mutateAsync({
        id: editing?.id,
        company_id: companyId,
        name: String(fd.get('name') || ''),
        code: String(fd.get('code') || ''),
        address: String(fd.get('address') || ''),
        city: String(fd.get('city') || ''),
        latitude: fd.get('latitude') ? Number(fd.get('latitude')) : undefined,
        longitude: fd.get('longitude') ? Number(fd.get('longitude')) : undefined,
        phone: String(fd.get('phone') || ''),
        is_active: true,
      })
      setShowForm(false)
      setEditing(null)
    } catch (err) {
      setFormError(parseSupabaseError(err))
    }
  }

  async function toggleActive(b: VendorBranch) {
    setFormError(null)
    try {
      await upsert.mutateAsync({ id: b.id, company_id: b.company_id, is_active: !b.is_active })
    } catch (err) {
      setFormError(parseSupabaseError(err))
    }
  }

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader
        title="Vendor locations"
        description="Pickup locations for your storefront — the same branches used across DeliveryOS operations."
      />

      {error && <p className="text-sm text-red-600">{parseSupabaseError(error)}</p>}

      <Card>
        <CardHeader className="flex-row items-center justify-between">
          <CardTitle>Locations</CardTitle>
          <Button type="button" size="sm" onClick={startCreate}>
            Add location
          </Button>
        </CardHeader>
        <CardContent>
          {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
          {!isLoading && branches.length === 0 && (
            <p className="text-sm text-[var(--color-muted)]">No pickup locations yet.</p>
          )}
          <ul className="divide-y">
            {branches.map((b) => (
              <li key={b.id} className="flex flex-wrap items-center justify-between gap-2 py-3">
                <div>
                  <div className="flex items-center gap-2 font-medium">
                    {b.name}
                    <Badge variant={b.is_active ? 'success' : 'outline'}>{b.is_active ? 'Active' : 'Inactive'}</Badge>
                  </div>
                  <div className="text-xs text-[var(--color-muted)]">
                    {b.code} · {b.address ?? 'No address'} {b.city ? `· ${b.city}` : ''}
                    {b.latitude != null && b.longitude != null ? ` · ${b.latitude.toFixed(4)}, ${b.longitude.toFixed(4)}` : ''}
                  </div>
                </div>
                <div className="flex gap-2">
                  <Button type="button" size="sm" variant="outline" onClick={() => startEdit(b)}>
                    Edit
                  </Button>
                  <Button type="button" size="sm" variant="outline" onClick={() => void toggleActive(b)}>
                    {b.is_active ? 'Deactivate' : 'Activate'}
                  </Button>
                </div>
              </li>
            ))}
          </ul>
        </CardContent>
      </Card>

      {showForm && (
        <Card>
          <CardHeader>
            <CardTitle>{editing ? `Edit ${editing.name}` : 'New location'}</CardTitle>
            <CardDescription>Coordinates are optional — an address/landmark description is enough to get started.</CardDescription>
          </CardHeader>
          <CardContent>
            <form key={editing?.id ?? 'new'} className="grid gap-4 md:grid-cols-2" onSubmit={onSubmit}>
              {formError && <p className="text-sm text-red-600 md:col-span-2">{formError}</p>}
              <div className="space-y-2">
                <Label htmlFor="name">Name</Label>
                <Input id="name" name="name" defaultValue={editing?.name} required />
              </div>
              <div className="space-y-2">
                <Label htmlFor="code">Code</Label>
                <Input id="code" name="code" defaultValue={editing?.code} required disabled={!!editing} />
              </div>
              <div className="space-y-2 md:col-span-2">
                <Label htmlFor="address">Address / landmark</Label>
                <Input id="address" name="address" defaultValue={editing?.address ?? ''} />
              </div>
              <div className="space-y-2">
                <Label htmlFor="city">City</Label>
                <Input id="city" name="city" defaultValue={editing?.city ?? ''} />
              </div>
              <div className="space-y-2">
                <Label htmlFor="phone">Phone</Label>
                <Input id="phone" name="phone" defaultValue={editing?.phone ?? ''} />
              </div>
              <div className="space-y-2">
                <Label htmlFor="latitude">Latitude (optional)</Label>
                <Input id="latitude" name="latitude" type="number" step="any" defaultValue={editing?.latitude ?? ''} />
              </div>
              <div className="space-y-2">
                <Label htmlFor="longitude">Longitude (optional)</Label>
                <Input id="longitude" name="longitude" type="number" step="any" defaultValue={editing?.longitude ?? ''} />
              </div>
              <div className="flex gap-2 md:col-span-2">
                <Button type="submit" disabled={upsert.isPending}>
                  {upsert.isPending ? 'Saving…' : 'Save location'}
                </Button>
                <Button type="button" variant="outline" onClick={() => setShowForm(false)}>
                  Cancel
                </Button>
              </div>
            </form>
          </CardContent>
        </Card>
      )}
    </div>
  )
}

export function VendorLocationsPage() {
  return (
    <VendorGuard>
      <VendorLocationsContent />
    </VendorGuard>
  )
}
