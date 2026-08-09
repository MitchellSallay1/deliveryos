import { describe, expect, it } from 'vitest'
import { ADMIN_NAV_GROUPS } from '@/lib/admin-nav'
import { defaultHomeForRole, permissionsForRole } from '@/lib/rbac'

describe('super admin control tower', () => {
  it('registers core admin routes in navigation', () => {
    const paths = ADMIN_NAV_GROUPS.flatMap((g) => g.items.map((i) => i.to))
    expect(paths).toContain('/admin')
    expect(paths).toContain('/admin/live')
    expect(paths).toContain('/admin/deliveries')
    expect(paths).toContain('/admin/companies')
    expect(paths).toContain('/admin/integrations/mtn')
  })

  it('routes super admin home to command center', () => {
    expect(defaultHomeForRole('super_admin')).toBe('/admin')
  })

  it('does not grant tenant delivery pages to super_admin rbac label alone', () => {
    const perms = permissionsForRole('super_admin')
    expect(perms.has('page:admin')).toBe(true)
    expect(perms.has('page:deliveries')).toBe(false)
  })

  it('CTA register/login paths unchanged for marketing', () => {
    expect(defaultHomeForRole('company_owner')).toBe('/dashboard')
    expect(defaultHomeForRole('rider')).toBe('/my-jobs')
  })
})
