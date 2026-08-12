# Scheduled jobs (production)

All schedules use **UTC**. Prefer Supabase Dashboard → Edge Functions → Cron, or an external scheduler with `CRON_SECRET`.

| Job | Function | Suggested schedule | Purpose |
|-----|----------|-------------------|---------|
| Orchestrator | `jobs-scheduler` | `*/5 * * * *` | Maintenance RPC + dispatch SMS/WhatsApp/webhooks/email |
| SMS (operational) | `sms-dispatch` | via orchestrator | Outbound SMS queue (rider/delivery notifications, delivery OTP) |
| SMS (auth OTP) | `auth-sms-hook` | Supabase Auth Send SMS Hook (event-driven, not cron) | Login/registration OTP delivery — **not** part of the orchestrator |
| WhatsApp | `whatsapp-dispatch` | via orchestrator | Outbound WhatsApp queue (Gupshup) — see [WHATSAPP.md](./WHATSAPP.md) |
| Webhooks | `webhooks-dispatch` | via orchestrator | Webhook retries |
| Email | `email-dispatch` | via orchestrator | Transactional email queue |

## `run_scheduled_maintenance_jobs` (Postgres RPC)

Invoked by `jobs-scheduler` with service role:

- Mark subscriptions `past_due` when period ended
- Mark invoices `overdue`
- Expire open marketplace requests/offers
- Purge GPS samples older than 48h

## Secrets

- `CRON_SECRET` — required header `x-cron-secret` on scheduled invocations
- `SMS_PROVIDER` — `stub` (dev) or `winaggregator` (production — current Liberia outbound SMS route, covers both MTN Liberia and Orange Liberia; see below)
- `WINAGGREGATOR_SMS_ENDPOINT` — optional override; defaults to `https://winaggregator-mtn.com/request/sms-service/1`
- `WINAGGREGATOR_SENDER_ID` — optional override; defaults to `DelivOS` (confirmed production sender ID)
- No API key/authentication header is required or sent by this integration — confirmed production behavior, not a gap.
- `SEND_SMS_HOOK_SECRET` — `auth-sms-hook` only; the `v1,whsec_<base64>` secret Supabase generates when the Send SMS Hook is enabled in the Auth dashboard. Never logged, never committed. Required — `auth-sms-hook` fails closed (503) without it.
- `EMAIL_PROVIDER` — `stub` or `http`
- `EMAIL_HTTP_ENDPOINT`, `EMAIL_HTTP_TOKEN`
- `GUPSHUP_API_KEY`, `GUPSHUP_APP_NAME`, `GUPSHUP_SOURCE_NUMBER` — `whatsapp-dispatch` only. Missing any of these makes the function respond 503 rather than send — see [WHATSAPP.md](./WHATSAPP.md).
- `GUPSHUP_WEBHOOK_SECRET` — `whatsapp-webhook` only; the token appended to the callback URL as `?token=...`.

### SMS provider notes (WinAggregator) — production-tested

- Confirmed production behavior, verified by a real end-to-end send: one shared endpoint delivers to both MTN Liberia and Orange Liberia numbers, sender ID `DelivOS`, no authentication header, destination normalized to bare `231XXXXXXXXX` (never `+231...`). Treated as a general Liberia SMS gateway, not MTN-specific, and not split by network — see `supabase/functions/_shared/sms-provider.ts`.
- Response body format is still undocumented; a successful HTTP response is treated as provider acceptance only. `provider_message_id` is left null on send (format unknown) — raw response text is logged to `sms_outbox.last_error` on failure only.
- **Two separate, intentionally decoupled delivery paths, both now live in production:**
  1. **Operational SMS** — rider job notifications, customer delivery updates, customer delivery OTP. Queued via `queue_outbound_sms` → `sms_outbox` → `sms-dispatch` (polled by `jobs-scheduler`). Verified end-to-end: `queue_outbound_sms` → `sms_outbox` → `sms-dispatch` → WinAggregator → handset.
  2. **Login/registration OTP** — Supabase Auth (`signInWithOtp`/`verifyOtp`) generates and verifies the OTP as usual; delivery happens via the Supabase **Send SMS Hook**, configured in the Auth dashboard to call `auth-sms-hook`, which reuses the same `WinAggregatorSmsProvider`. This path does **not** touch `sms_outbox` — it is event-driven (called directly by Supabase Auth), not polled by `jobs-scheduler`. Verified end-to-end in production: `supabase.auth.signInWithOtp` → Send SMS Hook → `auth-sms-hook` → WinAggregator → handset → OTP entered → `verifyOtp` → session issued.
- Do not merge these two paths — they exist separately on purpose (operational sends are queued/retried/rate-limited by our own logic; auth OTP is security-sensitive and delivered immediately, with Supabase Auth remaining the sole authority over generation/expiry/verification/sessions/rate limiting).

## Deploy

```bash
npx supabase functions deploy jobs-scheduler
npx supabase functions deploy sms-dispatch
npx supabase functions deploy webhooks-dispatch
npx supabase functions deploy email-dispatch
npx supabase functions deploy auth-sms-hook --no-verify-jwt
npx supabase functions deploy whatsapp-dispatch
npx supabase functions deploy whatsapp-webhook --no-verify-jwt
```
