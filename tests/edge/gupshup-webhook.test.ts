import { describe, expect, it } from 'vitest'
import { parseGupshupWebhookEvent } from '../../supabase/functions/_shared/gupshup-webhook.ts'

describe('parseGupshupWebhookEvent — inbound message', () => {
  it('parses a real-shaped inbound text message payload', () => {
    const event = parseGupshupWebhookEvent({
      app: 'DeliveryOS',
      timestamp: 1718007189549,
      version: 2,
      type: 'message',
      payload: {
        id: 'ABEGkZUTIXZ0Ago6jWqOZm-Sz0WD',
        source: '231770229690',
        type: 'text',
        payload: { text: 'TRACK DLV-ABC123' },
        sender: { phone: '231770229690', name: 'Jane', country_code: '231', dial_code: '770229690' },
      },
    })

    expect(event).toEqual({
      kind: 'message',
      appName: 'DeliveryOS',
      providerMessageId: 'ABEGkZUTIXZ0Ago6jWqOZm-Sz0WD',
      senderPhone: '231770229690',
      messageType: 'text',
      text: 'TRACK DLV-ABC123',
      mediaReference: null,
      timestamp: 1718007189549,
    })
  })

  it('stores a provider media reference for non-text messages without ever touching a binary', () => {
    const event = parseGupshupWebhookEvent({
      app: 'DeliveryOS',
      type: 'message',
      payload: {
        id: 'msg-image-1',
        source: '231770229690',
        type: 'image',
        payload: { id: 'media-ref-1', url: 'https://gupshup.example/media/1', contentType: 'image/jpeg' },
        sender: { phone: '231770229690' },
      },
    })

    expect(event.kind).toBe('message')
    if (event.kind === 'message') {
      expect(event.text).toBeNull()
      expect(event.mediaReference).toEqual({ id: 'media-ref-1', url: 'https://gupshup.example/media/1', contentType: 'image/jpeg' })
    }
  })

  it('falls back to payload.source when sender.phone is absent', () => {
    const event = parseGupshupWebhookEvent({
      type: 'message',
      payload: { id: 'msg-2', source: '231880001111', type: 'text', payload: { text: 'HELP' } },
    })
    expect(event.kind).toBe('message')
    if (event.kind === 'message') {
      expect(event.senderPhone).toBe('231880001111')
    }
  })

  it('is unknown, not a crash, when the message payload is missing required fields', () => {
    expect(parseGupshupWebhookEvent({ type: 'message', payload: {} })).toEqual({ kind: 'unknown', rawType: 'message' })
  })
})

describe('parseGupshupWebhookEvent — status/DLR events', () => {
  it('parses a delivered event, preferring gsId over id as the correlation key', () => {
    const event = parseGupshupWebhookEvent({
      app: 'DeliveryOS',
      timestamp: 1718007200000,
      type: 'message-event',
      payload: { id: 'wamid.whatsapp-id', gsId: 'ee4a68a0-1203-4c85-8dc3-49d0b3226a35', type: 'delivered', destination: '231770229690' },
    })

    expect(event).toEqual({
      kind: 'message-event',
      appName: 'DeliveryOS',
      providerMessageId: 'ee4a68a0-1203-4c85-8dc3-49d0b3226a35',
      status: 'delivered',
      errorReason: null,
      timestamp: 1718007200000,
    })
  })

  it('falls back to id when gsId is absent (enqueued events have no gsId)', () => {
    const event = parseGupshupWebhookEvent({
      type: 'message-event',
      payload: { id: 'gs-msg-id-1', type: 'enqueued', destination: '231770229690' },
    })
    expect(event.kind).toBe('message-event')
    if (event.kind === 'message-event') {
      expect(event.providerMessageId).toBe('gs-msg-id-1')
      expect(event.status).toBe('enqueued')
    }
  })

  it('extracts an error reason from a failed event', () => {
    const event = parseGupshupWebhookEvent({
      type: 'message-event',
      payload: {
        id: 'gs-msg-id-2',
        type: 'failed',
        destination: '231770229690',
        payload: { code: 1008, reason: 'User is not Opted in and Inactive' },
      },
    })
    expect(event.kind).toBe('message-event')
    if (event.kind === 'message-event') {
      expect(event.errorReason).toBe('User is not Opted in and Inactive')
    }
  })
})

describe('parseGupshupWebhookEvent — unknown/other events', () => {
  it('never throws on an unrecognized event type (e.g. a future user-event notification)', () => {
    expect(parseGupshupWebhookEvent({ type: 'user-event', payload: { type: 'opted-in' } })).toEqual({
      kind: 'unknown',
      rawType: 'user-event',
    })
  })

  it('never throws on malformed/non-object input', () => {
    expect(parseGupshupWebhookEvent(null)).toEqual({ kind: 'unknown', rawType: null })
    expect(parseGupshupWebhookEvent('not an object')).toEqual({ kind: 'unknown', rawType: null })
    expect(parseGupshupWebhookEvent(undefined)).toEqual({ kind: 'unknown', rawType: null })
    expect(parseGupshupWebhookEvent([1, 2, 3])).toEqual({ kind: 'unknown', rawType: null })
  })
})
