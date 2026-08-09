# Admin security

## Principles

- Super Admin is **platform scope**, not a tenant membership.
- **No impersonation** — support uses read-only diagnostics (`admin_support_lookup`).
- **No secrets in UI** — API keys show prefix only; webhook secrets never listed.
- **Audit** — privileged changes call `log_audit_event` (e.g. `admin_set_company_status`).

## Privacy

- Delivery explorer masks customer phone via `mask_phone` in list RPC.
- Map shows rider GPS only — not destination addresses.
- Reveal full PII only when necessary via existing audited tenant tools — not bulk export from admin UI.

## MTN / payments

Do not mark MTN SMS, USSD, or MoMo operational until configuration and health checks pass. UI defaults to **not configured**.

## Future platform roles

Documented targets: `platform_operations`, `platform_finance`, `platform_support`, `platform_security`. Not implemented — only `is_super_admin` today.

## Regression

- Non–super-admin users redirected from `/admin` to `/dashboard` (`SuperAdminRoute`).
- Tenant users cannot call platform RPCs (forbidden from PostgreSQL).

Tests: `src/lib/admin-nav.test.ts`, `src/lib/rbac.test.ts`.
