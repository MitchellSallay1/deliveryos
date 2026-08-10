import { AlertCircle, RotateCw } from 'lucide-react'

/**
 * Per-widget failure state — never raw error text. Each dashboard card that
 * can fail renders this instead of taking the whole page down, with its own
 * retry action.
 */
export function WidgetError({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <div className="flex flex-col items-center justify-center gap-1.5 py-5 text-center">
      <AlertCircle className="h-4 w-4 text-amber-500" aria-hidden />
      <p className="text-sm text-[var(--color-muted)]">{message}</p>
      {onRetry && (
        <button
          type="button"
          onClick={onRetry}
          className="mt-0.5 inline-flex items-center gap-1.5 rounded-lg border px-3 py-1.5 text-xs font-medium text-[var(--color-foreground)] transition-colors hover:bg-zinc-50"
        >
          <RotateCw className="h-3.5 w-3.5" aria-hidden />
          Retry
        </button>
      )}
    </div>
  )
}
