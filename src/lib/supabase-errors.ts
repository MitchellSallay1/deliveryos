const ERROR_MESSAGES: Record<string, string> = {
  company_suspended:
    'This workspace is suspended. Contact DeliveryOS support or your administrator.',
  company_pending:
    'This workspace is pending activation. Dispatch actions are disabled until a platform admin activates your company.',
  company_not_operational: 'This workspace cannot perform that action right now.',
  company_inactive: 'This workspace is not active.',
  company_not_found: 'Company workspace not found.',
  subscription_expired: 'Your subscription period has ended. Renew billing to create new deliveries.',
  subscription_past_due: 'Your subscription is past due. Resolve billing to resume operational actions.',
  subscription_inactive: 'Your subscription is not active. You can still view history and billing.',
  trial_expired:
    'Your 7-day free trial has ended. Choose a plan to continue creating deliveries and riders.',
  marketplace_not_enabled: 'Marketplace features are not enabled on your plan.',
  marketplace_suspended: 'Marketplace access is suspended for this workspace.',
  rate_limited: 'Too many requests. Please wait and try again.',
  delivery_monthly_limit_reached:
    'Monthly delivery limit reached for your subscription plan. Upgrade or wait until next month.',
  rider_plan_limit_reached: 'Rider limit reached for your subscription plan.',
  sms_credits_exhausted: 'SMS credits exhausted. Top up credits to send messages.',
  feature_not_available: 'This requires a plan upgrade.',
  gps_not_enabled: 'Live GPS tracking is not included in your current plan.',
  multi_branch_not_enabled: 'Multiple locations require a plan upgrade.',
  not_a_vendor_company: 'This workspace is not set up as a Commerce vendor.',
  not_a_merchant_company: 'This workspace is not set up as a Commerce vendor.',
  vendor_not_available: 'This store is not currently accepting orders.',
  payment_not_confirmed: 'This order cannot be accepted until payment is confirmed.',
  cod_not_allowed: 'This store does not accept Cash on Delivery. Choose a different payment method.',
  invalid_payment_method: 'That payment method is not recognized.',
  payment_method_not_available: 'That payment method is not available yet. Please choose Cash on Delivery for now.',
  invalid_fulfillment_state: 'This action is not available for the order in its current state.',
  invalid_vendor_state: 'That is not a valid store status.',
  invitation_invalid: 'This invitation link is invalid or has expired.',
  invitation_email_mismatch:
    'Sign in with the email address that received this invitation.',
  invitation_phone_mismatch:
    'Sign in with the phone number that received this invitation.',
  forbidden: 'You do not have permission to perform this action.',
}

export function parseSupabaseError(error: unknown): string {
  if (!error || typeof error !== 'object') return 'Something went wrong'
  const msg = 'message' in error ? String((error as { message: string }).message) : ''
  for (const key of Object.keys(ERROR_MESSAGES)) {
    if (msg.includes(key)) return ERROR_MESSAGES[key]
  }
  return msg || 'Something went wrong'
}

export function supabaseErrorCode(error: unknown): string | null {
  if (!error || typeof error !== 'object') return null
  const msg = 'message' in error ? String((error as { message: string }).message) : ''
  for (const key of Object.keys(ERROR_MESSAGES)) {
    if (msg.includes(key)) return key
  }
  return null
}
