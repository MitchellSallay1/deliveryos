/**
 * Parsers for Gupshup's webhook callback payloads. Pure, dependency-free
 * TypeScript (no Deno.* calls) so it unit-tests the same way as
 * _shared/gupshup-provider.ts — the webhook Edge Function only wires these
 * into database calls, it does not reimplement parsing.
 *
 * Payload shapes confirmed against docs.gupshup.io (docs/text,
 * docs/v2-message-events, docs/message-events) — the two shapes DeliveryOS
 * acts on in Phase A are 'message' (inbound user message) and
 * 'message-event' (outbound delivery-receipt/status). Any other `type`
 * (e.g. Gupshup's user-event opted-in/opted-out notifications) is parsed
 * into GupshupUnknownEvent rather than rejected — Phase A tracks opt-in/out
 * from inbound STOP/START commands instead (see docs/WHATSAPP.md), so these
 * are safely ignorable today, not an error.
 */

export type GupshupInboundMessageEvent = {
  kind: 'message'
  appName: string | null
  providerMessageId: string
  senderPhone: string
  messageType: string
  text: string | null
  mediaReference: Record<string, unknown> | null
  timestamp: number | null
}

export type GupshupStatusEvent = {
  kind: 'message-event'
  appName: string | null
  /** The id to match against whatsapp_outbox.provider_message_id — prefers gsId (Gupshup's own id) when present, else the WhatsApp message id. */
  providerMessageId: string
  status: string
  errorReason: string | null
  timestamp: number | null
}

export type GupshupUnknownEvent = {
  kind: 'unknown'
  rawType: string | null
}

export type GupshupWebhookEvent = GupshupInboundMessageEvent | GupshupStatusEvent | GupshupUnknownEvent

function asRecord(v: unknown): Record<string, unknown> | null {
  return typeof v === 'object' && v !== null && !Array.isArray(v) ? (v as Record<string, unknown>) : null
}

function str(v: unknown): string | null {
  return typeof v === 'string' && v.length > 0 ? v : null
}

export function parseGupshupWebhookEvent(body: unknown): GupshupWebhookEvent {
  const root = asRecord(body)
  const rawType = root ? str(root.type) : null
  const payload = root ? asRecord(root.payload) : null
  const appName = root ? str(root.app) : null
  const timestamp = root && typeof root.timestamp === 'number' ? root.timestamp : null

  if (rawType === 'message' && payload) {
    const providerMessageId = str(payload.id)
    const sender = asRecord(payload.sender)
    const senderPhone = (sender && str(sender.phone)) ?? str(payload.source)
    const messageType = str(payload.type) ?? 'unknown'
    const inner = asRecord(payload.payload)

    if (!providerMessageId || !senderPhone) {
      return { kind: 'unknown', rawType }
    }

    return {
      kind: 'message',
      appName,
      providerMessageId,
      senderPhone,
      messageType,
      text: inner ? str(inner.text) : null,
      // Provider metadata only (e.g. { id, url, mimeType }) — the binary is
      // never fetched or stored, per Phase A's explicit media scope.
      mediaReference: messageType === 'text' ? null : inner,
      timestamp,
    }
  }

  if (rawType === 'message-event' && payload) {
    // gsId is only present on DLR (sent/delivered/read/failed) events, not
    // 'enqueued' — fall back to payload.id, which is present on every event.
    const providerMessageId = str(payload.gsId) ?? str(payload.id)
    const status = str(payload.type)

    if (!providerMessageId || !status) {
      return { kind: 'unknown', rawType }
    }

    const innerPayload = asRecord(payload.payload)
    const errorReason =
      (innerPayload && (str(innerPayload.reason) ?? (innerPayload.code != null ? String(innerPayload.code) : null))) ??
      null

    return {
      kind: 'message-event',
      appName,
      providerMessageId,
      status,
      errorReason,
      timestamp,
    }
  }

  return { kind: 'unknown', rawType }
}
