import { describe, expect, it } from 'vitest'
import { isNonCanonicalHost } from './config'

describe('isNonCanonicalHost', () => {
  it('flags the operational app domain', () => {
    expect(isNonCanonicalHost('app.delivoslib.com')).toBe(true)
  })

  it('flags any Vercel preview/deployment domain', () => {
    expect(isNonCanonicalHost('deliveryos-git-feature-x.vercel.app')).toBe(true)
    expect(isNonCanonicalHost('deliveryos.vercel.app')).toBe(true)
  })

  it('does not flag the canonical marketing domain', () => {
    expect(isNonCanonicalHost('delivoslib.com')).toBe(false)
  })

  it('does not flag www — that is handled by a redirect to the apex, not by noindex', () => {
    expect(isNonCanonicalHost('www.delivoslib.com')).toBe(false)
  })

  it('does not flag local dev', () => {
    expect(isNonCanonicalHost('localhost')).toBe(false)
  })
})
