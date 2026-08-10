# MTN integration (placeholder)

A **native MTN API integration** (direct MTN SMS/USSD/MoMo credentials and endpoints) has not been built and MTN's own API specifications have not been provided — that remains a placeholder, as this doc's title says.

**SMS delivery itself, however, is live**: DeliveryOS sends outbound SMS (both auth OTP and operational) through **WinAggregator**, a third-party Liberia SMS gateway confirmed to deliver to both MTN Liberia and Orange Liberia handsets — see `docs/SCHEDULED_JOBS.md` and `supabase/functions/_shared/sms-provider.ts`. This is not the same thing as a native MTN integration; if MTN later provides its own direct API, that would be a separate, additional provider, not a replacement required to make SMS work.

**Do not hard-code** Twilio, Vonage, Resend, or MTN endpoints in core business logic.

## Two SMS concerns (keep separate)

| Concern | Purpose | Configuration surface |
|---------|---------|------------------------|
| **Auth OTP** | Supabase sign-in / sign-up | Supabase Auth phone provider or Auth SMS Hook |
| **Operational SMS** | Jobs, customer updates, button-phone commands, proof OTP | DeliveryOS edge functions / existing SMS adapters |

Shared **adapter infrastructure** at the provider layer is allowed later; **secrets and routing must stay logically separate**.

## Auth OTP — implemented and production-verified

1. Supabase Dashboard → Authentication → Phone provider — enabled.
2. Delivery via a **Send SMS Hook** Edge Function (`supabase/functions/auth-sms-hook/`) that calls **WinAggregator** — not MTN’s own API. Standard Webhooks-signed, fails closed without `SEND_SMS_HOOK_SECRET`.

Client entry point: `src/services/auth-sms-provider.ts` (wraps Supabase Auth only; no third-party keys in Vite).

A real end-to-end test succeeded in production: OTP sent, received via SMS, verified, session issued.

If MTN later provides its own direct API/credentials, `auth-sms-hook` can add MTN as an additional or alternate provider without changing Supabase Auth’s role (still the sole authority for OTP generation/expiry/verification/sessions).

## Operational SMS (existing)

Rider/customer SMS continues through existing operational paths (see rider channel docs) — also delivered via WinAggregator (`sms_outbox` → `sms-dispatch`), production-verified separately from and independently of the auth OTP path above. The two share the same underlying `WinAggregatorSmsProvider` transport but never the same queue.

## Mobile Money (not started)

MTN MoMo will plug into provider-neutral billing later:

- Subscription payments
- Marketplace settlement
- Merchant payments

Current manual billing/COD flows are unchanged. **No MoMo API implementation in this migration.**
