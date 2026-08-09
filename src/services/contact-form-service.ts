export type ContactFormPayload = {
  name: string
  company: string
  phone: string
  email?: string
  businessType: string
  message: string
  intent: 'sales' | 'demo' | 'support'
}

export type ContactSubmitResult =
  | { ok: true; mode: 'endpoint' }
  | { ok: true; mode: 'provider_ready' }

/**
 * Submits contact form when VITE_CONTACT_FORM_URL is configured (e.g. Formspree, custom Edge).
 * Otherwise returns provider-ready success without exposing secrets.
 */
export async function submitContactForm(payload: ContactFormPayload): Promise<ContactSubmitResult> {
  const url = import.meta.env.VITE_CONTACT_FORM_URL as string | undefined
  if (url?.trim()) {
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...payload, source: 'deliveryos-marketing' }),
    })
    if (!res.ok) throw new Error('Could not send message. Try again or email us directly.')
    return { ok: true, mode: 'endpoint' }
  }
  return { ok: true, mode: 'provider_ready' }
}
