import { useState } from 'react'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import {
  createApiKey,
  listApiKeys,
  revokeApiKey,
  upsertWebhookEndpoint,
} from '@/services/field-ops-service'
import { useQuery, useQueryClient } from '@tanstack/react-query'

const WEBHOOK_EVENTS = [
  'delivery.created',
  'delivery.assigned',
  'delivery.picked_up',
  'delivery.in_transit',
  'delivery.delivered',
  'delivery.failed',
  'payment.collected',
]

export function IntegrationsSettingsSection({ companyId }: { companyId: string }) {
  const qc = useQueryClient()
  const { data: keys = [] } = useQuery({
    queryKey: ['api-keys', companyId],
    queryFn: () => listApiKeys(companyId),
  })

  const [newKeyName, setNewKeyName] = useState('Production API')
  const [createdKey, setCreatedKey] = useState<string | null>(null)
  const [webhookUrl, setWebhookUrl] = useState('')
  const [message, setMessage] = useState<string | null>(null)

  async function onCreateKey() {
    setMessage(null)
    const row = await createApiKey(companyId, newKeyName, [
      'delivery:create',
      'delivery:read',
      'tracking:read',
    ])
    setCreatedKey(String((row as { api_key?: string }).api_key ?? ''))
    void qc.invalidateQueries({ queryKey: ['api-keys', companyId] })
  }

  async function onAddWebhook(e: React.FormEvent) {
    e.preventDefault()
    setMessage(null)
    await upsertWebhookEndpoint({
      company_id: companyId,
      url: webhookUrl.trim(),
      events: WEBHOOK_EVENTS,
      is_active: true,
    })
    setWebhookUrl('')
    setMessage('Webhook endpoint saved. Dispatch via sms-dispatch / webhooks-dispatch Edge Functions.')
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle>API keys</CardTitle>
          <CardDescription>
            Keys are shown once. Use the `api-v1` Edge Function with header `X-API-Key`.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3 text-sm">
          <ul>
            {(keys as { id: string; name: string; key_prefix: string; is_active: boolean }[]).map(
              (k) => (
                <li key={k.id} className="flex items-center justify-between border-b py-2">
                  <span>
                    {k.name} · {k.key_prefix}…
                  </span>
                  {k.is_active && (
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => void revokeApiKey(k.id).then(() => qc.invalidateQueries({ queryKey: ['api-keys', companyId] }))}
                    >
                      Revoke
                    </Button>
                  )}
                </li>
              ),
            )}
          </ul>
          <div className="flex flex-col gap-2 sm:flex-row sm:items-end">
            <div className="flex-1 space-y-1">
              <Label htmlFor="keyName">Key name</Label>
              <Input id="keyName" value={newKeyName} onChange={(e) => setNewKeyName(e.target.value)} />
            </div>
            <Button type="button" onClick={() => void onCreateKey()}>
              Create key
            </Button>
          </div>
          {createdKey && (
            <p className="rounded border bg-amber-50 p-2 text-xs text-amber-900">
              Copy now: <code className="break-all">{createdKey}</code>
            </p>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Webhooks</CardTitle>
          <CardDescription>HMAC-signed POST payloads — see docs/WEBHOOKS.md</CardDescription>
        </CardHeader>
        <CardContent>
          <form className="flex flex-col gap-2 sm:flex-row" onSubmit={(e) => void onAddWebhook(e)}>
            <Input
              placeholder="https://example.com/webhooks/deliveryos"
              value={webhookUrl}
              onChange={(e) => setWebhookUrl(e.target.value)}
              required
            />
            <Button type="submit">Save endpoint</Button>
          </form>
          {message && <p className="mt-2 text-xs text-[var(--color-muted)]">{message}</p>}
        </CardContent>
      </Card>
    </div>
  )
}
