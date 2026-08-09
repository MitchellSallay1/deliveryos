import { useQuery } from '@tanstack/react-query'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { useAuth } from '@/hooks/use-auth'
import { listBranches } from '@/services/operations-service'

export function BranchesPage() {
  const companyId = useAuth().context?.activeCompanyId ?? null
  const { data: branches = [], isLoading, error } = useQuery({
    queryKey: ['branches', companyId],
    queryFn: () => listBranches(companyId!),
    enabled: !!companyId,
  })

  return (
    <Card>
      <CardHeader>
        <CardTitle>Branches</CardTitle>
      </CardHeader>
      <CardContent className="text-sm">
        {isLoading && <p className="text-[var(--color-muted)]">Loading…</p>}
        {error && <p className="text-red-600">{error instanceof Error ? error.message : 'Error'}</p>}
        <ul>
          {(branches as { id: string; name: string; code: string; city: string | null }[]).map((b) => (
            <li key={b.id} className="border-b py-2">
              {b.name} · {b.code} {b.city ? `· ${b.city}` : ''}
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  )
}
