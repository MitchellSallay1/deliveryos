import { useCallback, useEffect, useState } from 'react'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { maskPhoneForDisplay, normalizePhoneE164, isValidLiberiaMobile } from '@/lib/phone'
import { sendPhoneOtp, verifyPhoneOtp, syncProfileFromAuth } from '@/services/auth-service'

const RESEND_COOLDOWN_SEC = 60

type Step = 'phone' | 'otp'

type PhoneOtpFlowProps = {
  title?: string
  description?: string
  submitLabel?: string
  onVerified: () => void | Promise<void>
  disabled?: boolean
}

export function PhoneOtpFlow({
  title = 'Phone number',
  description = 'We will text you a one-time verification code.',
  submitLabel = 'Send verification code',
  onVerified,
  disabled,
}: PhoneOtpFlowProps) {
  const [step, setStep] = useState<Step>('phone')
  const [phoneInput, setPhoneInput] = useState('')
  const [phoneE164, setPhoneE164] = useState('')
  const [otp, setOtp] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [cooldown, setCooldown] = useState(0)

  useEffect(() => {
    if (cooldown <= 0) return
    const t = window.setInterval(() => setCooldown((c) => Math.max(0, c - 1)), 1000)
    return () => window.clearInterval(t)
  }, [cooldown])

  const sendCode = useCallback(async () => {
    setError(null)
    const normalized = normalizePhoneE164(phoneInput)
    if (!isValidLiberiaMobile(normalized)) {
      setError('Enter a valid Liberia mobile number (9 digits, e.g. 088… or +231…).')
      return
    }
    setLoading(true)
    try {
      const result = await sendPhoneOtp(normalized)
      setPhoneE164(result.phoneE164)
      setStep('otp')
      setCooldown(RESEND_COOLDOWN_SEC)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not send code.')
    } finally {
      setLoading(false)
    }
  }, [phoneInput])

  async function onVerify(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    if (!otp.trim() || otp.trim().length < 4) {
      setError('Enter the verification code from your SMS.')
      return
    }
    setLoading(true)
    try {
      await verifyPhoneOtp(phoneE164, otp)
      await syncProfileFromAuth()
      await onVerified()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Verification failed.')
    } finally {
      setLoading(false)
    }
  }

  if (step === 'phone') {
    return (
      <div className="space-y-4">
        <div>
          <h3 className="text-base font-medium">{title}</h3>
          <p className="text-sm text-[var(--color-muted)]">{description}</p>
        </div>
        {error && <p className="text-sm text-red-600">{error}</p>}
        <div className="space-y-2">
          <Label htmlFor="phone">Phone number</Label>
          <Input
            id="phone"
            name="phone"
            type="tel"
            inputMode="tel"
            autoComplete="tel"
            placeholder="+231 88 123 4567"
            value={phoneInput}
            onChange={(e) => setPhoneInput(e.target.value)}
            disabled={disabled || loading}
            required
          />
        </div>
        <Button type="button" className="w-full" disabled={disabled || loading} onClick={() => void sendCode()}>
          {loading ? 'Sending…' : submitLabel}
        </Button>
      </div>
    )
  }

  return (
    <form className="space-y-4" onSubmit={onVerify}>
      <div>
        <h3 className="text-base font-medium">Verification code</h3>
        <p className="text-sm text-[var(--color-muted)]">
          We&apos;ve sent a verification code to:
        </p>
        <p className="mt-1 font-medium">{maskPhoneForDisplay(phoneE164)}</p>
      </div>
      {error && <p className="text-sm text-red-600">{error}</p>}
      <div className="space-y-2">
        <Label htmlFor="otp">Enter code</Label>
        <Input
          id="otp"
          name="otp"
          inputMode="numeric"
          autoComplete="one-time-code"
          placeholder="123456"
          value={otp}
          onChange={(e) => setOtp(e.target.value.replace(/\D/g, '').slice(0, 8))}
          disabled={disabled || loading}
          required
        />
      </div>
      <Button type="submit" className="w-full" disabled={disabled || loading}>
        {loading ? 'Verifying…' : 'Verify & continue'}
      </Button>
      <div className="flex flex-wrap gap-3 text-sm">
        <button
          type="button"
          className="text-[var(--color-primary)] hover:underline disabled:opacity-50"
          disabled={loading || cooldown > 0}
          onClick={() => void sendCode()}
        >
          {cooldown > 0 ? `Resend code (${cooldown}s)` : 'Resend code'}
        </button>
        <button
          type="button"
          className="text-[var(--color-muted)] hover:underline"
          disabled={loading}
          onClick={() => {
            setStep('phone')
            setOtp('')
            setError(null)
          }}
        >
          Change phone number
        </button>
      </div>
    </form>
  )
}
