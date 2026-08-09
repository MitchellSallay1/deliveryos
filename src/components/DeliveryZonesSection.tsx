import { useState } from 'react'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { useDeliveryZones } from '@/hooks/use-field-ops'
import { upsertDeliveryZone } from '@/services/field-ops-service'
import { formatLrdFromCents } from '@/utils/delivery-schemas'

export function DeliveryZonesSection({ companyId }: { companyId: string }) {
  const { data: zones = [], refetch } = useDeliveryZones(companyId)
  const [name, setName] = useState('')
  const [fee, setFee] = useState('500')
  const [error, setError] = useState<string | null>(null)

  async function addZone(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    try {
      await upsertDeliveryZone({
        company_id: companyId,
        name: name.trim(),
        base_fee_cents: Math.round(Number(fee) * 100) || 0,
        currency: 'LRD',
        is_active: true,
      })
      setName('')
      await refetch()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed')
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Delivery zones</CardTitle>
        <CardDescription>Fixed fees by zone — used when creating deliveries.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {error && <p className="text-sm text-red-600">{error}</p>}
        <ul className="text-sm">
          {(zones as { id: string; name: string; base_fee_cents: number; is_active: boolean }[]).map(
            (z) => (
              <li key={z.id} className="border-b py-2">
                {z.name} · {formatLrdFromCents(z.base_fee_cents)}
                {!z.is_active && ' (inactive)'}
              </li>
            ),
          )}
        </ul>
        <form className="flex flex-col gap-2 sm:flex-row sm:items-end" onSubmit={(e) => void addZone(e)}>
          <div className="flex-1 space-y-1">
            <Label htmlFor="zoneName">Zone name</Label>
            <Input id="zoneName" value={name} onChange={(e) => setName(e.target.value)} required />
          </div>
          <div className="w-32 space-y-1">
            <Label htmlFor="zoneFee">Base fee (LRD)</Label>
            <Input id="zoneFee" type="number" min={0} value={fee} onChange={(e) => setFee(e.target.value)} />
          </div>
          <Button type="submit">Add zone</Button>
        </form>
      </CardContent>
    </Card>
  )
}
