import { useState } from 'react'
import { Download } from 'lucide-react'
import { Button } from '@/components/ui/Button'
import { usePwaInstall } from '@/hooks/use-pwa-install'
import { IosInstallSheet } from '@/components/pwa/IosInstallSheet'

type InstallButtonProps = {
  label?: string
  variant?: 'default' | 'accent' | 'outline' | 'ghost'
  size?: 'default' | 'sm' | 'lg'
  className?: string
  showIcon?: boolean
}

/**
 * The one shared install action, safe to place in any surface (marketing
 * CTA, dashboard header, mobile banner). Renders nothing once installed or
 * on a platform with no install path at all — callers never need their own
 * platform branching.
 */
export function InstallButton({ label = 'Install DeliveryOS', variant = 'accent', size = 'default', className, showIcon = true }: InstallButtonProps) {
  const { isStandalone, canPromptInstall, isIos, promptInstall } = usePwaInstall()
  const [iosSheetOpen, setIosSheetOpen] = useState(false)

  if (isStandalone) return null
  if (!canPromptInstall && !isIos) return null

  async function onClick() {
    if (canPromptInstall) {
      await promptInstall()
      return
    }
    if (isIos) setIosSheetOpen(true)
  }

  return (
    <>
      <Button type="button" variant={variant} size={size} className={className} onClick={() => void onClick()}>
        {showIcon && <Download className="mr-1.5 h-4 w-4" aria-hidden />}
        {label}
      </Button>
      <IosInstallSheet open={iosSheetOpen} onClose={() => setIosSheetOpen(false)} />
    </>
  )
}
