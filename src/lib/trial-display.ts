export type TrialSummary = {
  is_free_trial?: boolean
  status?: string
  trial_ends_at?: string | null
  days_remaining?: number | null
  expired?: boolean
}

export function formatTrialEndsAt(iso: string | null | undefined): string {
  if (!iso) return '—'
  return new Date(iso).toLocaleString(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  })
}

export function trialBannerMessage(trial: TrialSummary | null | undefined): {
  tone: 'info' | 'warning' | 'danger'
  headline: string
  detail: string
  showChoosePlan: boolean
} | null {
  if (!trial?.is_free_trial && !trial?.expired) return null

  if (trial.expired || trial.status === 'expired') {
    return {
      tone: 'danger',
      headline: 'Trial expired — choose a plan',
      detail:
        'Your 7-day free trial has ended. Choose a plan to continue creating deliveries and riders.',
      showChoosePlan: true,
    }
  }

  const days = trial.days_remaining ?? 0
  if (days <= 0) {
    return {
      tone: 'danger',
      headline: 'Trial expired — choose a plan',
      detail:
        'Your 7-day free trial has ended. Choose a plan to continue creating deliveries and riders.',
      showChoosePlan: true,
    }
  }

  if (days <= 1) {
    return {
      tone: 'warning',
      headline: '1 day remaining on your free trial',
      detail: `Trial ends ${formatTrialEndsAt(trial.trial_ends_at)}.`,
      showChoosePlan: true,
    }
  }

  if (days <= 3) {
    return {
      tone: 'warning',
      headline: `${days} days remaining on your free trial`,
      detail: `Trial ends ${formatTrialEndsAt(trial.trial_ends_at)}.`,
      showChoosePlan: true,
    }
  }

  return {
    tone: 'info',
    headline: 'Free trial',
    detail: `${days} days remaining · Trial ends ${formatTrialEndsAt(trial.trial_ends_at)}.`,
    showChoosePlan: true,
  }
}
