import { Badge } from '@/components/ui/Badge'
import { cn } from '@/lib/utils'

const STYLES: Record<string, string> = {
  healthy: 'bg-emerald-100 text-emerald-800',
  needs_attention: 'bg-amber-100 text-amber-900',
  at_risk: 'bg-red-100 text-red-800',
  not_configured: 'bg-zinc-100 text-zinc-700',
  degraded: 'bg-amber-100 text-amber-900',
  unavailable: 'bg-red-100 text-red-800',
}

export function AdminHealthBadge({ level }: { level: string }) {
  const label = level.replace(/_/g, ' ')
  return (
    <Badge className={cn('capitalize', STYLES[level] ?? 'bg-zinc-100 text-zinc-800')}>{label}</Badge>
  )
}

export function AdminHealthReasons({ reasons }: { reasons: string[] }) {
  if (!reasons?.length) return null
  return (
    <ul className="mt-2 list-inside list-disc text-sm text-[var(--color-muted)]">
      {reasons.map((r) => (
        <li key={r}>{r}</li>
      ))}
    </ul>
  )
}

export function compareHint(today: number, yesterday: number): string | undefined {
  if (yesterday === 0) return today > 0 ? 'New activity today' : undefined
  const pct = Math.round(((today - yesterday) / yesterday) * 100)
  if (pct === 0) return 'Same as yesterday'
  return `${pct > 0 ? '+' : ''}${pct}% vs yesterday`
}

export function formatLrd(cents: number): string {
  if (!cents) return 'LRD 0'
  return `LRD ${(cents / 100).toLocaleString(undefined, { maximumFractionDigits: 0 })}`
}
