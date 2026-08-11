import { useAuth } from '@/hooks/use-auth'
import type { CompanyBusinessType } from '@/services/marketplace-service'

/** Resolves the active company's Commerce vendor eligibility (business_type merchant/hybrid). Read-only — never grants access itself, RPC-level checks remain the real security boundary. */
export function useVendorContext() {
  const { context } = useAuth()
  const companyId = context?.activeCompanyId ?? null
  const membership = context?.memberships.find((m) => m.company_id === companyId)
  const businessType = (membership?.company.business_type ?? null) as CompanyBusinessType | null
  const isVendorEligible = businessType === 'merchant' || businessType === 'hybrid'

  return {
    companyId,
    companyName: membership?.company.name ?? 'Workspace',
    businessType,
    isVendorEligible,
  }
}
