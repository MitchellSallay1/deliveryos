import { useState } from 'react'
import { usePageMeta } from '@/hooks/use-page-meta'
import { MarketingPageShell } from '@/layouts/MarketingLayout'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { Button } from '@/components/ui/Button'
import { submitContactForm } from '@/services/contact-form-service'

export function ContactPage() {
  usePageMeta({ title: 'Contact', path: '/contact' })
  const [intent, setIntent] = useState<'sales' | 'demo' | 'support'>('sales')
  const [status, setStatus] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    setError(null)
    setStatus(null)
    const fd = new FormData(e.currentTarget)
    setLoading(true)
    try {
      const result = await submitContactForm({
        intent,
        name: String(fd.get('name') || ''),
        company: String(fd.get('company') || ''),
        phone: String(fd.get('phone') || ''),
        email: String(fd.get('email') || '') || undefined,
        businessType: String(fd.get('businessType') || ''),
        message: String(fd.get('message') || ''),
      })
      if (result.mode === 'provider_ready') {
        setStatus(
          'Thank you. Configure VITE_CONTACT_FORM_URL in production to deliver submissions to your team. Your message was not transmitted in this environment.',
        )
      } else {
        setStatus('Thank you — we will respond shortly.')
      }
      e.currentTarget.reset()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Something went wrong.')
    } finally {
      setLoading(false)
    }
  }

  return (
    <MarketingPageShell className="py-16">
      <h1 className="text-4xl font-semibold tracking-tight text-zinc-900">Contact us</h1>
      <p className="mt-4 max-w-xl text-lg text-zinc-600">Phone is our primary contact. Tell us about your operation.</p>

      <div className="mt-8 flex flex-wrap gap-2">
        {(
          [
            ['sales', 'Contact sales'],
            ['demo', 'Request demo'],
            ['support', 'Technical / support'],
          ] as const
        ).map(([id, label]) => (
          <button
            key={id}
            type="button"
            onClick={() => setIntent(id)}
            className={`rounded-lg px-4 py-2 text-sm font-medium ${intent === id ? 'bg-zinc-900 text-white' : 'bg-zinc-100 text-zinc-700'}`}
          >
            {label}
          </button>
        ))}
      </div>

      <form className="mt-10 max-w-xl space-y-4" onSubmit={onSubmit}>
        <Field label="Name" name="name" required />
        <Field label="Company" name="company" required />
        <Field label="Phone" name="phone" type="tel" required />
        <Field label="Email (optional)" name="email" type="email" />
        <Field label="Business type" name="businessType" placeholder="Courier, merchant, enterprise…" required />
        <div className="space-y-2">
          <Label htmlFor="message">Message</Label>
          <textarea
            id="message"
            name="message"
            required
            rows={5}
            className="flex w-full rounded-lg border border-zinc-300 px-3 py-2 text-sm"
          />
        </div>
        {error && <p className="text-sm text-red-600">{error}</p>}
        {status && <p className="text-sm text-zinc-700">{status}</p>}
        <Button type="submit" variant="accent" disabled={loading}>
          {loading ? 'Sending…' : 'Send message'}
        </Button>
      </form>
    </MarketingPageShell>
  )
}

function Field(props: React.ComponentProps<typeof Input> & { label: string; name: string }) {
  const { label, name, ...rest } = props
  return (
    <div className="space-y-2">
      <Label htmlFor={name}>{label}</Label>
      <Input id={name} name={name} {...rest} />
    </div>
  )
}
