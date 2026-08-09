import { describe, expect, it } from 'vitest'

describe('random token migration', () => {
  it('replaces gen_random_bytes in active RPCs', async () => {
    const fs = await import('node:fs/promises')
    const sqlText = await fs.readFile(
      'supabase/migrations/20260308130000_random_tokens_without_gen_random_bytes.sql',
      'utf8',
    )
    expect(sqlText).toContain('random_token_hex')
    expect(sqlText).toMatch(/gen_random_uuid\(\)/)
    expect(sqlText).not.toMatch(/encode\(gen_random_bytes/)
    expect(sqlText).toContain('generate_tracking_code')
  })
})
