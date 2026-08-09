# Launch checklist

## DATABASE

- [ ] All migrations applied to production (`supabase db push`)
- [ ] **CI DB tests passed** (`.github/workflows/ci.yml` green)
- [ ] RLS suite reviewed (`tests/db/rls-security.test.ts`)
- [ ] Backups / PITR enabled (Supabase dashboard)

## AUTH

- [ ] Phone provider enabled; SMS gateway or Auth Send SMS Hook configured (MTN TBD)
- [ ] Auth rate limits + CAPTCHA for OTP
- [ ] Legacy email test users removed or migrated (dev/staging)
- [ ] `/auth/callback` redirect URLs if using OAuth/magic links
- [ ] UAT P0 signed ([UAT_PLAN.md](./UAT_PLAN.md)) · Full gate: [LAUNCH_READINESS.md](./LAUNCH_READINESS.md)

## SECURITY

- [ ] Secrets rotated (service role, cron, SMS, email)
- [ ] Service role never in Vite bundle
- [ ] API rate limits verified (`api-v1`)
- [ ] Webhook secrets stored per endpoint

## BILLING

- [ ] Plans configured (`subscriptions` catalog)
- [ ] Subscription past_due job scheduled

## SMS / EMAIL

- [ ] `SMS_PROVIDER=http` + endpoint configured OR stub only in dev
- [ ] `EMAIL_PROVIDER=http` + endpoint configured
- [ ] `jobs-scheduler` cron every 5 minutes

## GPS / PWA

- [ ] Rider location permissions tested on Android
- [ ] PWA install smoke test

## MARKETPLACE

- [ ] Scenario B manual test (merchant → provider → delivery)

## COD

- [ ] Collect → settlement → reconcile tested

## OBSERVABILITY

- [ ] Frontend error tracking configured (**UNVERIFIED** — wire Sentry/etc.)
- [ ] Admin `/admin/system-status` reviewed

## LEGAL

- [ ] `/terms` and `/privacy` reviewed by counsel (**placeholder**)

## BACKUP

- [ ] Restore drill per `docs/DISASTER_RECOVERY.md`
