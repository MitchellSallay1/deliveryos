# Security definer function audit (Phase 8)

Audit date: 2026-08-07  
Method: static review of `supabase/migrations` for `SECURITY DEFINER`, `search_path`, grants, and tenant checks.

Legend: **PASS** — acceptable for launch with documented ops; **FIXED** — changed in Phase 8; **REVIEW REQUIRED** — needs human verification in staging.

## RLS helpers (PASS)

| Function | search_path | AuthZ | Result |
|----------|-------------|-------|--------|
| `is_super_admin` | public | profile lookup | PASS |
| `user_company_ids` | public | auth.uid membership | PASS |
| `has_company_role` | public | role check | PASS |
| `assert_company_dispatcher` | public | role + auth | PASS |
| `assert_company_member` | public | membership | PASS |

## Tenant guards (PASS / FIXED)

| Function | Notes | Result |
|----------|-------|--------|
| `assert_company_operational` | company status | PASS |
| `assert_subscription_operational` | blocks new ops when past_due/expired | **FIXED** Phase 8 |
| `assert_merchant_marketplace` | feature + suspension | PASS |
| `assert_provider_marketplace` | opt-in profile | PASS |

## Business RPCs (sample — all reviewed PASS unless noted)

Deliveries, riders, payments, billing, fleet, inventory, marketplace, and admin RPCs use `SET search_path = public` and check `has_company_role` / `is_super_admin` / `assert_company_operational` before writes.

| Area | Representative functions | Result |
|------|-------------------------|--------|
| Deliveries | `create_delivery`, `assign_delivery_rider`, `transition_delivery_status` | PASS |
| Billing | `admin_record_billing_payment`, `admin_set_company_subscription` | PASS |
| Marketplace | `accept_marketplace_offer`, `record_marketplace_settlement` | PASS |
| Inventory | `inventory_adjust_stock`, `_inventory_apply_movement` | PASS (RPC-only writes) |
| API keys | `verify_api_key` | PASS — REVOKE PUBLIC, service_role only |
| Webhooks | `enqueue_webhook_event` | PASS — REVOKE PUBLIC |
| Email | `queue_email` | **FIXED** — REVOKE PUBLIC, service_role only |

## Public / anon (REVIEW REQUIRED)

| Function | Exposure | Mitigation | Result |
|----------|----------|------------|--------|
| `get_public_delivery_tracking` | anon | privacy fields only + rate limit | **FIXED** Phase 8 |
| `get_invitation_by_token` | authenticated | token scoped | REVIEW REQUIRED |
| `check_public_tracking_rate_limit` | internal | REVOKE PUBLIC | PASS |

## Scheduled / service (PASS)

| Function | Caller | Result |
|----------|--------|--------|
| `run_scheduled_maintenance_jobs` | service_role / jobs-scheduler | PASS |
| `log_api_auth_event` | service_role | PASS |
| `purge_old_rider_location_samples` | maintenance job | PASS |

## Grants hygiene

- Internal helpers (`enqueue_webhook_event`, `queue_email`, rate limit helpers): not granted to `authenticated`/`anon`.
- Application mutations: prefer `GRANT EXECUTE TO authenticated` on named RPCs only.

## Follow-ups (REVIEW REQUIRED)

1. Re-run this audit after each migration adding `SECURITY DEFINER`.
2. Confirm staging `EXPLAIN` on high-volume RPCs under load test plan.
3. Penetration test marketplace cross-tenant cases with `npm run test:db` in CI (GitHub Actions).
