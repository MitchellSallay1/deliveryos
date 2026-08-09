import { describe, expect, it } from 'vitest'
import { can, defaultHomeForRole, permissionsForRole } from '@/lib/rbac'

describe('rbac', () => {
  it('grants dispatcher delivery write permissions', () => {
    expect(can('dispatcher', 'action:delivery:create')).toBe(true)
    expect(can('dispatcher', 'page:team')).toBe(false)
  })

  it('restricts rider to my-jobs and settings', () => {
    const perms = permissionsForRole('rider')
    expect(perms.has('page:my-jobs')).toBe(true)
    expect(perms.has('page:deliveries')).toBe(false)
  })

  it('routes super admin home to admin portal', () => {
    expect(defaultHomeForRole('super_admin')).toBe('/admin')
    expect(defaultHomeForRole('rider')).toBe('/my-jobs')
  })
})
