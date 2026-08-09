import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { User } from '@supabase/supabase-js'
import {
  resolveAuthenticatedRegisterRedirect,
  resolvePostAuthPath,
} from '@/lib/post-auth-navigation'
import { getSetupFormDefaults } from '@/types/onboarding'
import type { AuthContext } from '@/types/database'

const { authState, rpc } = vi.hoisted(() => ({
  authState: {
    signUp: vi.fn(),
    getSession: vi.fn(),
    updateUser: vi.fn(),
  },
  rpc: vi.fn(),
}))

vi.mock('@/lib/supabase/client', () => ({
  supabase: {
    auth: authState,
    rpc,
  },
}))

import { createWorkspaceForAuthenticatedUser } from '@/services/onboarding-service'

function mockUser(overrides: Partial<User> = {}): User {
  return {
    id: 'user-1',
    email: 'owner@acme.test',
    app_metadata: {},
    user_metadata: {},
    aud: 'authenticated',
    created_at: '',
    ...overrides,
  } as User
}

function emptyContext(overrides: Partial<AuthContext> = {}): AuthContext {
  return {
    profile: null,
    memberships: [],
    activeCompanyId: null,
    activeRole: null,
    ...overrides,
  }
}

describe('resolvePostAuthPath', () => {
  it('sends authenticated user with no company to /setup', () => {
    expect(resolvePostAuthPath(mockUser(), emptyContext())).toBe('/setup')
  })

  it('sends user with company membership to dashboard', () => {
    const ctx = emptyContext({
      memberships: [
        {
          id: 'm1',
          company_id: 'c1',
          user_id: 'user-1',
          role: 'company_owner',
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
      activeCompanyId: 'c1',
      activeRole: 'company_owner',
    })
    expect(resolvePostAuthPath(mockUser(), ctx)).toBe('/dashboard')
  })
})

describe('resolveAuthenticatedRegisterRedirect', () => {
  it('redirects authenticated user without company to /setup', () => {
    const user = mockUser()
    expect(resolveAuthenticatedRegisterRedirect(user, emptyContext())).toBe('/setup')
  })

  it('redirects authenticated user with company to /dashboard', () => {
    const user = mockUser()
    const ctx = emptyContext({ activeRole: 'company_owner', activeCompanyId: 'c1', memberships: [{
      id: 'm1', company_id: 'c1', user_id: 'user-1', role: 'company_owner', is_active: true, created_at: '',
      company: { id: 'c1', name: 'Acme', slug: 'acme', status: 'active', business_type: 'logistics_provider' },
    }] })
    expect(resolveAuthenticatedRegisterRedirect(user, ctx)).toBe('/dashboard')
  })
})

describe('getSetupFormDefaults', () => {
  it('pre-fills pending metadata including partial fields', () => {
    const user = mockUser({
      email: 'owner@acme.test',
      user_metadata: {
        pending_company_name: 'Acme Couriers',
        pending_business_type: 'merchant',
        pending_company_phone: '+231770000000',
      },
    })
    expect(getSetupFormDefaults(user)).toEqual({
      companyName: 'Acme Couriers',
      businessType: 'merchant',
      companyPhone: '+231770000000',
      companyEmail: 'owner@acme.test',
    })
  })
})

describe('createWorkspaceForAuthenticatedUser', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    authState.updateUser.mockResolvedValue({ data: {}, error: null })
  })

  it('creates company via RPC without creating a new auth user', async () => {
    rpc.mockResolvedValue({ data: 'company-99', error: null })

    const id = await createWorkspaceForAuthenticatedUser(
      {
        companyName: 'New Co',
        businessType: 'hybrid',
        companyPhone: '+231770000001',
        companyEmail: 'ops@newco.test',
      },
      'owner@newco.test',
    )

    expect(id).toBe('company-99')
    expect(rpc).toHaveBeenCalledWith(
      'create_company_with_owner',
      expect.objectContaining({
        p_name: 'New Co',
        p_business_type: 'hybrid',
      }),
    )
    expect(authState.signUp).not.toHaveBeenCalled()
  })

  it('does not duplicate company on repeated RPC calls (idempotent server)', async () => {
    rpc.mockResolvedValue({ data: 'company-99', error: null })

    await createWorkspaceForAuthenticatedUser(
      { companyName: 'New Co', businessType: 'logistics_provider' },
      'owner@newco.test',
    )
    await createWorkspaceForAuthenticatedUser(
      { companyName: 'New Co', businessType: 'logistics_provider' },
      'owner@newco.test',
    )

    expect(rpc).toHaveBeenCalledTimes(2)
    expect(rpc).toHaveBeenNthCalledWith(
      1,
      'create_company_with_owner',
      expect.any(Object),
    )
  })
})

describe('auth callback missing metadata', () => {
  it('routes to /setup via resolvePostAuthPath after failed auto onboarding', () => {
    const user = mockUser({ user_metadata: { full_name: 'Jane' } })
    expect(resolvePostAuthPath(user, emptyContext())).toBe('/setup')
  })
})

describe('existing company member', () => {
  it('routes to dashboard not setup', () => {
    const ctx = emptyContext({
      memberships: [
        {
          id: 'm1',
          company_id: 'c1',
          user_id: 'user-1',
          role: 'company_owner',
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
      activeRole: 'company_owner',
      activeCompanyId: 'c1',
    })
    expect(resolvePostAuthPath(mockUser(), ctx)).toBe('/dashboard')
    expect(resolveAuthenticatedRegisterRedirect(mockUser(), ctx)).toBe('/dashboard')
  })
})

describe('setup success navigation', () => {
  it('uses dashboard path when context has membership after create', () => {
    const ctx = emptyContext({
      memberships: [
        {
          id: 'm1',
          company_id: 'c1',
          user_id: 'user-1',
          role: 'company_owner',
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
      activeRole: 'company_owner',
      activeCompanyId: 'c1',
    })
    expect(resolvePostAuthPath(mockUser(), ctx)).toBe('/dashboard')
  })
})
