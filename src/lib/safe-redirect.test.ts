import { describe, expect, it } from 'vitest'
import { safeInternalRedirect } from '@/lib/safe-redirect'

describe('safeInternalRedirect', () => {
  it('allows internal paths', () => {
    expect(safeInternalRedirect('/invite/abc')).toBe('/invite/abc')
  })

  it('blocks external URLs', () => {
    expect(safeInternalRedirect('https://evil.test')).toBeNull()
    expect(safeInternalRedirect('//evil.test/path')).toBeNull()
  })
})
