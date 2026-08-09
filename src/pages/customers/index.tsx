import { useState } from 'react'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { PageHeader } from '@/components/ui/PageHeader'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { useAuth } from '@/hooks/use-auth'
import {
  useCustomersList,
  useUpdateCustomer,
  useUpsertCustomer,
} from '@/hooks/use-customers'
import type { Customer } from '@/types/fleet'
import { customerSchema } from '@/utils/customer-schemas'

export function CustomersPage() {
  const { context } = useAuth()
  const companyId = context?.activeCompanyId ?? null

  const { data: customers = [], isLoading, error } = useCustomersList(companyId)
  const upsertMutation = useUpsertCustomer(companyId)
  const updateMutation = useUpdateCustomer(companyId)

  const [formError, setFormError] = useState<string | null>(null)
  const [editing, setEditing] = useState<Customer | null>(null)
  const [query, setQuery] = useState('')

  const filtered = customers.filter((c) => {
    const q = query.trim().toLowerCase()
    if (!q) return true
    return (
      c.full_name.toLowerCase().includes(q) ||
      c.phone.toLowerCase().includes(q) ||
      (c.address ?? '').toLowerCase().includes(q)
    )
  })

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const form = e.currentTarget
    setFormError(null)
    const fd = new FormData(form)
    const parsed = customerSchema.safeParse({
      fullName: fd.get('fullName'),
      phone: fd.get('phone'),
      address: fd.get('address') || undefined,
      landmark: fd.get('landmark') || undefined,
      notes: fd.get('notes') || undefined,
    })
    if (!parsed.success) {
      setFormError(parsed.error.issues[0]?.message ?? 'Invalid form')
      return
    }
    try {
      if (editing) {
        await updateMutation.mutateAsync({ id: editing.id, input: parsed.data })
        setEditing(null)
      } else {
        await upsertMutation.mutateAsync(parsed.data)
      }
      form.reset()
    } catch (err) {
      setFormError(err instanceof Error ? err.message : 'Save failed')
    }
  }

  function startEdit(c: Customer) {
    setEditing(c)
    setFormError(null)
  }

  function cancelEdit() {
    setEditing(null)
    setFormError(null)
  }

  if (!companyId) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>No workspace</CardTitle>
          <CardDescription>Register or join a company to manage customers.</CardDescription>
        </CardHeader>
      </Card>
    )
  }

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader
        title="Customers"
        description="CRM-style directory — search, notes, and saved addresses."
      />
      <Input
        placeholder="Search name, phone, address…"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        className="max-w-md"
        aria-label="Search customers"
      />
      <p className="text-sm text-[var(--color-muted)]">
        Unique by phone per company · used on delivery create
      </p>

      <Card>
        <CardHeader>
          <CardTitle>{editing ? 'Edit customer' : 'Add customer'}</CardTitle>
          <CardDescription>
            {editing
              ? 'Update row (RLS ensures same tenant).'
              : 'Upsert on (company_id, phone) if phone already exists.'}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form
            key={editing?.id ?? 'new'}
            className="grid gap-4 md:grid-cols-2"
            onSubmit={onSubmit}
          >
            {formError && <p className="text-sm text-red-600 md:col-span-2">{formError}</p>}
            <FormField
              label="Name"
              name="fullName"
              required
              defaultValue={editing?.full_name}
            />
            <FormField
              label="Phone"
              name="phone"
              required
              defaultValue={editing?.phone}
              readOnly={!!editing}
            />
            <FormField
              label="Address"
              name="address"
              className="md:col-span-2"
              defaultValue={editing?.address ?? ''}
            />
            <FormField label="Landmark" name="landmark" defaultValue={editing?.landmark ?? ''} />
            <FormField label="Notes" name="notes" defaultValue={editing?.notes ?? ''} />
            <div className="flex gap-2 md:col-span-2">
              <Button
                type="submit"
                disabled={upsertMutation.isPending || updateMutation.isPending}
              >
                {editing ? 'Update' : 'Save customer'}
              </Button>
              {editing && (
                <Button type="button" variant="outline" onClick={cancelEdit}>
                  Cancel
                </Button>
              )}
            </div>
          </form>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="overflow-x-auto pt-6">
          {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
          {error && (
            <p className="text-sm text-red-600">
              {error instanceof Error ? error.message : 'Failed to load'}
            </p>
          )}
          <table className="w-full min-w-[640px] text-left text-sm">
            <thead className="sticky top-0 bg-white">
              <tr className="border-b text-xs uppercase tracking-wide text-[var(--color-muted)]">
                <th className="py-2">Name</th>
                <th className="py-2">Phone</th>
                <th className="py-2">Address</th>
                <th className="py-2">Landmark</th>
                <th className="py-2" />
              </tr>
            </thead>
            <tbody>
              {filtered.map((c) => (
                <tr key={c.id} className="border-b transition-colors hover:bg-zinc-50/80">
                  <td className="py-3 font-medium">{c.full_name}</td>
                  <td className="py-3">{c.phone}</td>
                  <td className="py-3 text-[var(--color-muted)]">{c.address ?? '—'}</td>
                  <td className="py-3 text-[var(--color-muted)]">{c.landmark ?? '—'}</td>
                  <td className="py-3">
                    <Button type="button" size="sm" variant="outline" onClick={() => startEdit(c)}>
                      Edit
                    </Button>
                  </td>
                </tr>
              ))}
              {!isLoading && filtered.length === 0 && (
                <tr>
                  <td colSpan={5} className="py-8 text-center text-[var(--color-muted)]">
                    No customers yet.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </CardContent>
      </Card>
    </div>
  )
}

function FormField({
  label,
  name,
  className,
  ...props
}: { label: string; name: string; className?: string } & React.ComponentProps<'input'>) {
  return (
    <div className={`space-y-2 ${className ?? ''}`}>
      <Label htmlFor={name}>{label}</Label>
      <Input id={name} name={name} {...props} />
    </div>
  )
}
