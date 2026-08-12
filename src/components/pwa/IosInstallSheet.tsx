import { Plus, Share } from 'lucide-react'
import { Sheet } from '@/components/ui/Sheet'

export function IosInstallSheet({ open, onClose }: { open: boolean; onClose: () => void }) {
  return (
    <Sheet open={open} onClose={onClose} title="Install DeliveryOS" description="Add DeliveryOS to your Home Screen for one-tap access.">
      <ol className="space-y-4 text-sm">
        <li className="flex items-start gap-3">
          <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-[var(--color-accent)] text-xs font-semibold text-black">
            1
          </span>
          <span className="flex items-center gap-1.5 pt-0.5">
            Tap the <Share className="inline h-4 w-4" aria-hidden /> <strong>Share</strong> button in Safari's toolbar.
          </span>
        </li>
        <li className="flex items-start gap-3">
          <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-[var(--color-accent)] text-xs font-semibold text-black">
            2
          </span>
          <span className="pt-0.5">
            Scroll down and choose <strong>Add to Home Screen</strong>.
          </span>
        </li>
        <li className="flex items-start gap-3">
          <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-[var(--color-accent)] text-xs font-semibold text-black">
            3
          </span>
          <span className="flex items-center gap-1.5 pt-0.5">
            Tap <strong>Add</strong> <Plus className="inline h-4 w-4" aria-hidden /> in the top corner.
          </span>
        </li>
      </ol>
    </Sheet>
  )
}
