import type { User } from '@supabase/supabase-js'
import type { AuthContext } from '@/types/database'
import { defaultHomeForRole } from '@/lib/rbac'
import { hasPendingOnboardingMetadata, isRiderPersona } from '@/types/onboarding'

export function isRiderLinked(context: AuthContext | null | undefined): boolean {
  if (!context) return false
  return context.memberships.some((m) => m.role === 'rider' && m.is_active)
}

export function resolvePostAuthPath(user: User, context: AuthContext): string {
  if (context.profile?.is_super_admin) {
    return '/admin'
  }

  if (isRiderPersona(user)) {
    return isRiderLinked(context) ? '/my-jobs' : '/link-rider'
  }

  if (context.memberships.length > 0) {
    const active =
      context.memberships.find((m) => m.company_id === context.activeCompanyId) ??
      context.memberships[0]
    const role = context.activeRole ?? active?.role ?? null
    if (active?.company.business_type === 'merchant' && role === 'company_owner') {
      return '/merchant/requests'
    }
    return defaultHomeForRole(role)
  }

  if (hasPendingOnboardingMetadata(user)) {
    return '/dashboard'
  }

  return '/setup'
}

/** Authenticated users must not use registration (new auth account). */
export function resolveAuthenticatedRegisterRedirect(
  user: User,
  context: AuthContext | null,
): '/admin' | '/dashboard' | '/setup' | '/my-jobs' | '/link-rider' {
  if (context?.profile?.is_super_admin) return '/admin'
  if (isRiderPersona(user)) {
    return isRiderLinked(context ?? { memberships: [], profile: null, activeCompanyId: null, activeRole: null })
      ? '/my-jobs'
      : '/link-rider'
  }
  if ((context?.memberships.length ?? 0) > 0) return '/dashboard'
  return '/setup'
}

export function shouldBlockCompanySetup(user: User | null | undefined): boolean {
  return isRiderPersona(user)
}

export function isCompanyWorkspaceUser(context: AuthContext | null): boolean {
  if (!context) return false
  if (context.profile?.is_super_admin) return true
  const role = context.activeRole
  return role != null && role !== 'rider'
}
