import { describe, expect, it } from 'vitest'
import { companyRegisterSchema, phoneInputSchema } from '@/utils/auth-schemas'

describe('phoneInputSchema', () => {
  it('accepts normalized Liberia numbers', () => {
    expect(phoneInputSchema.safeParse('0881697769').success).toBe(true)
    expect(phoneInputSchema.safeParse('+231881697769').success).toBe(true)
  })

  it('rejects too-short numbers', () => {
    expect(phoneInputSchema.safeParse('123').success).toBe(false)
  })
})

describe('companyRegisterSchema', () => {
  it('allows optional company email', () => {
    const result = companyRegisterSchema.safeParse({
      businessType: 'logistics_provider',
      companyName: 'Acme',
      companyPhone: '+231770000000',
      companyEmail: '',
      fullName: 'Jane',
    })
    expect(result.success).toBe(true)
  })
})
