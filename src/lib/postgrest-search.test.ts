import { describe, expect, it } from 'vitest'
import { sanitizeIlikeSearchTerm } from '@/lib/postgrest-search'

describe('sanitizeIlikeSearchTerm', () => {
  it('leaves ordinary search terms unchanged', () => {
    expect(sanitizeIlikeSearchTerm('John Doe')).toBe('John Doe')
    expect(sanitizeIlikeSearchTerm('0881697769')).toBe('0881697769')
  })

  it('strips characters that break out of a PostgREST or() filter group', () => {
    expect(sanitizeIlikeSearchTerm('a,b')).toBe('a b')
    expect(sanitizeIlikeSearchTerm('a)or(id.neq.0')).toBe('a or id.neq.0')
    expect(sanitizeIlikeSearchTerm('id.neq.0),status.eq.x')).toBe('id.neq.0  status.eq.x')
  })

  it('preserves ilike wildcards', () => {
    expect(sanitizeIlikeSearchTerm('%admin%')).toBe('%admin%')
    expect(sanitizeIlikeSearchTerm('jo_n')).toBe('jo_n')
  })
})
