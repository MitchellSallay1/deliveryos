# Scheduled jobs (production)

All schedules use **UTC**. Prefer Supabase Dashboard → Edge Functions → Cron, or an external scheduler with `CRON_SECRET`.

| Job | Function | Suggested schedule | Purpose |
|-----|----------|-------------------|---------|
| Orchestrator | `jobs-scheduler` | `*/5 * * * *` | Maintenance RPC + dispatch SMS/webhooks/email |
| SMS | `sms-dispatch` | via orchestrator | Outbound SMS queue |
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
- `SMS_PROVIDER` — `stub` (dev) or `http` (production adapter)
- `SMS_HTTP_ENDPOINT`, `SMS_HTTP_TOKEN`
- `EMAIL_PROVIDER` — `stub` or `http`
- `EMAIL_HTTP_ENDPOINT`, `EMAIL_HTTP_TOKEN`

## Deploy

```bash
npx supabase functions deploy jobs-scheduler
npx supabase functions deploy sms-dispatch
npx supabase functions deploy webhooks-dispatch
npx supabase functions deploy email-dispatch
```
