import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  CommandButton,
  CommandCard,
  CommandCardBody,
  CommandCardHeader,
  CommandInput,
  CommandKpi,
  SectionHeader,
} from '@/components/admin/control-tower'
import { getMarketplaceAnalytics } from '@/services/marketplace-service'
import { supabase } from '@/lib/supabase/client'

export function AdminMarketplacePage() {
  const { data: platform, isLoading } = useQuery({
    queryKey: ['admin-marketplace-analytics'],
    queryFn: () => getMarketplaceAnalytics('platform'),
  })

  const [suspending, setSuspending] = useState(false)
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
      return suspended
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['admin-marketplace-analytics'] }),
  })

  return (
    <div className="space-y-4">
      <SectionHeader eyebrow="Marketplace" title="Marketplace control" className="mb-0" />

      {isLoading && <p className="text-sm text-zinc-500">Loading metrics…</p>}

      {platform && (
        <div className="grid gap-3 sm:grid-cols-3">
          <CommandKpi label="GMV" value={`LRD ${Number(platform.gmv_lrd_cents ?? 0) / 100}`} />
          <CommandKpi label="Platform fees" value={`LRD ${Number(platform.platform_fees_lrd_cents ?? 0) / 100}`} />
          <CommandKpi
            label="Acceptance rate"
            value={platform.acceptance_rate != null ? `${(Number(platform.acceptance_rate) * 100).toFixed(1)}%` : '—'}
          />
        </div>
      )}

      <CommandCard className="max-w-lg">
        <CommandCardHeader title="Suspend marketplace access" description="Applies immediately to the given company" />
        <CommandCardBody>
          <form
            className="grid gap-3"
            onSubmit={(e) => {
              e.preventDefault()
              suspendMut.mutate(new FormData(e.currentTarget))
            }}
          >
            <div className="space-y-1.5">
              <label className="text-xs font-medium text-zinc-400">Company ID</label>
              <CommandInput name="company_id" required />
            </div>
            <label className="flex items-center gap-2 text-sm text-zinc-300">
              <input
                type="checkbox"
                name="suspended"
                className="accent-[#FFCB05]"
                onChange={(e) => setSuspending(e.target.checked)}
              />{' '}
              Marketplace suspended
            </label>
            <label className="flex items-center gap-2 text-sm text-zinc-300">
              <input type="checkbox" name="disable_provider" className="accent-[#FFCB05]" /> Disable provider network profile
            </label>
            <CommandButton type="submit" variant={suspending ? 'destructive' : 'primary'} disabled={suspendMut.isPending}>
              {suspendMut.isPending ? 'Applying…' : 'Apply'}
            </CommandButton>
          </form>
        </CommandCardBody>
      </CommandCard>
    </div>
  )
}
