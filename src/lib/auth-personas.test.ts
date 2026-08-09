import { describe, expect, it } from 'vitest'
import type { User } from '@supabase/supabase-js'
import {
  hasPendingOnboardingMetadata,
  isRiderPersona,
  readUserPersona,
} from '@/types/onboarding'
import {
  isRiderLinked,
  resolvePostAuthPath,
  shouldBlockCompanySetup,
} from '@/lib/post-auth-navigation'
import type { AuthContext } from '@/types/database'

function mockUser(meta: Record<string, unknown> = {}): User {
  return { id: 'u1', user_metadata: meta } as User
}

const emptyContext: AuthContext = {
  profile: null,
  memberships: [],
  activeCompanyId: null,
  activeRole: null,
}

describe('persona metadata', () => {
  it('detects rider persona without company pending fields', () => {
    const user = mockUser({ persona: 'rider', full_name: 'Sam' })
    expect(isRiderPersona(user)).toBe(true)
    expect(hasPendingOnboardingMetadata(user)).toBe(false)
    expect(readUserPersona(user)).toBe('rider')
  })

  it('detects company owner pending workspace metadata', () => {
    const user = mockUser({
      persona: 'company_owner',
      pending_company_name: 'Acme',
      pending_company_phone: '+231770000000',
      pending_company_email: 'ops@acme.test',
    })
    expect(hasPendingOnboardingMetadata(user)).toBe(true)
    expect(readUserPersona(user)).toBe('company_owner')
  })

  it('detects merchant persona from metadata', () => {
    const user = mockUser({
      persona: 'merchant',
      pending_company_name: 'Shop',
      pending_company_phone: '+231770000001',
      pending_company_email: 'shop@test.com',
      pending_business_type: 'merchant',
    })
    expect(readUserPersona(user)).toBe('merchant')
  })
})

describe('resolvePostAuthPath', () => {
  it('sends unlinked rider to link screen', () => {
    const user = mockUser({ persona: 'rider' })
    expect(resolvePostAuthPath(user, emptyContext)).toBe('/link-rider')
  })

  it('sends linked rider to my jobs', () => {
    const user = mockUser({ persona: 'rider' })
    const ctx: AuthContext = {
      ...emptyContext,
      activeRole: 'rider',
      memberships: [
        {
          id: 'm1',
          company_id: 'c1',
          user_id: 'u1',
          role: 'rider',
          is_active: true,
          created_at: '',
          company: {
            id: 'c1',
            name: 'Acme',
            slug: 'acme',
            status: 'active',
            business_type: 'logistics_provider',
          },
        },
      ],
    }
    expect(isRiderLinked(ctx)).toBe(true)
    expect(resolvePostAuthPath(user, ctx)).toBe('/my-jobs')
  })

  it('blocks company setup for riders', () => {
    expect(shouldBlockCompanySetup(mockUser({ persona: 'rider' }))).toBe(true)
    expect(shouldBlockCompanySetup(mockUser({ persona: 'company_owner' }))).toBe(false)
  })

  it('routes merchant owner to merchant portal', () => {
    const user = mockUser({ persona: 'merchant' })
    const ctx: AuthContext = {
      ...emptyContext,
      activeRole: 'company_owner',
      activeCompanyId: 'c1',
      memberships: [
        {
          id: 'm1',
          company_id: 'c1',
          user_id: 'u1',
          role: 'company_owner',
          is_active: true,
          created_at: '',
          company: {
            id: 'c1',
            name: 'Shop',
            slug: 'shop',
            status: 'active',
            business_type: 'merchant',
          },
        },
      ],
    }
    expect(resolvePostAuthPath(user, ctx)).toBe('/merchant/requests')
  })
})

describe('button-phone riders', () => {
  it('unchanged: no auth persona for MSISDN channel', () => {
    expect(isRiderPersona(null)).toBe(false)
    expect(hasPendingOnboardingMetadata(null)).toBe(false)
  })
})
