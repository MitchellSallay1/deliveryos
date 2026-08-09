import { Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { supabase } from '@/lib/supabase/client'

type Step = { key: string; done: boolean; href: string }

export function OnboardingChecklist({ companyId }: { companyId: string }) {
  const { data, isLoading } = useQuery({
    queryKey: ['onboarding', companyId],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_company_onboarding_status', {
        p_company_id: companyId,
      })
      if (error) throw error
      return data as { steps: Step[]; business_type: string }
    },
  })

  if (isLoading || !data?.steps?.length) return null
  const pending = data.steps.filter((s) => !s.done)
  if (pending.length === 0) return null

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base">Getting started</CardTitle>
      </CardHeader>
      <CardContent>
        <ul className="space-y-2 text-sm">
          {pending.map((step) => (
            <li key={step.key} className="flex items-center justify-between gap-2">
              <span className="capitalize text-[var(--color-muted)]">{step.key.replace(/_/g, ' ')}</span>
              <Link to={step.href} className="text-[var(--color-primary)] hover:underline">
                Continue
              </Link>
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  )
}
