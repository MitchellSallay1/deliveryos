import { useAuth } from '@/hooks/use-auth'
import { can, type Permission } from '@/lib/rbac'

export function useAccess() {
  const { context } = useAuth()
  const role = context?.activeRole ?? null

  return {
    role,
    can: (permission: Permission) => can(role, permission),
  }
}
