import { describe, expect, it } from 'vitest'
import {
  isButtonPhoneCapable,
  parseRiderSmsCommand,
  riderAccessModeLabel,
  trackingCommandSuffix,
} from '@/utils/rider-schemas'

describe('rider access mode', () => {
  it('labels access modes for UI', () => {
    expect(riderAccessModeLabel('smartphone')).toBe('Smartphone')
    expect(riderAccessModeLabel('button_phone')).toBe('Button phone')
    expect(riderAccessModeLabel('both')).toBe('Both')
  })

  it('detects button-phone capable riders', () => {
    expect(isButtonPhoneCapable('smartphone')).toBe(false)
    expect(isButtonPhoneCapable('button_phone')).toBe(true)
    expect(isButtonPhoneCapable('both')).toBe(true)
  })
})

describe('trackingCommandSuffix', () => {
  it('uses last 4 alphanumeric chars', () => {
    expect(trackingCommandSuffix('DLV-80D7AE1A69B9')).toBe('69B9')
  })
})

describe('parseRiderSmsCommand', () => {
  it('parses accept with suffix', () => {
    expect(parseRiderSmsCommand('A 69B9')).toEqual({ command: 'A', suffix: '69B9', extra: undefined })
  })

  it('parses deliver with OTP', () => {
    expect(parseRiderSmsCommand('D 69B9 4821')).toEqual({
      command: 'D',
      suffix: '69B9',
      extra: '4821',
    })
  })

  it('parses single-token accept', () => {
    expect(parseRiderSmsCommand('A')).toEqual({ command: 'A', suffix: undefined, extra: undefined })
  })

  it('rejects unknown commands', () => {
    expect(parseRiderSmsCommand('Z 69B9')).toBeNull()
  })
})

describe('button-phone rider model', () => {
  it('does not require auth user_id for button-phone-only riders', () => {
    const rider = {
      access_mode: 'button_phone' as const,
      user_id: null as string | null,
    }
    expect(rider.user_id).toBeNull()
    expect(isButtonPhoneCapable(rider.access_mode)).toBe(true)
  })

  it('smartphone rider still expects linked account for PWA', () => {
    const rider = { access_mode: 'smartphone' as const, user_id: 'uuid' }
    expect(isButtonPhoneCapable(rider.access_mode)).toBe(false)
    expect(rider.user_id).toBeTruthy()
  })
})
