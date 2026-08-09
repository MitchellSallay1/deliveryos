import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { upsertProviderMarketplaceProfile } from '@/services/marketplace-service'
import { supabase } from '@/lib/supabase/client'

export function MarketplaceProviderSettings({ companyId }: { companyId: string }) {
  const qc = useQueryClient()

  const { data: profile, isLoading } = useQuery({
    queryKey: ['provider-marketplace-profile', companyId],
    queryFn: async () => {
      const { data, error } = await (
        supabase as { from: (table: string) => ReturnType<typeof supabase.from> }
      )
        .from('provider_marketplace_profiles')
        .select('*')
        .eq('company_id', companyId)
        .maybeSingle()
      if (error) throw error
      return data
    },
  })

  const save = useMutation({
    mutationFn: (fd: FormData) =>
      upsertProviderMarketplaceProfile({
        company_id: companyId,
        marketplace_enabled: fd.get('marketplace_enabled') === 'on',
        accepting_jobs: fd.get('accepting_jobs') === 'on',
        service_description: String(fd.get('service_description') || ''),
        service_phone: String(fd.get('service_phone') || ''),
        minimum_delivery_fee_lrd_cents: Math.round(
          Number(fd.get('minimum_fee_lrd') || 0) * 100,
        ),
      }),
    onSuccess: () =>
      void qc.invalidateQueries({ queryKey: ['provider-marketplace-profile', companyId] }),
  })

  if (isLoading) return null

  return (
    <Card>
      <CardHeader>
        <CardTitle>Delivery network (marketplace)</CardTitle>
        <CardDescription>
          Opt in to receive delivery requests from merchants on DeliveryOS. Participation is not
          automatic.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <form
          className="grid max-w-lg gap-3"
          onSubmit={(e) => {
            e.preventDefault()
            save.mutate(new FormData(e.currentTarget))
          }}
        >
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              name="marketplace_enabled"
              defaultChecked={profile?.marketplace_enabled ?? false}
            />
            Enable marketplace profile
          </label>
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              name="accepting_jobs"
              defaultChecked={profile?.accepting_jobs ?? false}
            />
            Accepting jobs
          </label>
          <div className="space-y-2">
            <Label>Service description</Label>
            <Input
              name="service_description"
              defaultValue={profile?.service_description ?? ''}
            />
          </div>
          <div className="space-y-2">
            <Label>Service phone</Label>
            <Input name="service_phone" defaultValue={profile?.service_phone ?? ''} />
          </div>
          <div className="space-y-2">
            <Label>Minimum fee (LRD)</Label>
            <Input
              name="minimum_fee_lrd"
              type="number"
              min={0}
              step="0.01"
              defaultValue={(profile?.minimum_delivery_fee_lrd_cents ?? 0) / 100}
            />
          </div>
          <Button type="submit" disabled={save.isPending}>
            Save marketplace settings
          </Button>
        </form>
      </CardContent>
    </Card>
  )
}
