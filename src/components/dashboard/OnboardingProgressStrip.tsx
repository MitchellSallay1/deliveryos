import { Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { ArrowRight } from 'lucide-react'
import { supabase } from '@/lib/supabase/client'
import { onboardingProgressLabel } from '@/lib/dashboard-metrics'

type Step = { key: string; done: boolean; href: string }

/**
 * Compact onboarding progress — replaces the old full-width "Getting
 * started" card that occupied prime dashboard space permanently. Collapses
 * to nothing automatically once every step is done (same underlying data
 * as before, just a much smaller footprint while incomplete).
 */
export function OnboardingProgressStrip({ companyId }: { companyId: string }) {
  const { data } = useQuery({
    queryKey: ['onboarding', companyId],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_company_onboarding_status', {
        p_company_id: companyId,
      })
      if (error) throw error
      return data as { steps: Step[]; business_type: string }
    },
  })

  if (!data?.steps?.length) return null
  const pending = data.steps.filter((s) => !s.done)
  if (pending.length === 0) return null

  const total = data.steps.length
  const completed = total - pending.length
  const pct = Math.round((completed / total) * 100)
  const nextStep = pending[0]

  return (
    <div className="flex flex-col gap-2 rounded-xl border bg-white px-4 py-3 sm:flex-row sm:items-center sm:justify-between">
      <div className="flex-1">
        <div className="flex items-center justify-between gap-3 sm:justify-start">
          <p className="text-sm font-medium text-[var(--color-foreground)]">
            {onboardingProgressLabel(completed, total)}
          </p>
        </div>
        <div className="mt-1.5 h-1.5 w-full max-w-xs overflow-hidden rounded-full bg-zinc-100">
          <div
            className="h-full rounded-full bg-[var(--color-accent)] transition-all"
            style={{ width: `${Math.max(6, pct)}%` }}
          />
        </div>
      </div>
      <Link
        to={nextStep.href}
        className="inline-flex shrink-0 items-center gap-1 text-sm font-medium text-[var(--color-primary)] hover:underline"
      >
        Continue <ArrowRight className="h-3.5 w-3.5" aria-hidden />
      </Link>
    </div>
  )
}
