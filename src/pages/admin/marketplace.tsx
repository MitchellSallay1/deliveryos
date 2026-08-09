import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { getMarketplaceAnalytics } from '@/services/marketplace-service'
import { supabase } from '@/lib/supabase/client'

export function AdminMarketplacePage() {
  const { data: platform, isLoading } = useQuery({
    queryKey: ['admin-marketplace-analytics'],
    queryFn: () => getMarketplaceAnalytics('platform'),
  })

  const qc = useQueryClient()
  const suspendMut = useMutation({
    mutationFn: async (fd: FormData) => {
      const companyId = String(fd.get('company_id'))
      const suspended = fd.get('suspended') === 'on'
      const { error } = await supabase.rpc('admin_set_marketplace_suspension', {
        p_company_id: companyId,
        p_suspended: suspended,
        p_disable_provider: fd.get('disable_provider') === 'on',
      })
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['admin-marketplace-analytics'] }),
  })

  return (
    <div className="space-y-6">
      <h2 className="text-xl font-semibold">Marketplace control</h2>
      {isLoading && <p className="text-sm text-[var(--color-muted)]">Loading metrics…</p>}
      {platform && (
        <div className="grid gap-4 sm:grid-cols-3">
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm">GMV</CardTitle>
            </CardHeader>
            <CardContent className="text-2xl font-semibold">
              LRD {Number(platform.gmv_lrd_cents ?? 0) / 100}
            </CardContent>
          </Card>
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm">Platform fees</CardTitle>
            </CardHeader>
            <CardContent className="text-2xl font-semibold">
              LRD {Number(platform.platform_fees_lrd_cents ?? 0) / 100}
            </CardContent>
          </Card>
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm">Acceptance rate</CardTitle>
            </CardHeader>
            <CardContent className="text-2xl font-semibold">
              {platform.acceptance_rate != null
                ? `${(Number(platform.acceptance_rate) * 100).toFixed(1)}%`
                : '—'}
            </CardContent>
          </Card>
        </div>
      )}

      <Card>
        <CardHeader>
          <CardTitle>Suspend marketplace access</CardTitle>
        </CardHeader>
        <CardContent>
          <form
            className="grid max-w-md gap-3"
            onSubmit={(e) => {
              e.preventDefault()
              suspendMut.mutate(new FormData(e.currentTarget))
            }}
          >
            <div className="space-y-2">
              <Label>Company ID</Label>
              <Input name="company_id" required />
            </div>
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" name="suspended" /> Marketplace suspended
            </label>
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" name="disable_provider" /> Disable provider network profile
            </label>
            <Button type="submit" disabled={suspendMut.isPending}>
              Apply
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}
