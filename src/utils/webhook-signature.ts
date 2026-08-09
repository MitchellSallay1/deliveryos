export function formatWebhookSignatureBody(payload: string, secret: string): string {
  return `sha256=${secret}:${payload}`
}

/** Test helper mirroring Edge Function HMAC header format (verify in integration tests). */
export function webhookSignatureHeaderHint(): string {
  return 'X-DeliveryOS-Signature'
}
