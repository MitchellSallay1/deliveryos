import { Link } from 'react-router-dom'
import { AlertTriangle, CheckCircle2, ChevronRight } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { cn } from '@/lib/utils'
import type { AttentionItem } from '@/lib/dashboard-metrics'

export function AttentionCenter({ items }: { items: AttentionItem[] }) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base">Needs attention</CardTitle>
      </CardHeader>
      <CardContent>
        {items.length === 0 ? (
          <div className="flex items-center gap-2.5 py-2 text-sm text-emerald-800">
            <CheckCircle2 className="h-4 w-4 shrink-0 text-emerald-600" aria-hidden />
            Everything looks good. No operational issues need your attention.
          </div>
        ) : (
          <ul className="divide-y">
            {items.map((item) => (
              <li key={item.key}>
                <Link
                  to={item.href}
                  className="flex items-center justify-between gap-3 py-2.5 text-sm transition-colors hover:bg-zinc-50 -mx-1 px-1 rounded-md"
                >
                  <div className="flex min-w-0 items-start gap-2.5">
                    <AlertTriangle
                      className={cn(
                        'mt-0.5 h-4 w-4 shrink-0',
                        item.severity === 'critical' ? 'text-red-500' : 'text-amber-500',
                      )}
                      aria-hidden
                    />
                    <div className="min-w-0">
                      <p className="font-medium text-[var(--color-foreground)]">{item.label}</p>
                      <p className="text-xs text-[var(--color-muted)]">{item.detail}</p>
                    </div>
                  </div>
                  <ChevronRight className="h-4 w-4 shrink-0 text-[var(--color-muted)]" aria-hidden />
                </Link>
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  )
}
