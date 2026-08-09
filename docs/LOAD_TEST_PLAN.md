# Load test plan (non-production)

Do **not** run destructive tests against production.

## Targets (staging)

| Scenario | RPS | p95 latency | Error budget |
|----------|-----|-------------|--------------|
| Public tracking GET | 50 | < 300ms | < 0.1% |
| Delivery create (API) | 10 | < 800ms | < 0.5% |
| Rider GPS write | 30 | < 400ms | < 0.5% |
| Marketplace publish | 5 | < 1200ms | < 1% |

## Tools

- k6 or Artillery against staging `api-v1` and anon tracking RPC via Supabase REST/RPC proxy.

## Pass criteria

- No RLS leakage under concurrent tenants (run DB tests post-load).
- Webhook/SMS queues drain within 15 minutes after burst.

## Status

**UNVERIFIED** — plan only; execution requires staging environment.
