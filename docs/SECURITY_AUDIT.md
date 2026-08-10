# DeliveryOS — Security audit (launch)

**Audit date:** 2026-08-08  
**Method:** Static review of migrations, Edge Functions, frontend auth/RBAC, and existing [SECURITY_FUNCTION_AUDIT.md](./SECURITY_FUNCTION_AUDIT.md).  
**Scope:** No penetration test; no live MTN/SMS test.

---

## Executive summary

| Area | Rating | Notes |
|------|--------|-------|
| Tenant isolation (RLS) | **Strong** | Policies + SECURITY DEFINER RPCs with role checks |
| Auth (phone OTP) | **Good (client)** | Provider/config external; friendly OTP errors |
| Edge Functions | **Good** | Shared secrets; not exposed to browser |
| Frontend authorization | **Good** | UI gates; must not replace RLS |
| Public surfaces | **Acceptable** | Tracking + invite preview scoped |
| Secrets hygiene | **Pass** | No service role in Vite bundle (verified grep) |

**P0 launch blockers (security):** Configure production SMS/auth secrets; run DB RLS suite on staging before prod.

---

## 1. Authentication & sessions

| Finding | Severity | Status |
|---------|----------|--------|
| Identity via Supabase JWT; `auth.uid()` in RLS | — | By design |
| Phone OTP client boundary only (`auth-sms-provider.ts`) | — | Pass |
| Open redirect on login | Medium | **Fixed** — `safeInternalRedirect` on `?redirect=` |
| Super admin from phone in UI | — | Pass — uses `profiles.is_super_admin` |
| Brute force OTP | Medium | Mitigate via Supabase rate limits + CAPTCHA (ops) |
| Session fixation | Low | Supabase-managed |

---

## 2. Authorization & privilege escalation

| Control | Implementation |
|---------|----------------|
| Company scope | `has_company_role`, `user_company_ids`, RLS |
| Rider persona | `PersonaGate`, no owner workspace for riders |
| Dispatcher vs owner | RBAC permissions in `rbac.ts` |
| Admin | `SuperAdminRoute` + DB flag |
| API keys | `verify_api_key`; service role only for verify |

**Verified:** Frontend `can()` is defense-in-depth; mutations go through RPCs.

---

## 3. RLS & RPC

- 26 forward migrations; RLS policies in dedicated migration.
- SECURITY DEFINER functions use `SET search_path = public` (see function audit).
- Sensitive internals (`queue_email`, webhooks enqueue) REVOKE PUBLIC per Phase 8.

**Recommendation:** Run `tests/db/rls-security.test.ts` with `RUN_DB_TESTS=1` before prod cutover.

---

## 4. Invitations & rider linking

| Risk | Mitigation |
|------|------------|
| Invite token guessing | Long random token; expiry |
| Accept wrong user | Phone/email match on accept |
| Rider takeover | Verified phone must match rider MSISDN + invite |
| Invite code only bypass | **Removed** — phone match required |

**Gap fixed in audit:** `invitation_phone_mismatch` now mapped in `parseSupabaseError`.

---

## 5. SMS / USSD / OTP

| Channel | Secret handling | Notes |
|---------|-----------------|-------|
| Operational SMS | Edge env, `x-sms-secret` | Separate from auth OTP |
| Auth OTP | Supabase Auth + Send SMS Hook (`SEND_SMS_HOOK_SECRET`, Standard Webhooks-signed, fail-closed) | Production-verified via WinAggregator; not a native MTN carrier integration |
| Button-phone OTP proof | DB + inbound edge | Not Supabase Auth |

**Risk:** SMS spoofing at carrier layer — operational acceptance for market.

---

## 6. Injection & data exposure

| Vector | Status |
|--------|--------|
| SQL injection via client | Mitigated — RPC parameters, no raw SQL in app |
| XSS | React default escaping; avoid `dangerouslySetInnerHTML` (none found in pages) |
| Public tracking | Field-limited RPC + rate limit (Phase 8) |
| Error leakage | Partial — many pages use `parseSupabaseError`; some still show raw `err.message` (see KNOWN_LIMITATIONS) |

---

## 7. Cross-company isolation

- Deliveries, customers, riders scoped by `company_id` in RPCs.
- Marketplace uses separate merchant/provider company IDs with explicit checks.

---

## 8. Edge Functions inventory

| Function | Auth |
|----------|------|
| `api-v1` | API key |
| `sms-inbound` | Shared secret header |
| `ussd-rider` | Gateway-specific (review deploy config) |
| `jobs-scheduler` | Cron secret / service role |
| `webhooks-dispatch` | Internal |
| `sms-dispatch` / `email-dispatch` | Service |

---

## 9. Recommendations (post-launch)

1. Wire centralized error reporting (Sentry) without logging PII/OTP.
2. Periodic re-audit of new SECURITY DEFINER functions.
3. Phone number change policy — admin-only (documented in PHONE_AUTH.md).
4. Optional: WAF / bot protection on auth endpoints via Supabase CAPTCHA.

---

## Sign-off

| Reviewer | Role | Date | Approved |
|----------|------|------|----------|
| | Security | | |
| | Engineering | | |
