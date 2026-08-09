import { useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { Button } from '@/components/ui/Button'
import { AdminHealthBadge, AdminHealthReasons } from '@/components/admin/AdminHealthBadge'
import { useSupportLookup } from '@/hooks/use-admin-platform'

export function AdminSupportPage() {
  const [query, setQuery] = useState('')
  const [submitted, setSubmitted] = useState('')
  const { data, isLoading } = useSupportLookup(submitted, submitted.length >= 2)

  return (
    <Card>
      <CardHeader>
        <CardTitle>Support diagnostics</CardTitle>
        <p className="text-sm text-[var(--color-muted)]">
          Search by company phone/name or tracking code. No impersonation — read-only diagnostics.
        </p>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex max-w-md gap-2">
          <Input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Phone, company, tracking" />
          <Button onClick={() => setSubmitted(query.trim())}>Lookup</Button>
        </div>
        {isLoading && <p className="text-sm text-[var(--color-muted)]">Searching…</p>}
        {submitted.length >= 2 && data?.health != null ? (
          <div className="rounded-lg border p-4">
            <AdminHealthBadge level={(data.health as { level: string }).level} />
            <AdminHealthReasons reasons={(data.health as { reasons: string[] }).reasons} />
          </div>
        ) : null}
        {data && (
          <pre className="max-h-96 overflow-auto rounded-lg bg-zinc-50 p-3 text-xs">{JSON.stringify(data, null, 2)}</pre>
        )}
      </CardContent>
    </Card>
  )
}
