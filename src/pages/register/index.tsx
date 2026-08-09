import { Link } from 'react-router-dom'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'

export function RegisterLandingPage() {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Welcome to DeliveryOS</CardTitle>
        <CardDescription>How will you use DeliveryOS?</CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        <PersonaOption
          to="/register/company"
          title="I own a delivery company"
          description="Create a courier workspace, dispatch deliveries, and manage riders."
        />
        <PersonaOption
          to="/register/merchant"
          title="I own a business that needs deliveries"
          description="Create a merchant workspace and request deliveries from providers."
        />
        <PersonaOption
          to="/register/rider"
          title="I'm a rider"
          description="Sign up with email only, then link your rider profile from your company."
        />
        <p className="pt-2 text-center text-sm text-[var(--color-muted)]">
          Already have an account?{' '}
          <Link to="/login" className="text-[var(--color-primary)] hover:underline">
            Sign in
          </Link>
        </p>
      </CardContent>
    </Card>
  )
}

function PersonaOption({
  to,
  title,
  description,
}: {
  to: string
  title: string
  description: string
}) {
  return (
    <Link
      to={to}
      className="block rounded-lg border px-4 py-3 transition-colors hover:border-[var(--color-primary)] hover:bg-slate-50"
    >
      <p className="font-medium">{title}</p>
      <p className="text-sm text-[var(--color-muted)]">{description}</p>
    </Link>
  )
}
