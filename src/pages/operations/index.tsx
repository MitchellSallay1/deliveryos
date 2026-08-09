import { Link } from 'react-router-dom'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { useAuth } from '@/hooks/use-auth'

const modules = [
  { to: '/operations/branches', title: 'Branches', desc: 'Locations & branch-aware dispatch' },
  { to: '/operations/fleet', title: 'Fleet', desc: 'Vehicles, maintenance, expenses' },
  { to: '/operations/warehouses', title: 'Warehouses', desc: 'Hubs and storage locations' },
  { to: '/operations/inventory', title: 'Inventory', desc: 'SKU catalog and stock levels' },
  { to: '/operations/inventory/movements', title: 'Stock movements', desc: 'Immutable inventory ledger' },
  { to: '/operations/cash-settlements', title: 'COD settlements', desc: 'Rider cash reconciliation' },
]

export function OperationsHubPage() {
  const { context } = useAuth()
  const companyId = context?.activeCompanyId

  if (!companyId) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Operations</CardTitle>
          <CardDescription>Select a company workspace.</CardDescription>
        </CardHeader>
      </Card>
    )
  }

  return (
    <div className="space-y-4">
      <div>
        <h2 className="text-xl font-semibold">Operations</h2>
        <p className="text-sm text-[var(--color-muted)]">
          Fleet, inventory, and COD tools — gated by your subscription plan.
        </p>
      </div>
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {modules.map((m) => (
          <Link key={m.to} to={m.to}>
            <Card className="h-full transition hover:border-[var(--color-primary)]">
              <CardHeader>
                <CardTitle className="text-base">{m.title}</CardTitle>
                <CardDescription>{m.desc}</CardDescription>
              </CardHeader>
              <CardContent />
            </Card>
          </Link>
        ))}
      </div>
    </div>
  )
}
