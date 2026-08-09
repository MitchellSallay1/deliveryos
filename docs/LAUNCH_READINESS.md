# DeliveryOS — Launch readiness checklist

Use with [LAUNCH_CHECKLIST.md](./LAUNCH_CHECKLIST.md) (shorter ops list) and [PRODUCTION_RUNBOOK.md](./PRODUCTION_RUNBOOK.md).

**Target:** First production deployment (Liberia / MTN deployment context).

---

## 1. Authentication & identity

- [ ] Supabase **Phone** provider enabled
- [ ] SMS gateway or Send SMS Hook configured (**MTN spec pending — BLOCKER for real OTP**)
- [ ] Auth rate limits enabled (Supabase Dashboard)
- [ ] CAPTCHA on OTP recommended for production
- [ ] Legacy email test users removed or reset ([PHONE_AUTH.md](./PHONE_AUTH.md))
- [ ] `VITE_SUPABASE_*` and `VITE_APP_URL` set on Vercel (no SMS secrets in Vite)
- [ ] Invite login redirect verified (AUTH-005 / REG-AUTH-05)

---

## 2. Database & RLS

- [ ] All 26 migrations applied in order on production project
- [ ] RLS enabled on tenant tables ([`20260307120100_rls_policies.sql`](../supabase/migrations/))
- [ ] Staging `RUN_DB_TESTS=1` RLS suite executed at least once
- [ ] PITR / backups enabled (Supabase Pro or documented alternative)
- [ ] Connection pooling configured for Edge/server workloads

---

## 3. Edge Functions & secrets

- [ ] `sms-inbound` deployed + `x-sms-secret` rotated
- [ ] `ussd-rider` deployed (if USSD live)
- [ ] `jobs-scheduler` cron every 5 minutes
- [ ] `api-v1` + API key rotation procedure documented
- [ ] `webhooks-dispatch` + customer webhook secrets
- [ ] Service role key **only** in server/Edge env (never client)

---

## 4. Billing & subscriptions

- [ ] Subscription catalog (`subscriptions` slugs) verified
- [ ] Trial → paid transition tested
- [ ] `trial_expired` and `subscription_past_due` UX verified
- [ ] Admin billing flows tested (`/admin/subscriptions`)

---

## 5. Security

- [ ] [SECURITY_AUDIT.md](./SECURITY_AUDIT.md) reviewed; P0 items closed
- [ ] [SECURITY_FUNCTION_AUDIT.md](./SECURITY_FUNCTION_AUDIT.md) staging sign-off
- [ ] HTTPS only on production domain
- [ ] Security headers on Vercel (default + review CSP for maps)
- [ ] Audit log retention policy ([DATA_RETENTION.md](./DATA_RETENTION.md))

---

## 6. Observability & errors

- [ ] Error tracking wired (Sentry or equivalent) — **currently UNVERIFIED in app**
- [ ] Supabase logs monitored for RPC failures
- [ ] `/admin/system-status` reviewed post-deploy
- [ ] Friendly error mapping ([`parseSupabaseError`](../src/lib/supabase-errors.ts)) — spot-check pages

---

## 7. Performance & scale

- [ ] Lighthouse smoke on dashboard + deliveries (mobile)
- [ ] Realtime channel count acceptable per company
- [ ] Large delivery list: Kanban pageSize 100 acceptable for pilot tenants
- [ ] See [PRODUCTION_SCORECARD.md](./PRODUCTION_SCORECARD.md) performance notes

---

## 8. Branding & legal

- [ ] MTN “Powered by” copy approved
- [ ] `/terms` and `/privacy` reviewed by counsel (**placeholders**)
- [ ] Favicon / PWA manifest / theme-color

---

## 9. MTN integration readiness (not launch blockers for internal alpha)

- [ ] [MTN_INTEGRATION.md](./MTN_INTEGRATION.md) shared with MTN technical team
- [ ] Auth SMS adapter boundary documented
- [ ] Operational SMS vs auth SMS separation confirmed
- [ ] MoMo **not** required for alpha

---

## 10. UAT & regression

- [ ] [UAT_PLAN.md](./UAT_PLAN.md) P0 cases executed on staging
- [ ] [REGRESSION_TESTS.md](./REGRESSION_TESTS.md) signed for release tag
- [ ] [KNOWN_LIMITATIONS.md](./KNOWN_LIMITATIONS.md) shared with stakeholders

---

## 11. DNS & deployment

- [ ] Production domain → Vercel
- [ ] Supabase Site URL + redirect URLs include production origin
- [ ] Preview env secrets isolated from production

---

## Launch decision

| Gate | Required for |
|------|----------------|
| Sections 1–3 + 10 (except live SMS) | **Internal alpha** |
| + Section 1 SMS live + UAT P0 | **Private beta** |
| + Legal + observability + MTN sign-off | **Enterprise / public beta** |
