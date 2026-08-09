# Scaling guidance

## Companies

| Scale | Guidance |
|-------|----------|
| 100 | Single Supabase project, default indexes sufficient |
| 1,000 | Monitor slow queries; add read replicas if reporting heavy |
| 10,000 | Partition high-volume tables (audit, webhook, GPS samples); dedicated analytics |

## Deliveries / day

| Volume | Bottleneck | Mitigation |
|--------|------------|------------|
| 10K | Delivery list queries | Pagination enforced; indexes on `(company_id, created_at)` |
| 100K | Webhook/SMS fan-out | Batch dispatch; increase scheduler frequency |
| 1M | Marketplace offer fan-out | Async matching worker; cap providers per request (50) |

No Redis/microservices required at initial launch. Revisit when CI load tests show p95 RPC > 500ms sustained.

See `docs/LOAD_TEST_PLAN.md`.
