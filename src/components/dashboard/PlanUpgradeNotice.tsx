import { Link } from 'react-router-dom'
import { Lock } from 'lucide-react'

/**
 * A known, predictable "not on your plan" state — distinct from WidgetError.
 * Never shows Retry (retrying can't fix a plan gate) and never queries
 * anything that's already known to be gated.
 */
export function PlanUpgradeNotice({ message }: { message: string }) {
  return (
    <div className="flex flex-col items-center justify-center gap-2 py-5 text-center">
      <Lock className="h-4 w-4 text-[var(--color-muted)]" aria-hidden />
      <p className="max-w-xs text-sm text-[var(--color-muted)]">{message}</p>
      <Link
        to="/billing"
        className="mt-0.5 inline-flex items-center rounded-lg border px-3 py-1.5 text-xs font-medium text-[var(--color-foreground)] transition-colors hover:bg-zinc-50"
      >
        View plans
      </Link>
    </div>
  )
}
