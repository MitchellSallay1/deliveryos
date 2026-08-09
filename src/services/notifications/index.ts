/** Notification channel abstraction (SMS, email, push). */

export type NotificationChannel = 'sms' | 'email' | 'push'

export type OutboundNotification = {
  channel: NotificationChannel
  companyId: string
  recipient: string
  body: string
  subject?: string
  deliveryId?: string
}

export interface NotificationProvider {
  readonly name: string
  send(message: OutboundNotification): Promise<{ ok: boolean; providerId?: string }>
}

/** SMS continues to flow through PostgreSQL `queue_outbound_sms` + sms-dispatch Edge Function. */
export class SmsNotificationProvider implements NotificationProvider {
  readonly name = 'sms'

  async send(message: OutboundNotification) {
    const { supabase } = await import('@/lib/supabase/client')
    const { error } = await supabase.rpc('queue_outbound_sms', {
      p_company_id: message.companyId,
      p_phone: message.recipient,
      p_body: message.body,
      p_delivery_id: message.deliveryId ?? null,
    })
    return { ok: !error, providerId: error ? undefined : 'queued' }
  }
}

export class EmailNotificationProvider implements NotificationProvider {
  readonly name = 'email'

  async send(_message: OutboundNotification) {
    return { ok: false, providerId: 'email_not_configured' }
  }
}

export class PushNotificationProvider implements NotificationProvider {
  readonly name = 'push'

  async send(_message: OutboundNotification) {
    return { ok: false, providerId: 'push_not_configured' }
  }
}

export function defaultNotificationRouter(): NotificationProvider[] {
  return [
    new SmsNotificationProvider(),
    new EmailNotificationProvider(),
    new PushNotificationProvider(),
  ]
}
