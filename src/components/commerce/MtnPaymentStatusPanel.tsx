import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { Card, CardContent } from '@/components/ui/Card'
import { usePaymentAttempt } from '@/hooks/use-payment-attempts'
import { formatLrdFromCents } from '@/utils/delivery-schemas'

/**
 * The 5 customer-facing states the phase brief requires stay visually and
 * textually distinct — most importantly, 'unknown' (payment_attempts.state
 * = 'unknown') must NEVER be presented as "payment failed, try again": this
 * system does not know whether the customer was charged, and inviting a
 * retry here risks a genuine double charge. See docs/MTN_MOMO_PAYMENTS.md
 * "Customer retry policy."
 */
function statusCopy(state: string): { title: string; description: string; badge: 'default' | 'success' | 'warning' | 'danger' } {
  switch (state) {
    case 'created':
    case 'requesting':
      return {
        title: 'Waiting for MTN approval',
        description: 'Approve the payment prompt on your phone. This can take up to a minute.',
        badge: 'default',
      }
    case 'pending':
      return {
        title: 'Payment still processing',
        description: 'MTN is still processing this payment. We will update this automatically — no need to refresh.',
        badge: 'warning',
      }
    case 'successful':
      return {
        title: 'Payment successful',
        description: 'Your payment was received.',
        badge: 'success',
      }
    case 'failed':
      return {
        title: 'Payment failed',
        description: 'The payment was not completed. You can try again.',
        badge: 'danger',
      }
    case 'unknown':
    default:
      return {
        title: "We're confirming your payment",
        description:
          "We could not confirm the result of this payment attempt with MTN. We are NOT saying it failed — if you were charged, we will reconcile it. Please do not attempt another payment for this order yet; contact support if this doesn't resolve.",
        badge: 'warning',
      }
  }
}

export function MtnPaymentStatusPanel({
  attemptId,
  onRetry,
  retrying,
}: {
  attemptId: string
  onRetry?: () => void
  retrying?: boolean
}) {
  const { data: attempt, isLoading } = usePaymentAttempt(attemptId)

  if (isLoading || !attempt) {
    return (
      <Card>
        <CardContent className="pt-6 text-sm text-[var(--color-muted)]">Loading payment status…</CardContent>
      </Card>
    )
  }

  const copy = statusCopy(attempt.state)
  const canRetry = attempt.state === 'failed' && !!onRetry

  return (
    <Card>
      <CardContent className="space-y-3 pt-6">
        <div className="flex items-center justify-between gap-2">
          <p className="text-sm font-semibold">{copy.title}</p>
          <Badge variant={copy.badge}>{attempt.state}</Badge>
        </div>
        <p className="text-sm text-[var(--color-muted)]">{copy.description}</p>
        <p className="text-xs text-[var(--color-muted)]">
          {formatLrdFromCents(attempt.gross_amount_cents)} · MTN MoMo {attempt.payer_msisdn.replace(/^(\+231\d{2})\d+(\d{4})$/, '$1***$2')}
        </p>
        {canRetry && (
          <Button type="button" size="sm" onClick={onRetry} disabled={retrying}>
            {retrying ? 'Starting new payment…' : 'Try again'}
          </Button>
        )}
      </CardContent>
    </Card>
  )
}
