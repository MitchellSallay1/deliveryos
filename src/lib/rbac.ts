import type { CompanyRole } from '@/types/supabase'
import type { CompanyBusinessType } from '@/services/marketplace-service'

export type AppRole = CompanyRole | 'super_admin'

export type RouteKey =
  | 'dashboard'
  | 'deliveries'
  | 'riders'
  | 'customers'
  | 'reports'
  | 'notifications'
  | 'settings'
  | 'team'
  | 'my-jobs'
  | 'admin'
  | 'admin-companies'

export type Permission =
  | 'page:dashboard'
  | 'page:deliveries'
  | 'page:deliveries:write'
  | 'page:riders'
  | 'page:riders:write'
  | 'page:customers'
  | 'page:customers:write'
  | 'page:reports'
  | 'page:notifications'
  | 'page:settings'
  | 'page:settings:company'
  | 'page:settings:integrations'
  | 'page:team'
  | 'page:team:manage'
  | 'page:my-jobs'
  | 'page:rider-profile'
  | 'page:live-map'
  | 'page:operations'
  | 'page:merchant-requests'
  | 'page:marketplace-jobs'
  | 'page:marketplace-providers'
  | 'page:billing'
  | 'page:vendor'
  | 'page:vendor:write'
  | 'page:admin'
  | 'page:admin-companies'
  | 'page:admin-marketplace'
  | 'action:delivery:create'
  | 'action:delivery:assign'
  | 'action:delivery:transition'
  | 'action:photo:upload'
  | 'action:payment:deposit'
  | 'action:vendor-order:fulfill'

const ROLE_PERMISSIONS: Record<AppRole, Permission[]> = {
  super_admin: [
    'page:admin',
    'page:admin-companies',
    'page:admin-marketplace',
    'page:dashboard',
    'page:settings',
  ],
  company_owner: [
    'page:dashboard',
    'page:deliveries',
    'page:deliveries:write',
    'page:riders',
    'page:riders:write',
    'page:customers',
    'page:customers:write',
    'page:reports',
    'page:notifications',
    'page:settings',
    'page:settings:company',
    'page:settings:integrations',
    'page:team',
    'page:team:manage',
    'page:live-map',
    'page:operations',
    'page:merchant-requests',
    'page:marketplace-jobs',
    'page:marketplace-providers',
    'page:billing',
    'page:vendor',
    'page:vendor:write',
    'action:delivery:create',
    'action:delivery:assign',
    'action:delivery:transition',
    'action:photo:upload',
    'action:payment:deposit',
    'action:vendor-order:fulfill',
  ],
  dispatcher: [
    'page:dashboard',
    'page:deliveries',
    'page:deliveries:write',
    'page:riders',
    'page:riders:write',
    'page:customers',
    'page:customers:write',
    'page:reports',
    'page:notifications',
    'page:settings',
    'page:live-map',
    'page:operations',
    'page:merchant-requests',
    'page:marketplace-jobs',
    'page:marketplace-providers',
    'page:vendor',
    'page:vendor:write',
    'action:delivery:create',
    'action:delivery:assign',
    'action:delivery:transition',
    'action:photo:upload',
    'action:payment:deposit',
    'action:vendor-order:fulfill',
  ],
  support_staff: [
    'page:dashboard',
    'page:deliveries',
    'page:customers',
    'page:customers:write',
    'page:reports',
    'page:notifications',
    'page:settings',
    'page:vendor',
    'action:vendor-order:fulfill',
  ],
  rider: ['page:my-jobs', 'page:rider-profile', 'action:photo:upload', 'action:delivery:transition'],
}

export const ROUTE_PERMISSIONS: Record<string, Permission> = {
  '/dashboard': 'page:dashboard',
  '/deliveries': 'page:deliveries',
  '/riders': 'page:riders',
  '/customers': 'page:customers',
  '/reports': 'page:reports',
  '/notifications': 'page:notifications',
  '/settings': 'page:settings',
  '/team': 'page:team',
  '/my-jobs': 'page:my-jobs',
  '/rider/profile': 'page:rider-profile',
  '/live-map': 'page:live-map',
  '/operations': 'page:operations',
  '/merchant/requests': 'page:merchant-requests',
  '/marketplace/jobs': 'page:marketplace-jobs',
  '/marketplace/providers': 'page:marketplace-providers',
  '/billing': 'page:billing',
  '/vendor': 'page:vendor',
  '/admin': 'page:admin',
  '/admin/companies': 'page:admin-companies',
  '/admin/marketplace': 'page:admin-marketplace',
}

const LOGISTICS_ONLY_PERMISSIONS: Permission[] = [
  'page:riders',
  'page:live-map',
  'page:operations',
]

const MERCHANT_PORTAL_PERMISSIONS: Permission[] = [
  'page:merchant-requests',
  'page:marketplace-providers',
]

/** Commerce vendor portal — visible for merchant and hybrid companies, hidden for pure logistics_provider (mirrors MERCHANT_PORTAL_PERMISSIONS). */
const VENDOR_PORTAL_PERMISSIONS: Permission[] = [
  'page:vendor',
  'page:vendor:write',
  'action:vendor-order:fulfill',
]

export function isNavVisibleForBusinessType(
  permission: Permission,
  businessType: CompanyBusinessType | null | undefined,
): boolean {
  const t = businessType ?? 'logistics_provider'
  if (t === 'merchant') {
    return !LOGISTICS_ONLY_PERMISSIONS.includes(permission)
  }
  if (t === 'logistics_provider') {
    return !MERCHANT_PORTAL_PERMISSIONS.includes(permission) && !VENDOR_PORTAL_PERMISSIONS.includes(permission)
  }
  return true
}

export function permissionsForRole(role: AppRole | null): Set<Permission> {
  if (!role) return new Set()
  return new Set(ROLE_PERMISSIONS[role] ?? [])
}

export function can(role: AppRole | null, permission: Permission): boolean {
  return permissionsForRole(role).has(permission)
}

export function defaultHomeForRole(role: AppRole | null): string {
  if (role === 'super_admin') return '/admin'
  if (role === 'rider') return '/my-jobs'
  return '/dashboard'
}

export function merchantHomePath(): string {
  return '/merchant/requests'
}

export function friendlyRoleLabel(role: AppRole | null): string {
  if (!role) return 'Guest'
  if (role === 'super_admin') return 'Super Admin'
  return role.replace(/_/g, ' ')
}
