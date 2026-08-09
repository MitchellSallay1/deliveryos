import { describe, expect, it, vi } from 'vitest'

describe('getAppUrl', () => {
  it('uses VITE_APP_URL when set', async () => {
    vi.stubEnv('VITE_APP_URL', 'https://app.deliveryos.example/')
    const { getAppUrl, authCallbackUrl } = await import('@/lib/app-url')
    expect(getAppUrl()).toBe('https://app.deliveryos.example')
    expect(authCallbackUrl()).toBe('https://app.deliveryos.example/auth/callback')
    vi.unstubAllEnvs()
  })
})
