# Phase 7 Audit — Logistics Network & Marketplace

**Date:** 2026-08-07  
**Scope:** Merchant ↔ provider marketplace on existing DeliveryOS architecture (no redesign).

---

## 0. Database test execution (pre-Phase 7 gate)

| Command | Result |
|---------|--------|
| `npx supabase start` | **Failed** — Docker Desktop Linux engine pipe unavailable (`dockerDesktopLinuxEngine` not found). |
| `npx supabase db reset` | **Not run** (depends on local Supabase). |
| `npm run test:db` | **Failed** — `ECONNREFUSED 127.0.0.1:54322` (no local Postgres). |
| `npx supabase test db` | **Not run** (depends on local Supabase). |

**Infrastructure reason:** This Windows environment does not have Docker Desktop running; local Supabase cannot start. Migrations and pgTAP suite are present for CI/developer machines with Docker.

**Application verification (this environment):**

| Command | Result |
|---------|--------|
| `npm run build` | **Pass** |
| `npm test` | **Pass** (18 tests; DB integration suite skipped without `RUN_DB_TESTS` connectivity) |
| `npm run test:db` | **Fail** (no DB — expected offline) |

---

## 1. Features implemented

| Area | Status |
|------|--------|
| Company business types (`logistics_provider`, `merchant`, `hybrid`) | Done |
| Safe default for existing companies | Done (`DEFAULT logistics_provider`) |
| Merchant portal (requests, providers, billing nav) | Done |
| Adaptive navigation by business type | Done |
| `delivery_requests` + `delivery_offers` model | Done |
| Provider opt-in marketplace profile + zones | Done |
| Deterministic provider matching | Done |
| Merchant preferred provider + blocked relationships | Done |
| Offer accept → convert to `deliveries` (provider-owned) | Done |
| Marketplace fee rules + split computation | Done |
| `marketplace_transactions` + ledger entries | Done |
| Manual marketplace settlement (admin RPC) | Done |
| Provider reviews (post-delivery, unique per delivery) | Done |
| Marketplace disputes (simple records) | Done |
| Cancellation rules (pre/post accept guards) | Done |
| Feature flags on plans + `can_use_feature` | Done |
| Registration business type question | Done |
| Admin marketplace metrics + suspension | Done |
| Paginated list RPCs | Done |
| Marketplace analytics RPC | Done |
| Public API marketplace endpoints | Done |
| Webhook event enqueue for marketplace | Done |
| pgTAP `phase7_marketplace.test.sql` | Done |
| Vitest marketplace RBAC tests | Done |

**Not built (per spec):** AI matching, dynamic pricing, MoMo/bank automation, rider marketplace exposure, payroll, cross-border, enterprise SSO.

---

## 2. Database changes

- Enum types: business type, request/offer status, relationship type, fee model, transaction status, ledger accounts, dispute reason/status
- `companies.business_type`, `companies.marketplace_suspended`
- Plan columns: `marketplace_access`, `merchant_portal`, `provider_network`, `marketplace_api`
- `deliveries.merchant_company_id`, `deliveries.delivery_request_id`
- Marketplace tables: profiles, zones, requests, offers, relationships, fee rules, transactions, ledger, settlements, reviews, disputes

---

## 3. Migrations

| File | Purpose |
|------|---------|
| `20260307230000_phase7_marketplace_schema.sql` | Schema, indexes, RLS enable |
| `20260307230100_phase7_marketplace_functions.sql` | RPCs, RLS policies, plan/can_use_feature patches |

---

## 4. RLS changes

- Tenant SELECT on requests (merchant + selected provider + super admin)
- Offers visible to assigned provider and owning merchant only
- Transactions/ledger readable by involved merchants/providers
- Fee rules: read active rules; write super admin only
- Settlements: super admin read; writes via RPC only
- Merchant read on `deliveries` via `merchant_company_id` policy

---

## 5. RPC functions (high level)

- Onboarding: `create_company_with_owner` (+ `p_business_type`)
- Merchant: `create_delivery_request`, `publish_delivery_request`, `cancel_delivery_request`, `list_delivery_requests_page`
- Provider: `upsert_provider_marketplace_profile`, `set_provider_marketplace_zones`, `list_marketplace_jobs_page`, `accept_marketplace_offer`, `reject_marketplace_offer`
- Relationships: `upsert_merchant_provider_relationship`, `list_marketplace_providers_page`
- Finance: `compute_marketplace_fee_split`, `record_marketplace_settlement`, `admin_upsert_marketplace_fee_rule`
- Quality: `create_provider_review`, `create_marketplace_dispute`
- Admin: `admin_set_marketplace_suspension`, `get_marketplace_analytics`
- Patches: `can_use_feature`, `admin_upsert_plan`

---

## 6. Marketplace architecture

```
Merchant company → delivery_request → delivery_offers → Provider company
                              ↓ accept
                    deliveries (provider company_id)
                    merchant_company_id + delivery_request_id
                              ↓
              Existing rider/GPS/SMS/COD/webhooks pipeline
```

DeliveryOS remains **technology/network**, not operational courier.

---

## 7. Merchant portal

Routes: `/merchant/requests`, `/marketplace/providers`, `/billing`  
Hidden for pure merchants: riders, live map, operations (via `isNavVisibleForBusinessType`).

---

## 8. Provider portal

Routes: `/marketplace/jobs`  
Settings: `MarketplaceProviderSettings` (opt-in, accepting jobs, fees)  
Directory participation requires explicit `marketplace_enabled`.

---

## 9. Financial ledger

Immutable transaction row per request; ledger lines for merchant payable, provider receivable, platform revenue; manual settlement with idempotency guard.

---

## 10. API extensions

Edge function `api-v1`: delivery-requests CRUD/cancel; marketplace jobs list/accept with scoped permissions.

---

## 11. Webhook extensions

Merchant/provider marketplace events enqueued via existing `enqueue_webhook_event` HMAC pipeline (see `docs/WEBHOOKS.md`).

---

## 12. Tests

| Suite | Status |
|-------|--------|
| `src/lib/marketplace-rbac.test.ts` | Pass |
| `supabase/tests/database/phase7_marketplace.test.sql` | Ready (requires local Supabase) |
| `tests/db/integration.test.ts` marketplace RLS cases | **Not extended** — blocked on Docker/DB |

**Recommended local run (when Docker available):**

```bash
npx supabase start
npx supabase db reset
npm run test:db
npx supabase test db
```

---

## 13. Security findings

| Finding | Severity | Mitigation |
|---------|----------|------------|
| Cross-tenant offer visibility | High | RLS + RPC scoping; list jobs redacts pre-acceptance PII |
| Double settlement | High | Unique settlement per transaction + RPC guard |
| Suspended tenant participation | Medium | `marketplace_suspended` + assert helpers |
| Direct table writes on financial rows | Medium | No client INSERT policies on transactions; RPC-only creation |
| API accept wrong offer | Medium | Edge verifies `provider_company_id` on offer |

---

## 14. Performance findings

| Load | Notes |
|------|-------|
| 1k requests/day | Single-region Postgres + indexed `(merchant_company_id, status)` adequate |
| 10k/day | Publish loop capped at 50 providers/request; monitor notification/webhook outbox |
| 100k/day | Consider async matching worker (Edge/cron) for offer fan-out; batch webhooks |
| 1M/day | Partition `delivery_requests`/`delivery_offers` by month; read replicas for analytics RPC |

No microservices introduced.

---

## 15. Remaining risks

- First-eligible auto-accept mode not fully productized (architecture supports preferred + manual accept MVP)
- Merchant-owned delivery team path for hybrid uses existing `create_delivery` UI only (no unified wizard)
- Extended marketplace RLS integration tests pending local Supabase
- Generated types partially hand-patched (`npm run gen:types` after migrate recommended)
- Notification templates for marketplace events rely on existing outbox patterns (content tuning needed)

---

## 16. Technical debt

- Add Vitest + pgTAP cases for cross-tenant offer isolation when DB CI available
- Merchant tracking view for converted deliveries (currently provider-scoped delivery + public track link)
- Admin UI for fee rules and dispute review (RPC exists; UI minimal)
- Hook `delivery_request.completed` on delivery terminal states

---

## Scores (1–10)

| Dimension | Phase 6 | Phase 7 |
|-----------|---------|---------|
| Architecture | 8 | 8 |
| Security | 8 | 7.5 |
| Performance | 7.5 | 7.5 |
| Maintainability | 8 | 7.5 |
| Scalability | 7 | 7.5 |
| Commercial readiness | 7 | 8 |
| Marketplace readiness | — | 7 |
| Production readiness | 7 | 7 |

**Phase 7 summary:** Marketplace layer added without forking delivery execution. Production rollout requires Docker-backed migration apply, full DB test pass, and operator runbook for manual settlements.

---

**Phase 8 not started.** Stop here per instructions.
