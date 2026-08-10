import type { ReactNode } from 'react'
import { cn } from '@/lib/utils'

export function CommandTable({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <div className={cn('overflow-x-auto', className)}>
      <table className="w-full border-collapse text-sm">{children}</table>
    </div>
  )
}

export function CommandTableHead({ children }: { children: ReactNode }) {
  return (
    <thead>
      <tr className="border-b border-white/[0.06] text-left text-[11px] uppercase tracking-wide text-zinc-500">
        {children}
      </tr>
    </thead>
  )
}

export function CommandTh({ children, className }: { children: ReactNode; className?: string }) {
  return <th className={cn('px-3 py-2 font-medium', className)}>{children}</th>
}

export function CommandTr({
  children,
  className,
  onClick,
}: {
  children: ReactNode
  className?: string
  onClick?: () => void
}) {
  return (
    <tr
      className={cn(
        'border-b border-white/[0.04] text-zinc-300',
        onClick && 'cursor-pointer hover:bg-white/[0.03]',
        className,
      )}
      onClick={onClick}
    >
      {children}
    </tr>
  )
}

export function CommandTd({ children, className }: { children: ReactNode; className?: string }) {
  return <td className={cn('px-3 py-2.5', className)}>{children}</td>
}

export function CommandEmptyState({ label }: { label: string }) {
  return (
    <div className="flex flex-col items-center justify-center gap-1 px-4 py-10 text-center">
      <p className="text-sm text-zinc-500">{label}</p>
    </div>
  )
}
