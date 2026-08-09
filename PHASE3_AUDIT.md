# Phase 3 — Production Hardening Audit

**Date:** August 7, 2026  
**Scope:** Phase 3 roadmap items (types, legacy removal, RBAC, team, SQL guards, payments, tests, performance)

---

## Before vs after (summary)

| Area | Before Phase 3 | After Phase 3 |
|------|----------------|---------------|
| **Types** | Hand-maintained partial `database.ts`, untyped Supabase client | `src/types/supabase.ts` + typed `createClient<Database>()`; `npm run gen:types` for linked projects |
| **Legacy code** | `backend/`, `frontend/`, `docker-compose.yml`, compiled Go binaries | Removed from repo |
| **RBAC** | UI mostly open to all authenticated members | `lib/rbac.ts`, `RequireAccess`, role-filtered nav, delivery write gates |
| **Team** | Manual SQL for `company_users` | Invitations table + RPCs + `/team` + `/invite/:token` |
| **Company status** | UI warnings only | `assert_company_operational()` in RPCs + RLS active checks on writes |
| **Subscription limits** | Rider cap trigger only | Monthly delivery cap in `create_delivery`; SMS credits raise structured errors; `features.sms` flag hook |
| **Payments** | Direct table UPDATE allowed via RLS | `payments_write` dropped; deposits/reconcile via RPC only |
| **Tests** | None | Vitest: RBAC, error mapping, auth/delivery schemas (7+ tests) |
| **Performance** | Single ~648KB JS chunk | Lazy routes + manual chunks (vendor/query/supabase); paginated deliveries |

---

## Production readiness scores

| Dimension | Before | After | Notes |
|-----------|--------|-------|-------|
| **Overall production readiness** | 58 | **72** | Hardening complete; billing/GPS still out of scope |
| **Security** | 62 | **78** | SQL enforcement + payment RLS + invitations; public tracking unchanged |
| **Performance** | 55 | **68** | Pagination + code splitting; DB integration tests still manual |
| **Scalability** | 52 | **62** | Paginated lists; Realtime still invalidates full query keys |
| **Maintainability** | 60 | **76** | Typed client, RBAC module, legacy removed |

---

## Migrations added (Phase 3)

| File | Purpose |
|------|---------|
| `supabase/migrations/20260307190000_phase3_hardening.sql` | Operational guards, subscription/SMS enforcement, team invitations + RPCs, payment RLS tightening, transition patches |

Apply with:

```bash
npx supabase db push
```

---

## Files changed / added (high level)

### Added
- `supabase/migrations/20260307190000_phase3_hardening.sql`
- `src/types/supabase.ts` (schema-aligned types; replace via `gen:types` when linked)
- `src/lib/rbac.ts`, `src/lib/rbac.test.ts`
- `src/lib/supabase-errors.ts`, `src/lib/supabase-errors.test.ts`
- `src/components/RequireAccess.tsx`
- `src/hooks/use-access.ts`, `src/hooks/use-team.ts`
- `src/services/team-service.ts`
- `src/pages/team/index.tsx`, `src/pages/invite.tsx`
- `vitest.config.ts`, `src/utils/auth-schemas.test.ts`, `src/utils/delivery-schemas.test.ts`
- `PHASE3_AUDIT.md`

### Modified
- `src/lib/supabase/client.ts` — typed client
- `src/types/database.ts` — re-exports from `supabase.ts`
- `src/types/delivery.ts`, services, hooks, pages (typed RPCs, pagination, RBAC, friendly errors)
- `src/App.tsx` — lazy routes, team/invite, `RequireAccess`
- `src/layouts/DashboardLayout.tsx` — RBAC nav
- `package.json`, `vite.config.ts`, `tsconfig.json`, `README.md`, `ARCHITECTURE.md`

### Removed
- `backend/` (entire Go API tree + binaries)
- `frontend/` (deprecated Vite app)
- `docker-compose.yml`
- `src/pages/placeholder.tsx`

---

## Remaining risks

1. **Database integration tests** — RLS and RPC guards are not yet exercised by automated pgTAP/Supabase test runner; rely on migration review + manual QA until CI DB is wired.
2. **Email delivery for invites** — Invite links are generated in UI; no transactional email provider (copy/paste link workflow).
3. **Public tracking RPC** — Still exposes customer name/addresses to anyone with tracking code (unchanged by design).
4. **`gen:types`** — Requires `supabase link`; committed `supabase.ts` must be refreshed after schema changes.
5. **Super admin promotion** — Still manual SQL on `profiles.is_super_admin`.
6. **Real SMS gateway** — Outbound remains stubbed in Postgres (`queue_outbound_sms`).
7. **Role vs rider profile** — Users with `company_role = rider` in `company_users` still need `claim_rider_profile` for delivery transitions tied to `riders.user_id`.

---

## Phase 3 checklist

| # | Item | Status |
|---|------|--------|
| 1 | Supabase types + typed services | Done (committed types + `gen:types` script) |
| 2 | Remove legacy code | Done |
| 3 | Role-based access | Done (nav + routes + action gates) |
| 4 | Team management | Done (invitations + owner UI) |
| 5 | Company status enforcement | Done (SQL) |
| 6 | Subscription enforcement | Done (deliveries/month, riders, SMS, feature flag hook) |
| 7 | Payment security | Done (RLS SELECT-only + RPC) |
| 8 | Testing | Partial (unit tests; DB integration pending) |
| 9 | Performance | Done (pagination, lazy routes, chunk split) |

---

## Next (Phase 4 — not started)

Billing, platform audit log, email invite provider, pgTAP/CI database tests, super-admin role management UI, subscription plan changes.
