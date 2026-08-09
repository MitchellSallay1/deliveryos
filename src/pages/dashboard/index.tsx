import { useAuth } from '@/hooks/use-auth'
import { Card, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { OperationsDashboard } from '@/components/dashboard/OperationsDashboard'

export function DashboardPage() {
  const { context } = useAuth()
  const companyId = context?.activeCompanyId ?? null

  if (!companyId) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>No company workspace</CardTitle>
          <CardDescription>
            Complete registration or ask an owner to invite you.
          </CardDescription>
        </CardHeader>
      </Card>
    )
  }

  return <OperationsDashboard companyId={companyId} />
}
