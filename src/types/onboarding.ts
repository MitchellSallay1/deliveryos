import type { User } from '@supabase/supabase-js'
import type { CompanyBusinessType } from '@/types/supabase'

export type UserPersona = 'company_owner' | 'merchant' | 'rider'

export type PendingOnboardingMetadata = {
  pending_company_name: string
  pending_company_phone: string
  pending_company_email: string
  pending_business_type: CompanyBusinessType
}

export type CompletePendingOnboardingResult = {
  company_id: string | null
  created: boolean
  status: 'created' | 'already_member' | 'pending_metadata_missing'
}

export function readUserMetadata(user: User): Record<string, unknown> {
  return (user.user_metadata ?? {}) as Record<string, unknown>
}

export function readUserPersona(user: User | null | undefined): UserPersona | null {
  if (!user) return null
  const m = readUserMetadata(user)
  const raw = typeof m.persona === 'string' ? m.persona.toLowerCase() : ''
  if (raw === 'rider' || raw === 'merchant' || raw === 'company_owner') {
    return raw as UserPersona
  }
  const name = typeof m.pending_company_name === 'string' ? m.pending_company_name.trim() : ''
  const phone = typeof m.pending_company_phone === 'string' ? m.pending_company_phone.trim() : ''
  if (name.length >= 2 && phone.length >= 7) {
    const businessType = m.pending_business_type
    if (businessType === 'merchant') return 'merchant'
    return 'company_owner'
  }
  return null
}

export function isRiderPersona(user: User | null | undefined): boolean {
  if (!user) return false
  const m = readUserMetadata(user)
  return typeof m.persona === 'string' && m.persona.toLowerCase() === 'rider'
}

export function hasPendingOnboardingMetadata(user: User | null | undefined): boolean {
  if (!user) return false
  if (isRiderPersona(user)) return false
  const m = readUserMetadata(user)
  const name = typeof m.pending_company_name === 'string' ? m.pending_company_name.trim() : ''
  const phone = typeof m.pending_company_phone === 'string' ? m.pending_company_phone.trim() : ''
  return name.length >= 2 && phone.length >= 7
}

export function pendingOnboardingFromUser(user: User): PendingOnboardingMetadata | null {
  if (!hasPendingOnboardingMetadata(user)) return null
  const m = readUserMetadata(user)
  const businessType = m.pending_business_type
  const validTypes = ['logistics_provider', 'merchant', 'hybrid'] as const
  const bt =
    typeof businessType === 'string' &&
    (validTypes as readonly string[]).includes(businessType)
      ? (businessType as CompanyBusinessType)
      : 'logistics_provider'
  return {
    pending_company_name: String(m.pending_company_name).trim(),
    pending_company_phone: String(m.pending_company_phone).trim(),
    pending_company_email: String(m.pending_company_email).trim(),
    pending_business_type: bt,
  }
}

/** Pre-fill manual workspace setup from signup metadata (full or partial). */
export function getSetupFormDefaults(user: User | null | undefined): {
  companyName: string
  businessType: CompanyBusinessType
  companyPhone: string
  companyEmail: string
} {
  if (!user) {
    return {
      companyName: '',
      businessType: 'logistics_provider',
      companyPhone: '',
      companyEmail: '',
    }
  }
  const m = readUserMetadata(user)
  const validTypes = ['logistics_provider', 'merchant', 'hybrid'] as const
  const rawBt = m.pending_business_type
  const businessType =
    typeof rawBt === 'string' && (validTypes as readonly string[]).includes(rawBt)
      ? (rawBt as CompanyBusinessType)
      : 'logistics_provider'

  return {
    companyName:
      typeof m.pending_company_name === 'string' ? m.pending_company_name.trim() : '',
    businessType,
    companyPhone:
      typeof m.pending_company_phone === 'string' ? m.pending_company_phone.trim() : '',
    companyEmail:
      (typeof m.pending_company_email === 'string' ? m.pending_company_email.trim() : '') ||
      user.email ||
      '',
  }
}
