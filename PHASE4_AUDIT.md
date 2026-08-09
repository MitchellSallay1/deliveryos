# Phase 4 — Monetization & Operations Audit

**Date:** August 7, 2026  
**Scope:** Subscription lifecycle, manual billing, invoices, usage metering, feature flags, admin billing portal, company billing UI, audit log, DB tests, tracking privacy, pagination/CSV, production runbook

---

## 1. What was implemented

| Area | Status |
|------|--------|
| Plan catalog upgrade (Starter / Business / Enterprise) | Done — columns on `subscriptions`, backfill migration |
| `company_subscriptions` lifecycle | Done — statuses, periods, backfill from legacy `subscription_id` |
| Manual billing records | Done — `subscription_billing_payments` + super-admin RPCs |
| Invoices | Done — table, statuses, admin create/mark paid, owner read via RLS |
| Usage metering | Done — `get_company_usage` (deliveries, riders, SMS, photo count) |
| Feature access | Done — `can_use_feature()`; wired to reports, POD, SMS, limits |
| Super Admin billing portal | Done — `/admin/plans`, `/subscriptions`, `/invoices`, `/payments`, `/audit`, metrics on overview |
| Company billing UI | Done — `/settings` owner section with usage, invoices, payments, upgrade copy |
| Platform audit log | Done — `audit_logs` + `log_audit_event`; admin/owner read policies |
| Public tracking privacy | Done — `get_delivery_tracking` generalized areas, no full addresses |
| Pagination / CSV | Done — invoices, payments, audit, companies (client paginate + search); CSV on admin invoices/payments |
| DB integration tests | Done — pgTAP (`supabase/tests/database/`) + Vitest (`tests/db/`, `npm run test:db`) |
| Production runbook | Done — `docs/PRODUCTION_RUNBOOK.md` |

**Not in Phase 4 (by design):** Stripe, mobile money gateways, GPS, public API, automated checkout.

---

## 2. Database changes

### Migrations

| File | Purpose |
|------|---------|
| `20260307200000_phase4_billing_schema.sql` | Enums, plan columns, `company_subscriptions`, `invoices`, `subscription_billing_payments`, `audit_logs` |
| `20260307200100_phase4_billing_functions.sql` | Usage, features, limits, tracking privacy, RLS, admin billing RPCs, paginated list RPCs, audit |

Apply:

```bash
npx supabase db push
```

---

## 3. Tables added

- `company_subscriptions`
- `invoices`
- `subscription_billing_payments` (subscription accounting — not COD `payments`)
- `audit_logs`

---

## 4. Functions added / materially changed

- `log_audit_event`
- `get_active_company_subscription`
- `company_deliveries_in_period`, `company_sms_consumed_in_period`
- `get_company_usage`
- `can_use_feature` (central feature gate)
- `get_delivery_tracking` (privacy-focused)
- `admin_upsert_plan`, `admin_set_company_subscription`, `admin_extend_subscription`
- `admin_create_invoice`, `admin_record_billing_payment`, `admin_mark_invoice_paid`
- `get_platform_billing_metrics`
- `list_invoices_page`, `list_billing_payments_page`, `list_audit_logs_page`, `list_plans_admin`
- Patches: `assert_subscription_delivery_limit`, `enforce_rider_plan_limit`, `register_delivery_photo`, `get_workspace_report` (+ core), `admin_add_sms_credits` (audit)

---

## 5. RLS changes

- Enabled RLS on billing tables; **SELECT only** for tenants (owners) and super admin.
- No direct INSERT/UPDATE on `audit_logs` for `authenticated`.
- `subscriptions` UPDATE restricted to super admin (plan edits also via RPC).
- Phase 3 payment protections retained (no `payments_write`).

---

## 6. Routes added

| Route | Audience |
|-------|----------|
| `/admin/plans` | Super Admin |
| `/admin/subscriptions` | Super Admin |
| `/admin/invoices` | Super Admin |
| `/admin/payments` | Super Admin |
| `/admin/audit` | Super Admin |

Existing `/settings` expanded for company owners (billing section).

---

## 7. UI changes

- `AdminLayout` nav extended for billing modules.
- `AdminBillingOverview` on platform overview.
- Admin pages: plans, subscriptions, invoices, payments, audit.
- `BillingSettingsSection` on Settings (owner).
- `/track/:code` uses new tracking fields (areas, company name).

---

## 8. Tests added

- `supabase/tests/database/phase4_billing.test.sql` — pgTAP schema/RLS/policy checks
- `tests/db/integration.test.ts` — tenant invoice isolation, suspended feature gate, payment UPDATE denial (requires `RUN_DB_TESTS=1` + local DB)
- Existing Vitest unit tests unchanged (`npm test`)

---

## 9. Security findings

| Finding | Severity | Notes |
|---------|----------|-------|
| Billing mutations only via SECURITY DEFINER RPCs + `is_super_admin()` | Good | Consistent with Phase 3 pattern |
| Owners see invoices/payments; dispatchers do not | Good | Role check in RLS |
| `log_audit_event` not granted to PUBLIC; clients should not insert audit rows directly | Good | Verify grants after deploy |
| `listPublicPlans` reads `subscriptions` table | Low | Catalog is non-secret; limits visible — acceptable for upgrade UX |
| Public tracking still reveals generalized areas | Low | By design; monitor for re-identification |
| DB integration tests require superuser DB URL | Info | Never use service role in frontend tests |

**Review focus for Phase 5:** every new SECURITY DEFINER RPC — `search_path`, least privilege grants.

---

## 10. Performance findings

- Usage RPC runs several aggregates per settings view — acceptable at current scale; consider materialized monthly usage if tenant count grows.
- Paginated list RPCs for invoices/payments/audit — good for admin tables.
- Admin companies list still loads all companies (client-side pagination) — OK for early Liberia rollout; add server page RPC if tenant count > ~500.

---

## 11. Remaining technical debt

- `src/types/supabase.ts` not regenerated for Phase 4 tables — run `npm run gen:types` when linked.
- Admin subscription UI: extend period uses placeholder (RPC `admin_extend_subscription` exists; wire UI).
- Create invoice / record payment from admin UI is minimal — RPCs exist; richer forms later.
- Audit coverage incomplete for every team/company action (some admin RPCs log; not all Phase 3 paths).
- Automated Stripe / MoMo — deferred.
- Company owner audit view — RPC allows owner company scope; no dedicated `/settings` audit tab yet.

---

## 12. Remaining production risks

- Migrations not applied on remote Supabase → billing UI RPC errors until `db push`.
- Manual billing depends on Super Admin discipline — no double-entry reconciliation UI.
- `npm run test:db` skipped in default CI unless local Supabase + `RUN_DB_TESTS=1`.
- SMS usage metering depends on `sms_logs` completeness.

---

## Production readiness scores

| Dimension | Phase 3 | Phase 4 | Notes |
|-----------|---------|---------|-------|
| **Architecture** | 74 | **78** | Provider-independent billing layer; legacy `subscription_id` bridged |
| **Security** | 78 | **82** | Billing RLS, audit log, tracking privacy |
| **Performance** | 68 | **70** | Admin pagination RPCs; companies still full fetch |
| **Maintainability** | 76 | **80** | Billing service/hooks; large SQL migration documented |
| **Scalability** | 62 | **66** | Usage computed on read; plan for caching |
| **Commercial readiness** | 45 | **72** | Manual Liberia billing + plans + invoices; no self-serve checkout |
| **Production readiness** | 72 | **78** | Runbook + tests; needs staged migration rollout |

**Overall production readiness:** Phase 3 **72** → Phase 4 **78**

---

## Phase 3 vs Phase 4 (summary)

| Area | Phase 3 | Phase 4 |
|------|---------|---------|
| Monetization | Plan slug on company + rider/delivery caps | Full subscription lifecycle, invoices, manual payments |
| Admin | Companies + analytics | Billing portal + metrics |
| Features | JSON `features` + SMS flag | `can_use_feature()` + plan columns |
| Audit | Ad hoc | `audit_logs` table |
| Tests | Unit only | Unit + pgTAP + optional DB integration |
| Ops docs | README / ARCHITECTURE | `PRODUCTION_RUNBOOK.md` |

---

**Phase 4 complete.** Do not start Phase 5 without explicit request.
