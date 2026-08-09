# Platform operations

## Daily operator workflow

1. **Command Center** (`/admin`) — KPIs, alerts, trial funnel snapshot.
2. **Live Activity** (`/admin/live`) — delivery/rider/marketplace/queue counts (15s refresh).
3. **Alerts** — SMS spikes, dead webhooks, past-due subscriptions.
4. **Support lookup** (`/admin/support`) — company or tracking code diagnostics without impersonation.

## Finance

- **Revenue Center** (`/admin/revenue`) — MTD cash collected via `get_platform_billing_metrics`; not the same as subscription MRR estimate on command center.
- Subscriptions, invoices, payments — existing admin pages under Finance nav.

## Communications & MTN

- **Communications** — outbox/log aggregates only.
- **MTN Integrations** — readiness UI; status `not_configured` until verified provider config exists in DB/Edge.

## Jobs

Edge functions: `jobs-scheduler`, `sms-dispatch`, `webhooks-dispatch`, `email-dispatch`. Job run history is not in Postgres yet — use queue counts on System Health.

## Company actions (audited)

- Activate / suspend: `admin_set_company_status`
- SMS top-up: `admin_add_sms_credits`
- Plan changes: `/admin/subscriptions` + billing RPCs

## Exports

CSV on invoices/payments pages. Broader exports: use SQL/reporting against RPC aggregates — avoid downloading full tenant tables in the browser.
