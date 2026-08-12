# WhatsApp (Gupshup)

DeliveryOS WhatsApp is a first-class communication channel alongside SMS — not a replacement for it, and not connected to Auth OTP (which remains SMS-only via `auth-sms-hook`, untouched by this work).

## Account (non-secret metadata)

- App name: `DeliveryOS`
- Gupshup App ID: `3f4de7ad-d86c-4019-89d4-ca5db87826dc`
- WABA ID: `1299353838753622`
- Messaging limit (as of this phase): 250 customers / 24h
- The live production WhatsApp number lives in Gupshup and is **never hardcoded** — see `GUPSHUP_SOURCE_NUMBER` below.

## Architecture

```
Outbound:  business event -> dispatch_channel_notification (Postgres)
                            -> whatsapp_outbox
                            -> whatsapp-dispatch (Edge Function, polled by jobs-scheduler)
                            -> Gupshup -> WhatsApp recipient

Inbound:   WhatsApp user -> Gupshup -> whatsapp-webhook (Edge Function)
                                     -> whatsapp_inbound_messages (persist first)
                                     -> whatsapp_router_handle (router, runs after the 200 is sent)
                                     -> whatsapp_outbox (session reply)

Status:    Gupshup -> whatsapp-webhook (message-event) -> apply_whatsapp_status_event
                                                          -> whatsapp_outbox.status
```

SMS is completely independent: `sms_outbox` / `sms-dispatch` / WinAggregator are untouched. `dispatch_channel_notification` (Postgres) is the only new coupling point, and it only ever queues to ONE channel per call — see "Channel policy" below.

## Gupshup API contract (verified against docs.gupshup.io, not third-party sources)

- **Send session/free-form text**: `POST https://api.gupshup.io/wa/api/v1/msg`
- **Send template**: `POST https://api.gupshup.io/wa/api/v1/template/msg`
- Both: header `apikey: <key>`, `Content-Type: application/x-www-form-urlencoded`, body fields `channel=whatsapp`, `source`, `destination`, `src.name`, and `message` or `template` (a JSON string as the field value).
- Success response (`2xx`): `{"status":"submitted"|"success","messageId":"..."}` — this means **accepted for delivery**, not delivered. Real state (`sent`/`delivered`/`read`/`failed`) only ever comes later via the webhook.
- Implementation: `supabase/functions/_shared/gupshup-provider.ts`.

**Documentation gap, not guessed around**: Gupshup's webhook setup UI (`docs.gupshup.io/docs/set-webhookcallback-url`) is "paste a callback URL" — no custom header, shared secret, or signature mechanism is exposed to app customers, unlike Meta's own WhatsApp Cloud API (`X-Hub-Signature-256`). See "Webhook security" below for what this implementation uses instead.

## Provider configuration (Edge Function secrets — set these yourself, never in source)

| Secret | Used by | Purpose |
|---|---|---|
| `GUPSHUP_API_KEY` | `whatsapp-dispatch` | Gupshup API key |
| `GUPSHUP_APP_NAME` | `whatsapp-dispatch`, `whatsapp-webhook` | `src.name` on send; cross-checked against inbound webhook payloads |
| `GUPSHUP_SOURCE_NUMBER` | `whatsapp-dispatch` | Registered WA number, digits only — configured, never hardcoded, so a number change is a secret update, not a deploy |
| `GUPSHUP_WEBHOOK_SECRET` | `whatsapp-webhook` | Shared secret carried in the callback URL's `?token=` query param (see below) |

Missing any `whatsapp-dispatch` secret makes it respond `503 {"error":"not_configured"}` rather than send — the outbox keeps queuing safely either way, since `dispatch_channel_notification` already falls back to SMS for anything not truly WhatsApp-eligible.

## Webhook security model

**Re-verified** (production-security review pass, second independent research pass against `docs.gupshup.io/docs/webhooks-2`, `docs/set-webhookcallback-url`, and the SMS-API webhook guide): no signature/HMAC header, no configurable custom header, no verification/challenge token, and no documented source-IP range exists for app-level Gupshup WhatsApp webhooks — Gupshup's own setup guidance states only that "the webhook should have public access." This is a materially different situation from Meta's own WhatsApp Cloud API (`X-Hub-Signature-256`), which Gupshup as a BSP does not pass through to its app customers. Conclusion unchanged from the first pass: no stronger officially-supported mechanism exists to adopt, so the design below stands.

1. **Shared secret in the URL** (`?token=GUPSHUP_WEBHOOK_SECRET`) — the only place a secret CAN travel given Gupshup's "paste a URL" config UI. Fails closed (`503`) if unconfigured; constant-time compared (`verifySharedSecretQueryParam` in `_shared/carrier-auth.ts`, the same fail-closed pattern `sms-inbound`'s header-based secret already uses). **Never logged**: every `console.log`/`console.error` call in `whatsapp-webhook` logs a fixed string plus, at most, a Postgres/Supabase `.message` field — `req.url` and `req.headers` are never passed to a log call anywhere in this function (verified by direct grep of the source as part of this review). Supabase's own platform-level function-invocation logs may still capture the raw request line (URL + query string) outside this application's code — that's true of any query-param-carried secret on any platform, not something app code can suppress, and is exactly why this token should be treated as a real secret: rotate `GUPSHUP_WEBHOOK_SECRET` (and re-enter the new callback URL in the Gupshup dashboard) if you have reason to believe it's been exposed, and don't paste the callback URL into logs, chat, or tickets.
2. **App-name cross-check** — payload's `app` field, when present, must match `GUPSHUP_APP_NAME`.
3. **Idempotency** — inbound messages dedup on `provider_message_id` (unique index); status events apply forward-only (`apply_whatsapp_status_event` never lets a late `sent` event downgrade an already-observed `delivered`/`read`). A replayed webhook call cannot duplicate a user-visible reply or corrupt delivery-receipt state — verified by pgTAP (`whatsapp_phase_a.test.sql`).
4. **Scoped blast radius** — the ONLY functions `whatsapp-webhook` calls are `record_whatsapp_inbound_message` (writes only `whatsapp_inbound_messages`), `apply_whatsapp_status_event` (writes only an existing `whatsapp_outbox` row's own status columns — it cannot fabricate a "delivered" status for a message that doesn't already exist, since it requires a matching `provider_message_id`, which is Gupshup-assigned and not attacker-predictable), `whatsapp_router_handle` (internally: `apply_whatsapp_opt_command`, which writes only `whatsapp_preferences`; `get_public_delivery_tracking` and `get_public_commerce_order_status`, both pre-existing/new read-only, already-public-safe RPCs), and `queue_outbound_whatsapp_session_reply` (writes only `whatsapp_outbox`). None of these can write to `commerce_orders`, `deliveries`, `companies`, `auth.users`, billing tables, or any other tenant data — confirmed by reading every RPC this function calls, not assumed.

**Residual risk, stated precisely** (sharpened during this review — the earlier draft understated one concrete implication): anyone who obtains the callback URL (including its token) can POST a fabricated **inbound message** event with an arbitrary `sender.phone`, which the router treats as that phone's own message with no cryptographic proof of possession (WhatsApp/Gupshup's real infrastructure is normally what vouches for "this really came from this number" — a forged webhook bypasses that entirely, the same structural trust assumption `sms-inbound`'s existing shared-secret header already carries for SMS). Two concrete consequences, both already bounded:
- The system will send a real WhatsApp session reply (`HELP` text, a `TRACK` result, an `ORDER` result, or a STOP/START confirmation — never a business template, never arbitrary attacker-authored text) to that arbitrary number, from DeliveryOS's own WhatsApp number — usable for unsolicited-message annoyance of a third party, not for sending attacker-controlled content.
- If the attacker also knows or guesses a real order number, forging that order's own customer phone as the sender lets them retrieve that order's `fulfillment_status`/`payment_status`/`created_at` via `ORDER` — the same three fields `get_public_commerce_order_status` already returns to anyone who both knows the order number AND controls that phone number's real WhatsApp session; a forged webhook substitutes for the second half of that requirement. No other order field, no other customer's data without also knowing their specific order number, and no mutation of any kind.
A fabricated **status-event** cannot do either of these — it can only move an existing, attacker-unknown `whatsapp_outbox` row's status forward. This risk is judged acceptable for Phase A at Phase A's actual usage scope; if WhatsApp volume/sensitivity grows enough to warrant closing it, the fix is IP allowlisting at the Supabase/Vercel edge (outside this repo) or moving to a provider that supports request signing — not something to build speculatively now.

## Scheduler resilience

`jobs-scheduler` calls `whatsapp-dispatch` **outside** the `Promise.all` that runs `sms-dispatch`/`webhooks-dispatch`/`email-dispatch`, wrapped in its own `try`/`catch` with a 45s `AbortSignal.timeout`. A network failure, DNS error, or hang in `whatsapp-dispatch` resolves to a logged `{error: ...}` value in the scheduler's response instead of throwing — it cannot prevent the maintenance RPC or the three pre-existing dispatchers from running or being reported. `whatsapp-dispatch` itself: batches capped at 25 rows per invocation, retries capped at 5 attempts before `dead`, and — to prevent an overlapping invocation (e.g. a slow run still finishing when the next 5-minute trigger fires) from double-sending the same row — claims its selected batch by pushing `next_attempt_at` two minutes into the future for exactly those row ids *before* attempting to send any of them, so a concurrent second invocation's own `next_attempt_at <= now()` filter excludes them.

## Channel policy — WhatsApp vs SMS

`resolve_notification_channel(company_id, phone, semantic_event_key)` is the single decision point. It returns `'whatsapp'` **only** when all three are true:

1. `companies.whatsapp_notifications_enabled = true` for that company,
2. the phone has not opted out (`whatsapp_preferences`),
3. the semantic event's template is `status = 'approved'` **and** has a real `gupshup_template_id` set.

Every template seeded by this phase starts `'draft'` with `gupshup_template_id = NULL` — so today, for every company, this always returns `'sms'`. Turning WhatsApp on for real is a **data change** (approve a template with Gupshup/Meta, set its id in `whatsapp_template_registry`, flip a company's flag) — never a code change. `dispatch_channel_notification` wraps this: decide once, queue exactly one channel, fall back to SMS if the WhatsApp queue attempt itself fails (e.g. opted out) so the underlying business event is never silently un-notified.

Session (free-form) replies from the inbound router are queued separately (`queue_outbound_whatsapp_session_reply`) and are **not** gated by opt-out — opt-out governs business-initiated template notifications, not a direct reply to a message the user just sent.

## Inbound commands (Phase A — deterministic router, no AI)

`whatsapp_router_handle(phone, text)` in `20260310000000_whatsapp_phase_a_foundation.sql`:

| Command | Behavior |
|---|---|
| `TRACK <code>` | Calls `get_public_delivery_tracking` — the exact same rate-limited, public-safe RPC `/track/:code` uses. No new privileged lookup. |
| `ORDER <code>` | Calls `get_public_commerce_order_status`, which only returns data if the requesting phone matches the order's `customer_phone` — guessing an order number alone reveals nothing. |
| `HELP` / unrecognized | Static help text. |
| `STOP` | `apply_whatsapp_opt_command(phone, 'STOP')` — immediate, global (not per-company) opt-out. |
| `START` | Opts back in. |

Deliberately **not** reused: `apply_rider_channel_command` (the SMS/USSD rider accept/picked-up/delivered command set) — different audience (WhatsApp Phase A is customer-facing), different commands.

## Billing

WhatsApp sends are **not** metered against `sms_credits_included`/`sms_credits_purchased` — `dispatch_channel_notification` calls `queue_outbound_sms` (which decrements SMS credits) only when it actually queues SMS, never when it queues WhatsApp. `whatsapp_outbox` rows are the metering record for now (queryable per company); no fake WhatsApp credit balance was introduced. See the phase report for a recommended billing model.

## Admin visibility

`get_admin_communications_summary` (extended, same RPC the Communications page already called) now includes a `whatsapp` block: queued/sent/delivered/read/failed/inbound counts. `admin_get_whatsapp_summary`, `admin_list_whatsapp_templates`, and `admin_list_whatsapp_outbox_page` (message content and full phone number excluded — phone masked to last 4 digits) are available for a future dedicated admin page; only the summary card is wired into `/admin/communications` in Phase A.

## Tenant settings

`companies.whatsapp_notifications_enabled` / `whatsapp_sms_fallback_enabled` / `preferred_operational_channel` exist as data columns but have **no company-facing UI toggle yet** — with every template still `'draft'`, exposing a toggle would have no visible effect, which is exactly the "confusing configuration" this phase was told not to add. Server-side policy (`resolve_notification_channel`) remains authoritative regardless.
