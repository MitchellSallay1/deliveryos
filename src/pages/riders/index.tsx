import { useState } from 'react'
import { PageHeader } from '@/components/ui/PageHeader'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { useAuth } from '@/hooks/use-auth'
import { getAppUrl } from '@/lib/app-url'
import {
  useCompanyPlanUsage,
  useCreateRider,
  useRegenerateRiderInvite,
  useRidersList,
  useUpdateRiderAccess,
  useUpdateRiderStatus,
} from '@/hooks/use-riders'
import type { Rider } from '@/types/fleet'
import type { RiderStatus } from '@/types/supabase'
import {
  createRiderSchema,
  isButtonPhoneCapable,
  riderStatusLabel,
} from '@/utils/rider-schemas'

const STATUSES = ['available', 'busy', 'offline', 'suspended'] as const

export function RidersPage() {
  const { context } = useAuth()
  const companyId = context?.activeCompanyId ?? null

  const { data: riders = [], isLoading, error } = useRidersList(companyId)
  const { data: plan } = useCompanyPlanUsage(companyId)
  const createMutation = useCreateRider(companyId)
  const statusMutation = useUpdateRiderStatus(companyId)
  const accessMutation = useUpdateRiderAccess(companyId)
  const inviteMutation = useRegenerateRiderInvite(companyId)

  const [formError, setFormError] = useState<string | null>(null)
  const [showForm, setShowForm] = useState(false)

  const atRiderLimit = plan != null && plan.rider_count >= plan.max_riders

  async function onCreate(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const form = e.currentTarget
    setFormError(null)
    if (atRiderLimit) {
      setFormError(`Rider limit reached for ${plan?.plan_name} plan (${plan?.max_riders}).`)
      return
    }
    const fd = new FormData(form)
    const parsed = createRiderSchema.safeParse({
      riderCode: fd.get('riderCode'),
      fullName: fd.get('fullName'),
      phone: fd.get('phone'),
      status: fd.get('status') || 'offline',
      accessMode: fd.get('accessMode') || 'smartphone',
      smsChannelEnabled: fd.get('smsChannelEnabled') === 'on',
      ussdChannelEnabled: fd.get('ussdChannelEnabled') === 'on',
    })
    if (!parsed.success) {
      setFormError(parsed.error.issues[0]?.message ?? 'Invalid form')
      return
    }
    try {
      await createMutation.mutateAsync(parsed.data)
      form.reset()
      setShowForm(false)
    } catch (err) {
      setFormError(err instanceof Error ? err.message : 'Could not create rider')
    }
  }

  async function setStatus(rider: Rider, status: RiderStatus) {
    setFormError(null)
    try {
      await statusMutation.mutateAsync({ id: rider.id, status })
    } catch (err) {
      setFormError(err instanceof Error ? err.message : 'Update failed')
    }
  }

  if (!companyId) {
    return <EmptyWorkspace />
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <PageHeader
          title="Riders"
          description={
            plan
              ? `${plan.plan_name} · ${plan.rider_count}/${plan.max_riders} riders`
              : 'Fleet roster and channel access'
          }
          className="flex-1"
        />
        <Button
          type="button"
          variant="outline"
          onClick={() => setShowForm((v) => !v)}
          disabled={atRiderLimit && !showForm}
        >
          {showForm ? 'Close' : 'Add rider'}
        </Button>
      </div>

      {formError && <p className="text-sm text-red-600">{formError}</p>}

      {showForm && (
        <Card>
          <CardHeader>
            <CardTitle>New rider</CardTitle>
            <CardDescription>Inserts are scoped by RLS to your company_id.</CardDescription>
          </CardHeader>
          <CardContent>
            <form className="grid gap-4 md:grid-cols-2" onSubmit={onCreate}>
              <FormField label="Rider ID" name="riderCode" placeholder="R001" required />
              <FormField label="Full name" name="fullName" required />
              <FormField label="Phone" name="phone" required />
              <div className="space-y-2">
                <Label htmlFor="accessMode">Access mode</Label>
                <select
                  id="accessMode"
                  name="accessMode"
                  className="flex h-10 w-full rounded-lg border bg-white px-3 text-sm"
                  defaultValue="smartphone"
                >
                  <option value="smartphone">Smartphone (PWA + auth)</option>
                  <option value="button_phone">Button phone (SMS/USSD)</option>
                  <option value="both">Both</option>
                </select>
              </div>
              <div className="space-y-2 md:col-span-2">
                <Label>Button-phone channels</Label>
                <div className="flex flex-wrap gap-4 text-sm">
                  <label className="flex items-center gap-2">
                    <input type="checkbox" name="smsChannelEnabled" defaultChecked />
                    SMS enabled
                  </label>
                  <label className="flex items-center gap-2">
                    <input type="checkbox" name="ussdChannelEnabled" defaultChecked />
                    USSD enabled
                  </label>
                </div>
              </div>
              <div className="space-y-2">
                <Label htmlFor="status">Initial status</Label>
                <select
                  id="status"
                  name="status"
                  className="flex h-10 w-full rounded-lg border bg-white px-3 text-sm"
                  defaultValue="offline"
                >
                  {STATUSES.map((s) => (
                    <option key={s} value={s}>
                      {riderStatusLabel(s)}
                    </option>
                  ))}
                </select>
              </div>
              <div className="md:col-span-2">
                <Button type="submit" disabled={createMutation.isPending}>
                  {createMutation.isPending ? 'Saving…' : 'Save rider'}
                </Button>
              </div>
            </form>
          </CardContent>
        </Card>
      )}

      <Card>
        <CardContent className="overflow-x-auto pt-6">
          {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading…</p>}
          {error && (
            <p className="text-sm text-red-600">
              {error instanceof Error ? error.message : 'Failed to load riders'}
            </p>
          )}
          <table className="w-full min-w-[640px] text-left text-sm">
            <thead>
              <tr className="border-b text-xs uppercase text-[var(--color-muted)]">
                <th className="py-2">ID</th>
                <th className="py-2">Name</th>
                <th className="py-2">Phone</th>
                <th className="py-2">Status</th>
                <th className="py-2">Done</th>
                <th className="py-2">Rating</th>
                <th className="py-2">Access</th>
                <th className="py-2">Channels</th>
                <th className="py-2">Login</th>
                <th className="py-2">Invite</th>
                <th className="py-2">Actions</th>
              </tr>
            </thead>
            <tbody>
              {riders.map((r) => (
                <tr key={r.id} className="border-b">
                  <td className="py-3 font-medium">{r.rider_code}</td>
                  <td className="py-3">{r.full_name}</td>
                  <td className="py-3">{r.phone}</td>
                  <td className="py-3 capitalize">{riderStatusLabel(r.status)}</td>
                  <td className="py-3">{r.completed_deliveries}</td>
                  <td className="py-3">{Number(r.rating).toFixed(1)}</td>
                  <td className="py-3">
                    <select
                      className="h-8 rounded-md border px-1 text-xs"
                      value={r.access_mode ?? 'smartphone'}
                      disabled={accessMutation.isPending}
                      onChange={(e) =>
                        void accessMutation.mutateAsync({
                          id: r.id,
                          accessMode: e.target.value as Rider['access_mode'],
                        })
                      }
                    >
                      <option value="smartphone">Smartphone</option>
                      <option value="button_phone">Button phone</option>
                      <option value="both">Both</option>
                    </select>
                  </td>
                  <td className="py-3 text-xs">
                    {isButtonPhoneCapable(r.access_mode ?? 'smartphone') ? (
                      <div>
                        <div>{r.sms_channel_enabled ? 'SMS on' : 'SMS off'}</div>
                        <div>{r.ussd_channel_enabled ? 'USSD on' : 'USSD off'}</div>
                        <div className="text-[var(--color-muted)]">Phone: {r.phone}</div>
                      </div>
                    ) : (
                      <span className="text-[var(--color-muted)]">PWA</span>
                    )}
                  </td>
                  <td className="py-3 text-xs text-[var(--color-muted)]">
                    {isButtonPhoneCapable(r.access_mode ?? 'smartphone') && !r.user_id ? (
                      <span>No login required</span>
                    ) : r.user_id ? (
                      'Linked'
                    ) : (
                      'Not linked'
                    )}
                  </td>
                  <td className="py-3 text-xs">
                    {!isButtonPhoneCapable(r.access_mode ?? 'smartphone') && r.invite_code ? (
                      <RiderInviteTools
                        inviteCode={r.invite_code}
                        onRegenerate={() => inviteMutation.mutateAsync(r.id)}
                        regenerating={inviteMutation.isPending}
                      />
                    ) : (
                      <span className="text-[var(--color-muted)]">—</span>
                    )}
                  </td>
                  <td className="py-3">
                    <div className="flex flex-wrap gap-1">
                      {r.status === 'suspended' ? (
                        <Button type="button" size="sm" variant="outline" onClick={() => setStatus(r, 'offline')}>
                          Reinstate
                        </Button>
                      ) : (
                        <>
                          <Button type="button" size="sm" variant="outline" onClick={() => setStatus(r, 'available')}>
                            Available
                          </Button>
                          <Button type="button" size="sm" variant="destructive" onClick={() => setStatus(r, 'suspended')}>
                            Suspend
                          </Button>
                        </>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
              {!isLoading && riders.length === 0 && (
                <tr>
                  <td colSpan={10} className="py-8 text-center text-[var(--color-muted)]">
                    No riders yet. Add your first rider to assign deliveries.
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

function RiderInviteTools({
  inviteCode,
  onRegenerate,
  regenerating,
}: {
  inviteCode: string
  onRegenerate: () => Promise<unknown>
  regenerating: boolean
}) {
  const link = `${getAppUrl()}/rider/invite/${encodeURIComponent(inviteCode)}`

  async function copy(text: string) {
    await navigator.clipboard.writeText(text)
  }

  return (
    <div className="space-y-1">
      <div className="font-mono">{inviteCode}</div>
      <div className="flex flex-wrap gap-1">
        <Button type="button" size="sm" variant="outline" onClick={() => void copy(inviteCode)}>
          Copy code
        </Button>
        <Button type="button" size="sm" variant="outline" onClick={() => void copy(link)}>
          Copy link
        </Button>
        <Button type="button" size="sm" variant="outline" disabled={regenerating} onClick={() => void onRegenerate()}>
          New code
        </Button>
      </div>
    </div>
  )
}

function FormField({
  label,
  name,
  ...props
}: { label: string; name: string } & React.ComponentProps<'input'>) {
  return (
    <div className="space-y-2">
      <Label htmlFor={name}>{label}</Label>
      <Input id={name} name={name} {...props} />
    </div>
  )
}

function EmptyWorkspace() {
  return (
    <Card>
      <CardHeader>
        <CardTitle>No workspace</CardTitle>
        <CardDescription>Register or join a company to manage riders.</CardDescription>
      </CardHeader>
    </Card>
  )
}
