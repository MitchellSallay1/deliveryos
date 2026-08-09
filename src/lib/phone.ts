/** Client-side Liberia-first phone normalization (mirrors DB normalize_phone_lr). */

export function digitsOnly(input: string): string {
  return input.replace(/\D/g, '')
}

export function normalizePhoneE164(input: string, defaultCountry = '231'): string {
  const d = digitsOnly(input)
  if (!d) return ''

  if (d.length === 9) {
    return `+${defaultCountry}${d}`
  }
  if (d.length === 10 && d.startsWith('0')) {
    return `+${defaultCountry}${d.slice(1)}`
  }
  if (d.length >= 11 && d.startsWith('231')) {
    return `+${d}`
  }
  if (input.trim().startsWith('+')) {
    return `+${d}`
  }
  return `+${d}`
}

export function phoneMatchesMsisdn(a: string, b: string): boolean {
  const da = digitsOnly(a)
  const db = digitsOnly(b)
  if (da.length < 9 || db.length < 9) return false
  return da.slice(-9) === db.slice(-9)
}

/** Mask +231881697769 → +231 88 *** 7769 */
export function maskPhoneForDisplay(e164: string): string {
  const d = digitsOnly(e164)
  if (d.length < 9) return e164
  const last4 = d.slice(-4)
  const prefix = d.startsWith('231') ? '+231' : `+${d.slice(0, Math.max(0, d.length - 9))}`
  const local = d.slice(-9)
  const mid = local.slice(0, 2)
  return `${prefix} ${mid} *** ${last4}`
}

export function isValidLiberiaMobile(e164: string): boolean {
  const d = digitsOnly(e164)
  const local = d.length >= 12 && d.startsWith('231') ? d.slice(3) : d.length === 9 ? d : ''
  return local.length === 9 && /^[0-9]{9}$/.test(local)
}
