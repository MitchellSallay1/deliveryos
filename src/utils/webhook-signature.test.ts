import { describe, expect, it } from 'vitest'
import { formatWebhookSignatureBody, webhookSignatureHeaderHint } from '@/utils/webhook-signature'

describe('webhook signatures', () => {
  it('documents header name', () => {
    expect(webhookSignatureHeaderHint()).toBe('X-DeliveryOS-Signature')
  })

  it('formats deterministic test payload wrapper', () => {
    expect(formatWebhookSignatureBody('{"a":1}', 'secret')).toContain('sha256=')
  })
})
