import { describe, expect, it, vi } from 'vitest'
import { submitContactForm } from '@/services/contact-form-service'

describe('submitContactForm', () => {
  it('returns provider_ready when no endpoint configured', async () => {
    vi.stubEnv('VITE_CONTACT_FORM_URL', '')
    const result = await submitContactForm({
      name: 'Test',
      company: 'Co',
      phone: '+231770000000',
      businessType: 'courier',
      message: 'Hello',
      intent: 'sales',
    })
    expect(result.mode).toBe('provider_ready')
  })
})
