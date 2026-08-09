import { lazy, Suspense } from 'react'

const AdminNetworkMap = lazy(() =>
  import('@/components/admin/AdminNetworkMap').then((m) => ({ default: m.AdminNetworkMap })),
)

export function AdminMapPage() {
  return (
    <Suspense fallback={<p className="text-sm text-[var(--color-muted)]">Loading map…</p>}>
      <AdminNetworkMap />
    </Suspense>
  )
}
