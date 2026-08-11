import { describe, expect, it } from 'vitest'
import { can, defaultHomeForRole, isNavVisibleForBusinessType, permissionsForRole } from '@/lib/rbac'

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

  it('grants Commerce vendor permissions to owner/dispatcher/support_staff but not rider or super_admin', () => {
    expect(can('company_owner', 'page:vendor')).toBe(true)
    expect(can('company_owner', 'page:vendor:write')).toBe(true)
    expect(can('dispatcher', 'page:vendor')).toBe(true)
    expect(can('dispatcher', 'page:vendor:write')).toBe(true)
    expect(can('support_staff', 'page:vendor')).toBe(true)
    expect(can('support_staff', 'action:vendor-order:fulfill')).toBe(true)
    // support_staff can fulfill orders but not manage the catalog/store.
    expect(can('support_staff', 'page:vendor:write')).toBe(false)
    expect(can('rider', 'page:vendor')).toBe(false)
    expect(can('super_admin', 'page:vendor')).toBe(false)
  })

  it('hides the vendor Commerce nav for a pure logistics_provider company, shows it for merchant and hybrid', () => {
    expect(isNavVisibleForBusinessType('page:vendor', 'logistics_provider')).toBe(false)
    expect(isNavVisibleForBusinessType('page:vendor', 'merchant')).toBe(true)
    expect(isNavVisibleForBusinessType('page:vendor', 'hybrid')).toBe(true)
  })
})
