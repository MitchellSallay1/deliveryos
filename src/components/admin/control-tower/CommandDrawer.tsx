import { X } from 'lucide-react'
import { cn } from '@/lib/utils'

export type CommandDrawerProps = {
  open: boolean
  onClose: () => void
  title: string
  description?: string
  children: React.ReactNode
  className?: string
}

/** Dark slide-over panel for admin detail views — the control-tower equivalent of the tenant Sheet, kept separate so the tenant dashboard is never touched. */
export function CommandDrawer({ open, onClose, title, description, children, className }: CommandDrawerProps) {
  if (!open) return null

  return (
    <div className="fixed inset-0 z-[100] flex justify-end" role="dialog" aria-modal="true" aria-labelledby="command-drawer-title">
      <button
        type="button"
        className="absolute inset-0 bg-black/70 backdrop-blur-[1px]"
        aria-label="Close panel"
        onClick={onClose}
      />
      <div
        className={cn(
          'relative flex h-full w-full max-w-lg flex-col border-l border-white/10 bg-[#131316] shadow-2xl',
          className,
        )}
      >
        <div className="flex items-start justify-between gap-3 border-b border-white/[0.08] px-5 py-4">
          <div className="min-w-0">
            <h2 id="command-drawer-title" className="text-sm font-semibold text-white">
              {title}
            </h2>
            {description && <p className="mt-0.5 text-xs text-zinc-500">{description}</p>}
          </div>
          <button
            type="button"
            aria-label="Close"
            onClick={onClose}
            className="shrink-0 rounded-lg p-1.5 text-zinc-400 hover:bg-white/5 hover:text-white"
          >
            <X className="h-4 w-4" />
          </button>
        </div>
        <div className="flex-1 overflow-y-auto px-5 py-4">{children}</div>
      </div>
    </div>
  )
}
