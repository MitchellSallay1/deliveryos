import { cn } from '@/lib/utils'
import { useBranding } from '@/branding/BrandingProvider'

type BrandLogoProps = {
  className?: string
  variant?: 'light' | 'dark'
  showPartner?: boolean
}

export function BrandLogo({ className, variant = 'dark', showPartner = true }: BrandLogoProps) {
  const brand = useBranding()
  const isLight = variant === 'light'

  return (
    <div className={cn('flex flex-col gap-1', className)}>
      <div className="flex items-center gap-2">
        <span
          className={cn(
            'flex h-9 w-9 items-center justify-center rounded-lg text-sm font-bold tracking-tight',
            isLight ? 'bg-[var(--color-accent)] text-black' : 'bg-[var(--color-accent)] text-black',
          )}
          aria-hidden
        >
          DO
        </span>
        <div>
          <p
            className={cn(
              'text-base font-semibold leading-tight tracking-tight',
              isLight ? 'text-white' : 'text-[var(--color-foreground)]',
            )}
          >
            {brand.productName}
          </p>
          {showPartner && brand.partner && (
            <p
              className={cn(
                'text-[10px] font-medium uppercase tracking-widest',
                isLight ? 'text-white/70' : 'text-[var(--color-muted)]',
              )}
            >
              {brand.partner.poweredByLabel}
            </p>
          )}
        </div>
      </div>
    </div>
  )
}

export function MtnMark({ className }: { className?: string }) {
  return (
    <span
      className={cn(
        'inline-flex items-center rounded-md bg-[#FFCB05] px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide text-black',
        className,
      )}
      title="MTN"
    >
      MTN
    </span>
  )
}

export function PoweredByPartner({ className }: { className?: string }) {
  const brand = useBranding()
  if (!brand.partner) return null
  return (
    <p className={cn('flex items-center justify-center gap-2 text-xs text-[var(--color-muted)]', className)}>
      <span>{brand.partner.poweredByLabel}</span>
      {brand.partner.id === 'mtn' && <MtnMark />}
    </p>
  )
}
