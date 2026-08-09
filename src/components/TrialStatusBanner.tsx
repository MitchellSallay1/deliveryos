import { Link } from 'react-router-dom'
import { useAuth } from '@/hooks/use-auth'
import { useCompanyUsage } from '@/hooks/use-billing'
import { trialBannerMessage, type TrialSummary } from '@/lib/trial-display'
import { Button } from '@/components/ui/Button'
import { cn } from '@/lib/utils'

export function TrialStatusBanner() {
  const { context } = useAuth()
  const companyId = context?.activeCompanyId
  const { data: usage } = useCompanyUsage(companyId ?? null)

  if (!companyId) return null

  const trial = (usage as { trial?: TrialSummary } | undefined)?.trial
  const message = trialBannerMessage(trial)
  if (!message) return null

  return (
    <div
      className={cn(
        'mb-4 rounded-lg border px-4 py-3 text-sm',
        message.tone === 'info' && 'border-sky-200 bg-sky-50 text-sky-950',
        message.tone === 'warning' && 'border-amber-200 bg-amber-50 text-amber-950',
        message.tone === 'danger' && 'border-red-200 bg-red-50 text-red-950',
      )}
    >
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <p className="font-medium">{message.headline}</p>
          <p className="text-[var(--color-muted)]">{message.detail}</p>
        </div>
        {message.showChoosePlan && (
          <Link to="/billing">
            <Button type="button" size="sm" variant={message.tone === 'danger' ? 'default' : 'outline'}>
              Choose plan
            </Button>
          </Link>
        )}
      </div>
    </div>
  )
}
