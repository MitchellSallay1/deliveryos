import { useEffect, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { CommandButton, CommandCard, CommandCardBody, CommandCardHeader, CommandInput, SectionHeader, StatusChip } from '@/components/admin/control-tower'
import { fetchPlatformSettings, setPlatformSetting } from '@/services/platform-settings-service'
import { parseSupabaseError } from '@/lib/supabase-errors'

const JOBS = [
  { name: 'SMS dispatch', edge: 'sms-dispatch', note: 'Processes sms_outbox' },
  { name: 'Email dispatch', edge: 'email-dispatch', note: 'Processes email_outbox' },
  { name: 'Webhook dispatch', edge: 'webhooks-dispatch', note: 'Retries webhook_deliveries' },
  { name: 'Scheduler', edge: 'jobs-scheduler', note: 'Trial expiry, offer expiry, GPS purge' },
]

export function AdminJobsPage() {
  return (
    <div className="space-y-4">
      <SectionHeader eyebrow="Platform configuration" title="Scheduled jobs" className="mb-0" />
      <CommandCard>
        <CommandCardHeader description="Operational visibility is limited to queue counts until Edge Function telemetry is wired. Use System Health for pending/failed counts." />
        <CommandCardBody>
          <ul className="space-y-2">
            {JOBS.map((j) => (
              <li key={j.name} className="rounded-lg border border-white/[0.06] p-3 text-sm">
                <p className="font-medium text-zinc-100">{j.name}</p>
                <p className="text-xs text-zinc-500">
                  <span className="font-mono">{j.edge}</span> — {j.note}
                </p>
              </li>
            ))}
          </ul>
        </CommandCardBody>
      </CommandCard>
    </div>
  )
}

function PublicAppUrlSetting() {
  const qc = useQueryClient()
  const { data: settings, isLoading } = useQuery({
    queryKey: ['admin-platform-settings'],
    queryFn: fetchPlatformSettings,
  })
  const current = settings?.find((s) => s.key === 'public_app_url')
  const [value, setValue] = useState('')
  const [message, setMessage] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (current) setValue(current.value ?? '')
  }, [current])

  const save = useMutation({
    mutationFn: (v: string) => setPlatformSetting('public_app_url', v),
    onSuccess: () => {
      setMessage('Saved.')
      setError(null)
      void qc.invalidateQueries({ queryKey: ['admin-platform-settings'] })
    },
    onError: (err) => {
      setMessage(null)
      setError(parseSupabaseError(err))
    },
  })

  return (
    <CommandCard>
      <CommandCardHeader
        title="Public app URL"
        description="The production app origin (e.g. https://app.example.com, no trailing slash) used to build customer-facing links, such as the delivery-tracking link in status SMS. Not a secret — never stored here is anything sensitive. Leave empty to omit tracking links from SMS entirely rather than send a broken one."
      />
      <CommandCardBody className="space-y-3">
        {isLoading ? (
          <p className="text-sm text-zinc-500">Loading…</p>
        ) : (
          <>
            <CommandInput
              className="max-w-md"
              placeholder="https://app.example.com"
              value={value}
              onChange={(e) => setValue(e.target.value)}
            />
            <div className="flex items-center gap-3">
              <CommandButton
                variant="primary"
                disabled={save.isPending}
                onClick={() => void save.mutateAsync(value)}
              >
                {save.isPending ? 'Saving…' : 'Save'}
              </CommandButton>
              {message && <span className="text-sm text-emerald-400">{message}</span>}
              {error && <span className="text-sm text-red-400">{error}</span>}
            </div>
            {current?.updated_at && (
              <p className="text-xs text-zinc-500">Last updated {new Date(current.updated_at).toLocaleString()}</p>
            )}
          </>
        )}
      </CommandCardBody>
    </CommandCard>
  )
}

function MtnMomoActivationSetting() {
  const qc = useQueryClient()
  const { data: settings, isLoading } = useQuery({
    queryKey: ['admin-platform-settings'],
    queryFn: fetchPlatformSettings,
  })
  const current = settings?.find((s) => s.key === 'mtn_momo_collections_enabled')
  const enabled = current?.value === 'true'
  const [message, setMessage] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  const save = useMutation({
    mutationFn: (v: 'true' | 'false') => setPlatformSetting('mtn_momo_collections_enabled', v),
    onSuccess: (_, v) => {
      setMessage(v === 'true' ? 'MTN MoMo collection is now live.' : 'MTN MoMo collection is now disabled.')
      setError(null)
      void qc.invalidateQueries({ queryKey: ['admin-platform-settings'] })
    },
    onError: (err) => {
      setMessage(null)
      setError(parseSupabaseError(err))
    },
  })

  return (
    <CommandCard>
      <CommandCardHeader
        title="MTN MoMo collection — real-money kill switch"
        description="Defaults to disabled. While disabled, no new MTN MoMo payment attempt can be created — by any customer, through any path, including a direct API call — regardless of a store's own commerce settings. Existing pending/unknown/successful payment attempts remain visible and reconcilable at /admin/commerce-payments either way. Requires WINAGGREGATOR_MTN_* credentials to also be configured — enabling this alone does not collect money if credentials are missing."
      />
      <CommandCardBody className="space-y-3">
        {isLoading ? (
          <p className="text-sm text-zinc-500">Loading…</p>
        ) : (
          <>
            <div className="flex items-center gap-3">
              <StatusChip color={enabled ? 'green' : 'gray'} label={enabled ? 'live' : 'disabled'} />
              <CommandButton
                variant={enabled ? 'outline' : 'primary'}
                disabled={save.isPending}
                onClick={() => void save.mutateAsync(enabled ? 'false' : 'true')}
              >
                {save.isPending ? 'Saving…' : enabled ? 'Disable MTN MoMo collection' : 'Enable MTN MoMo collection'}
              </CommandButton>
              {message && <span className="text-sm text-emerald-400">{message}</span>}
              {error && <span className="text-sm text-red-400">{error}</span>}
            </div>
            {current?.updated_at && (
              <p className="text-xs text-zinc-500">Last changed {new Date(current.updated_at).toLocaleString()}</p>
            )}
          </>
        )}
      </CommandCardBody>
    </CommandCard>
  )
}

export function AdminConfigurationPage() {
  return (
    <div className="space-y-4">
      <SectionHeader eyebrow="Platform configuration" title="Configuration" className="mb-0" />
      <MtnMomoActivationSetting />
      <PublicAppUrlSetting />
      <CommandCard>
        <CommandCardHeader description="Safe display settings only. Trial duration and feature gates remain database-driven via plans. Secrets are not editable here." />
        <CommandCardBody className="text-sm text-zinc-400">
          <p>Support contact and maintenance banner hooks can be added via the platform_settings table in a future migration.</p>
        </CommandCardBody>
      </CommandCard>
    </div>
  )
}
