import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { User } from '@supabase/supabase-js'

const { authState, rpc } = vi.hoisted(() => ({
  authState: {
    signInWithOtp: vi.fn(),
    verifyOtp: vi.fn(),
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

import { finalizeOwnerWorkspaceAfterOtp } from '@/services/auth-service'
import {
  completePendingOnboarding,
  completePendingOnboardingIfNeeded,
} from '@/services/onboarding-service'
import { hasPendingOnboardingMetadata } from '@/types/onboarding'

function mockUser(overrides: Partial<User> = {}): User {
  return {
    id: 'user-1',
    app_metadata: {},
    user_metadata: {},
    aud: 'authenticated',
    created_at: '',
    ...overrides,
  } as User
}

describe('finalizeOwnerWorkspaceAfterOtp', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    authState.getSession.mockResolvedValue({
      data: { session: { user: mockUser({ id: 'u1' }) } },
      error: null,
    })
    authState.updateUser.mockResolvedValue({ data: {}, error: null })
    rpc.mockResolvedValue({ data: { company_id: 'company-1' }, error: null })
  })

  it('creates workspace after phone session exists', async () => {
    const result = await finalizeOwnerWorkspaceAfterOtp({
      businessType: 'logistics_provider',
      companyName: 'Acme Couriers',
      companyPhone: '+231770000000',
      companyEmail: '',
      fullName: 'Jane Owner',
    })

    expect(result.companyId).toBe('company-1')
    expect(rpc).toHaveBeenCalledWith('finalize_phone_workspace', expect.any(Object))
    expect(rpc).toHaveBeenCalledWith('sync_profile_from_auth_user')
  })
})

describe('completePendingOnboarding', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    authState.updateUser.mockResolvedValue({ data: {}, error: null })
  })

  it('creates company on callback when RPC succeeds', async () => {
    authState.getSession.mockResolvedValue({
      data: { session: { user: mockUser() } },
      error: null,
    })
    rpc.mockResolvedValue({
      data: { company_id: 'c1', created: true, status: 'created' },
      error: null,
    })

    const result = await completePendingOnboarding()
    expect(result.company_id).toBe('c1')
    expect(rpc).toHaveBeenCalledWith('complete_pending_onboarding')
    expect(authState.updateUser).toHaveBeenCalled()
  })

  it('returns friendly metadata missing status without throwing', async () => {
    authState.getSession.mockResolvedValue({
      data: { session: { user: mockUser() } },
      error: null,
    })
    rpc.mockResolvedValue({
      data: { company_id: null, created: false, status: 'pending_metadata_missing' },
      error: null,
    })

    const result = await completePendingOnboarding()
    expect(result.status).toBe('pending_metadata_missing')
    expect(authState.updateUser).not.toHaveBeenCalled()
  })
})

describe('hasPendingOnboardingMetadata', () => {
  it('detects pending signup without requiring email', () => {
    const user = mockUser({
      user_metadata: {
        pending_company_name: 'Acme',
        pending_company_phone: '+231770000000',
      },
    })
    expect(hasPendingOnboardingMetadata(user)).toBe(true)
  })

  it('skips rider persona', () => {
    const user = mockUser({
      user_metadata: { persona: 'rider', pending_company_name: 'X', pending_company_phone: '+231' },
    })
    expect(hasPendingOnboardingMetadata(user)).toBe(false)
  })
})

describe('completePendingOnboardingIfNeeded', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    authState.getSession.mockResolvedValue({
      data: { session: { user: mockUser() } },
      error: null,
    })
    authState.updateUser.mockResolvedValue({ data: {}, error: null })
  })

  it('skips RPC when user has no pending metadata', async () => {
    const user = mockUser({ user_metadata: { full_name: 'Jane' } })
    const result = await completePendingOnboardingIfNeeded(user)
    expect(result).toBeNull()
    expect(rpc).not.toHaveBeenCalled()
  })
})
