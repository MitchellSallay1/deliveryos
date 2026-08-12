import { useState } from 'react'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { useAuth } from '@/hooks/use-auth'
import { updateMyProfile } from '@/services/settings-service'
import { parseSupabaseError } from '@/lib/supabase-errors'

export function RiderProfilePage() {
  const { context, user, refreshContext } = useAuth()
  const riderMembership = context?.memberships.find((m) => m.role === 'rider')
  const [message, setMessage] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    setError(null)
    setMessage(null)
    const fd = new FormData(e.currentTarget)
    setSaving(true)
    try {
      await updateMyProfile({
        full_name: String(fd.get('fullName') || ''),
        phone: String(fd.get('phone') || '') || null,
      })
      refreshContext()
      setMessage('Profile saved.')
    } catch (err) {
      setError(parseSupabaseError(err))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="mx-auto max-w-lg space-y-4">
      <h2 className="text-xl font-semibold">Profile</h2>
      {riderMembership && (
        <p className="text-sm text-[var(--color-muted)]">
          Linked to {riderMembership.company.name}
        </p>
      )}
      <Card>
        <CardHeader>
          <CardTitle>Your details</CardTitle>
          <CardDescription>Phone must match your rider record when linking by rider ID.</CardDescription>
        </CardHeader>
        <CardContent>
          <form className="space-y-4" onSubmit={onSubmit}>
            {error && <p className="text-sm text-red-600">{error}</p>}
            {message && <p className="text-sm text-teal-700">{message}</p>}
            <div className="space-y-2">
              <Label htmlFor="fullName">Full name</Label>
              <Input
                id="fullName"
                name="fullName"
                defaultValue={context?.profile?.full_name ?? ''}
                required
                disabled={saving}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="phone">Phone</Label>
              <Input
                id="phone"
                name="phone"
                defaultValue={context?.profile?.phone ?? ''}
                placeholder="+231…"
                disabled={saving}
              />
            </div>
            <p className="text-xs text-[var(--color-muted)]">{user?.email}</p>
            <Button type="submit" disabled={saving}>
              Save
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}
