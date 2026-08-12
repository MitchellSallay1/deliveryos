import { describe, expect, it } from 'vitest'
import { isIosDevice, isStandaloneDisplayMode, supportsBeforeInstallPrompt } from './platform'

function mockNavigator(overrides: Partial<Navigator>): Navigator {
  return { userAgent: '', platform: '', maxTouchPoints: 0, ...overrides } as Navigator
}

function mockWindow(overrides: { matches?: boolean; hasMatchMedia?: boolean; standalone?: boolean }): Window {
  const nav = { standalone: overrides.standalone } as Navigator & { standalone?: boolean }
  return {
    navigator: nav,
    matchMedia: overrides.hasMatchMedia === false ? undefined : (() => ({ matches: overrides.matches ?? false })),
  } as unknown as Window
}

describe('isIosDevice', () => {
  it('detects iPhone by user agent', () => {
    expect(isIosDevice(mockNavigator({ userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)' }))).toBe(true)
  })

  it('detects iPod by user agent', () => {
    expect(isIosDevice(mockNavigator({ userAgent: 'Mozilla/5.0 (iPod touch; CPU iPhone OS 15_0 like Mac OS X)' }))).toBe(true)
  })

  it('detects classic iPad by user agent', () => {
    expect(isIosDevice(mockNavigator({ userAgent: 'Mozilla/5.0 (iPad; CPU OS 12_0 like Mac OS X)' }))).toBe(true)
  })

  it('detects iPadOS 13+ masquerading as a Mac via touch points', () => {
    expect(isIosDevice(mockNavigator({ userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_6)', platform: 'MacIntel', maxTouchPoints: 5 }))).toBe(true)
  })

  it('does not flag a real Mac (MacIntel, no touch points) as iOS', () => {
    expect(isIosDevice(mockNavigator({ userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_6)', platform: 'MacIntel', maxTouchPoints: 0 }))).toBe(false)
  })

  it('does not flag Android as iOS', () => {
    expect(isIosDevice(mockNavigator({ userAgent: 'Mozilla/5.0 (Linux; Android 14)', platform: 'Linux armv8l' }))).toBe(false)
  })

  it('does not flag Windows desktop as iOS', () => {
    expect(isIosDevice(mockNavigator({ userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)', platform: 'Win32' }))).toBe(false)
  })
})

describe('isStandaloneDisplayMode', () => {
  it('is true when the display-mode: standalone media query matches', () => {
    expect(isStandaloneDisplayMode(mockWindow({ matches: true }))).toBe(true)
  })

  it('is true when navigator.standalone is true (iOS Safari), even if the media query does not match', () => {
    expect(isStandaloneDisplayMode(mockWindow({ matches: false, standalone: true }))).toBe(true)
  })

  it('is false in an ordinary browser tab', () => {
    expect(isStandaloneDisplayMode(mockWindow({ matches: false, standalone: false }))).toBe(false)
  })

  it('does not throw when matchMedia is unavailable', () => {
    expect(isStandaloneDisplayMode(mockWindow({ hasMatchMedia: false, standalone: false }))).toBe(false)
  })
})

describe('supportsBeforeInstallPrompt', () => {
  it('is true when the browser exposes onbeforeinstallprompt', () => {
    expect(supportsBeforeInstallPrompt({ onbeforeinstallprompt: null } as unknown as Window)).toBe(true)
  })

  it('is false when the browser does not expose it (e.g. Safari)', () => {
    expect(supportsBeforeInstallPrompt({} as Window)).toBe(false)
  })
})
