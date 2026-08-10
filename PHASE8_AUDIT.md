# Phase 8 Audit — Production Launch & Validation

**Date:** 2026-08-07  
**Supabase CLI (local attempt):** 2.112.0

---

## 1. Database test execution (BLOCKING)

| Command | Result |
|---------|--------|
| `npx supabase start` | **BLOCKED** — Docker Desktop Linux engine unavailable on this machine |
| `npx supabase db reset` | **Not run** |
| `npm run test:db` | **Failed** — `ECONNREFUSED 127.0.0.1:54322` |
| `npx supabase test db` | **Not run** |

### CI strategy (implemented)

GitHub Actions workflow `.github/workflows/ci.yml`:

- Job `app`: `npm ci`, lint, `npm test`, `npm run build`
- Job `database`: `supabase start`, `db reset`, `npm run test:db`, `supabase test db`

**Production launch blocker:** DB/RLS tests must pass in CI (or local Docker) before claiming production-ready.

### Local test counts (this environment)

| Suite | Total | Passed | Failed | Skipped |
|-------|-------|--------|--------|---------|
| Vitest (all) | 29 | 18 | 0 | 11 |
| Vitest `test:db` | 12 | 1 | 2 suites (connection) | 11 |

Execution date: 2026-08-07.

---

## 2. What changed in Phase 8

| Area | Change |
|------|--------|
| Migrations | `20260307240000_phase8_production_schema.sql`, `20260307240100_phase8_production_functions.sql` |
| RLS tests | `tests/db/rls-security.test.ts` |
| Tracking | Stronger codes, rate limit RPC, client key on public track |
| API | Body size limit, correlation ID, sanitized errors, auth event logging |
| Webhooks | Timestamp header, timeout, response logging, admin retry UI |
| SMS/Email | WinAggregator SMS transport (`SMS_PROVIDER=winaggregator`), retry/dead-letter on SMS; `email_outbox` + `email-dispatch` |
| Jobs | `jobs-scheduler`, `run_scheduled_maintenance_jobs`, `docs/SCHEDULED_JOBS.md` |
| Subscriptions | `assert_subscription_operational` on new deliveries; past_due automation |
| Onboarding | `get_company_onboarding_status`, dashboard checklist |
| Admin | System status, webhook failures |
| Legal | `/terms`, `/privacy` placeholders |
| CI | `.github/workflows/ci.yml` |
| Docs | SECURITY_FUNCTION_AUDIT, DISASTER_RECOVERY, DATA_RETENTION, LAUNCH_CHECKLIST, SCALING, LOAD_TEST_PLAN |

---

## 3. Security fixes

- Public tracking rate limiting (`check_public_tracking_rate_limit`)
- Tracking code entropy increased (6 bytes random)
- API error message sanitization
- Subscription guard for new operational mutations without blocking login/history
- Email queue service-role only

See `docs/SECURITY_FUNCTION_AUDIT.md`.

---

## 4. SMS / email status

| Channel | Dev | Production |
|---------|-----|------------|
| SMS (operational) | `SMS_PROVIDER=stub` | `SMS_PROVIDER=winaggregator` — **production-tested end-to-end** (`queue_outbound_sms` → `sms_outbox` → `sms-dispatch` → WinAggregator → handset confirmed). One shared endpoint delivers to both MTN Liberia and Orange Liberia, sender ID `DelivOS`, no authentication header. Response body format is still unconfirmed beyond HTTP status. |
| SMS (auth OTP) | n/a (Supabase Auth handles OTP locally in dev unless the hook is also configured) | Supabase Auth Send SMS Hook → `auth-sms-hook` → WinAggregator — **production-tested end-to-end**: real OTP received via SMS, account setup completed, code verified, session issued. |
| Email | `EMAIL_PROVIDER=stub` | `EMAIL_PROVIDER=http` + `EMAIL_HTTP_ENDPOINT` (**config UNVERIFIED**) |

Login/registration OTP uses the **same WinAggregator provider** as operational SMS, but through a separate, intentionally decoupled path: Supabase Auth's Send SMS Hook (`auth-sms-hook`), not `sms_outbox`/`sms-dispatch`. Supabase Auth remains the sole authority for OTP generation, expiry, verification, sessions, and rate limiting — `auth-sms-hook` only delivers the SMS. See `docs/SCHEDULED_JOBS.md` for the full architecture.

Team invite emails enqueue via `create_company_invitation` → `queue_email`.

---

## 5. Observability

- Admin `get_platform_health_snapshot` + `/admin/system-status`
- API auth failure table `api_auth_events`
- Frontend error tracking: **UNVERIFIED** (integrate Sentry/LogRocket in Vercel)

---

## 6. Backup / restore

Documented in `docs/DISASTER_RECOVERY.md`. Live restore drill: **UNVERIFIED**.

---

## 7. Remaining blockers

1. **Docker/local or CI-green database tests** (RLS suite + pgTAP)
2. ~~Production SMS: confirm WinAggregator auth requirements and run a real end-to-end send test~~ — **done**, both the operational path (`sms_outbox` → `sms-dispatch`) and the auth OTP path (`auth-sms-hook`) are production-verified. Remaining: production email HTTP provider credentials and send test
3. Legal review of terms/privacy placeholders
4. Staging load test execution
5. External error monitoring wiring

---

## 8. Scores (1–10)

| Dimension | Phase 7 | Phase 8 |
|-----------|---------|---------|
| Architecture | 8 | 8 |
| Security | 7.5 | 8 |
| Performance | 7.5 | 7.5 |
| Maintainability | 7.5 | 8 |
| Scalability | 7.5 | 7.5 |
| Commercial readiness | 7 | 7.5 |
| Marketplace readiness | 7 | 7 |
| Operational readiness | 6 | 7.5 |
| Production readiness | 7 | **6.5** (blocked on DB test evidence) |

**Production readiness is not claimed.** Evidence gaps are labeled **BLOCKED** or **UNVERIFIED** above.

---

Phase 9 not started.
