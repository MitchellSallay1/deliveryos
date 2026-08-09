import type { User } from '@supabase/supabase-js'
import { supabase } from '@/lib/supabase/client'
import type { CompletePendingOnboardingResult } from '@/types/onboarding'
import { hasPendingOnboardingMetadata } from '@/types/onboarding'

export class OnboardingError extends Error {
  constructor(
    message: string,
    readonly code: 'not_authenticated' | 'rpc_failed' | 'metadata_missing' | 'unknown',
  ) {
    super(message)
    this.name = 'OnboardingError'
  }
}

export async function completePendingOnboarding(): Promise<CompletePendingOnboardingResult> {
  const { data: sessionData } = await supabase.auth.getSession()
  if (!sessionData.session?.user) {
    throw new OnboardingError('Sign in required to finish setup.', 'not_authenticated')
  }

  const { data, error } = await supabase.rpc('complete_pending_onboarding')
  if (error) {
    throw new OnboardingError(error.message, 'rpc_failed')
  }

  const result = data as CompletePendingOnboardingResult
  if (result.status === 'pending_metadata_missing') {
    return result
  }

  if (result.company_id) {
    await clearPendingOnboardingMetadata()
  }

  return result
}

export async function clearPendingOnboardingMetadata(): Promise<void> {
  await supabase.auth.updateUser({
    data: {
      pending_company_name: null,
      pending_company_phone: null,
      pending_company_email: null,
      pending_business_type: null,
      onboarding_completed_at: new Date().toISOString(),
    },
  })
}

/** When session exists: finish company setup from user metadata if needed. */
export async function completePendingOnboardingIfNeeded(
  user: User,
): Promise<CompletePendingOnboardingResult | null> {
  if (!hasPendingOnboardingMetadata(user)) {
    return null
  }
  return completePendingOnboarding()
}

export async function createCompanyWithOwnerFromSession(input: {
  companyName: string
  companyPhone: string
  companyEmail?: string
  businessType: 'logistics_provider' | 'merchant' | 'hybrid'
}): Promise<string> {
  const { data, error } = await supabase.rpc('create_company_with_owner', {
    p_name: input.companyName,
    p_phone: input.companyPhone,
    p_email: input.companyEmail ?? '',
    p_address: null,
    p_business_type: input.businessType,
  })
  if (error) throw new OnboardingError(error.message, 'rpc_failed')
  const companyId = data as string
  await clearPendingOnboardingMetadata()
  return companyId
}

function resolveWorkspaceContactFields(input: {
  companyPhone?: string
  companyEmail?: string
  userEmail?: string | null
}): { companyPhone: string; companyEmail: string } {
  const companyEmail =
    (input.companyEmail?.trim() || input.userEmail?.trim() || 'contact@deliveryos.local').toLowerCase()
  const rawPhone = input.companyPhone?.trim() ?? ''
  const companyPhone = rawPhone.length >= 7 ? rawPhone : '+2310000000'
  return { companyPhone, companyEmail }
}

/** Manual workspace setup for an already-authenticated user (no new auth account). */
export async function createWorkspaceForAuthenticatedUser(
  input: {
    companyName: string
    businessType: 'logistics_provider' | 'merchant' | 'hybrid'
    companyPhone?: string
    companyEmail?: string
  },
  userEmail?: string | null,
): Promise<string> {
  const { companyPhone, companyEmail } = resolveWorkspaceContactFields({
    companyPhone: input.companyPhone,
    companyEmail: input.companyEmail,
    userEmail,
  })
  return createCompanyWithOwnerFromSession({
    companyName: input.companyName.trim(),
    companyPhone,
    companyEmail,
    businessType: input.businessType,
  })
}
