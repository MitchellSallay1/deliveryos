import type { Session, User } from '@supabase/supabase-js'
import { supabase } from '@/lib/supabase/client'
import { normalizePhoneE164 } from '@/lib/phone'
import { sendAuthSmsOtp, verifyAuthSmsOtp } from '@/services/auth-sms-provider'
import { OnboardingError } from '@/services/onboarding-service'
import type { CompanyRegisterForm, MerchantRegisterForm } from '@/utils/auth-schemas'

export { OnboardingError }

export async function sendPhoneOtp(rawPhone: string) {
  return sendAuthSmsOtp(rawPhone)
}

export async function verifyPhoneOtp(rawPhone: string, token: string) {
  return verifyAuthSmsOtp(rawPhone, token)
}

export async function syncProfileFromAuth() {
  const { error } = await supabase.rpc('sync_profile_from_auth_user')
  if (error) throw new Error(error.message)
}

export async function setAuthPersonaMetadata(input: {
  persona: 'company_owner' | 'merchant' | 'rider'
  fullName?: string
}) {
  const { error } = await supabase.auth.updateUser({
    data: {
      persona: input.persona,
      ...(input.fullName ? { full_name: input.fullName.trim() } : {}),
    },
  })
  if (error) throw error
}

export async function finalizeOwnerWorkspaceAfterOtp(
  input: CompanyRegisterForm | MerchantRegisterForm,
): Promise<{ companyId: string; user: User; session: Session | null }> {
  const { data: sessionData } = await supabase.auth.getSession()
  const session = sessionData.session
  const user = session?.user
  if (!user) {
    throw new OnboardingError('Sign in required to finish setup.', 'not_authenticated')
  }

  await setAuthPersonaMetadata({
    persona: input.businessType === 'merchant' ? 'merchant' : 'company_owner',
    fullName: input.fullName,
  })

  const { data, error } = await supabase.rpc('finalize_phone_workspace', {
    p_full_name: input.fullName,
    p_company_name: input.companyName,
    p_business_type: input.businessType,
    p_company_phone: normalizePhoneE164(input.companyPhone),
    p_company_email: input.companyEmail?.trim() || null,
  })
  if (error) throw new OnboardingError(error.message, 'rpc_failed')

  const payload = data as { company_id: string }
  await supabase.auth.updateUser({
    data: {
      onboarding_completed_at: new Date().toISOString(),
      pending_company_name: null,
      pending_company_phone: null,
      pending_company_email: null,
      pending_business_type: null,
    },
  })

  await syncProfileFromAuth()

  return { companyId: payload.company_id, user, session }
}

export async function completeRiderPhoneSignup(fullName: string) {
  await setAuthPersonaMetadata({ persona: 'rider', fullName })
  await syncProfileFromAuth()
}
