# MTN integration (placeholder)

MTN SMS and Mobile Money credentials/API specifications will be provided later.

**Do not hard-code** Twilio, Vonage, Resend, or MTN endpoints in core business logic.

## Two SMS concerns (keep separate)

| Concern | Purpose | Configuration surface |
|---------|---------|------------------------|
| **Auth OTP** | Supabase sign-in / sign-up | Supabase Auth phone provider or Auth SMS Hook |
| **Operational SMS** | Jobs, customer updates, button-phone commands, proof OTP | DeliveryOS edge functions / existing SMS adapters |

Shared **adapter infrastructure** at the provider layer is allowed later; **secrets and routing must stay logically separate**.

## Auth OTP (MTN TBD)

1. Configure Supabase Dashboard → Authentication → Phone provider.
2. Either:
   - Use Supabase’s supported SMS gateway with MTN-compatible credentials when documented, **or**
   - Implement a **Send SMS Hook** (Edge Function) that calls MTN once API spec/credentials exist.

Client entry point: `src/services/auth-sms-provider.ts` (wraps Supabase Auth only; no third-party keys in Vite).

> **MTN SMS provider/API details to be configured once credentials/specification are provided.**

Until then, OTP UI and flows are testable with mocks; **end-to-end delivery is not verified**.

## Operational SMS (existing)

Rider/customer SMS continues through existing operational paths (see rider channel docs).

Future MTN adapter may serve both auth hook and operational sends via shared low-level client — not mixed business logic.

## Mobile Money (not started)

MTN MoMo will plug into provider-neutral billing later:

- Subscription payments
- Marketplace settlement
- Merchant payments

Current manual billing/COD flows are unchanged. **No MoMo API implementation in this migration.**
