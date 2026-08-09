import { describe, expect, it } from 'vitest'
import {
  maskPhoneForDisplay,
  normalizePhoneE164,
  phoneMatchesMsisdn,
} from '@/lib/phone'

describe('normalizePhoneE164', () => {
  it('normalizes local Liberia formats consistently', () => {
    expect(normalizePhoneE164('0881697769')).toBe('+231881697769')
    expect(normalizePhoneE164('+231881697769')).toBe('+231881697769')
    expect(normalizePhoneE164('231881697769')).toBe('+231881697769')
  })
})

describe('phoneMatchesMsisdn', () => {
  it('matches last 9 digits across formats', () => {
    expect(phoneMatchesMsisdn('0881697769', '+231881697769')).toBe(true)
    expect(phoneMatchesMsisdn('+231881697769', '881697769')).toBe(true)
    expect(phoneMatchesMsisdn('+231881697769', '+231770000000')).toBe(false)
  })
})

describe('maskPhoneForDisplay', () => {
  it('masks middle digits for OTP UX', () => {
    expect(maskPhoneForDisplay('+231881697769')).toContain('***')
    expect(maskPhoneForDisplay('+231881697769')).toContain('7769')
  })
})
