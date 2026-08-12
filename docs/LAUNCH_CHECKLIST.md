# Launch checklist

## DATABASE

- [ ] All migrations applied to production (`supabase db push`)
- [ ] **CI DB tests passed** (`.github/workflows/ci.yml` green)
- [ ] RLS suite reviewed (`tests/db/rls-security.test.ts`)
- [ ] Backups / PITR enabled (Supabase dashboard)
- [ ] `public_app_url` platform setting configured via Super Admin → `/admin/configuration` — required for delivery-tracking SMS links; see [PRODUCTION_RUNBOOK.md](./PRODUCTION_RUNBOOK.md#domain-dependent-configuration-public_app_url-platform-setting)

## AUTH

- [x] Phone provider enabled; Auth Send SMS Hook (`auth-sms-hook` → WinAggregator) configured and **production-tested end-to-end**: real OTP received via SMS from "DelivOS", account setup completed, code verified, session issued. Separate, intentionally decoupled from the WinAggregator transport used for delivery/rider SMS (`sms_outbox` → `sms-dispatch`).
- [ ] Auth rate limits + CAPTCHA for OTP
- [ ] Legacy email test users removed or migrated (dev/staging)
- [ ] `/auth/callback` redirect URLs if using OAuth/magic links
- [ ] UAT P0 signed ([UAT_PLAN.md](./UAT_PLAN.md)) · Full gate: [LAUNCH_READINESS.md](./LAUNCH_READINESS.md)

## SECURITY

- [ ] Secrets rotated (service role, cron, SMS, email, `SEND_SMS_HOOK_SECRET`)
- [ ] Service role never in Vite bundle
- [ ] API rate limits verified (`api-v1`)
- [ ] Webhook secrets stored per endpoint

## BILLING

- [ ] Plans configured (`subscriptions` catalog)
- [ ] Subscription past_due job scheduled

## SMS / EMAIL

- [x] `SMS_PROVIDER=winaggregator` — confirmed production endpoint, sender ID `DelivOS`, no authentication required (defaults are set in code; override via `WINAGGREGATOR_SMS_ENDPOINT` / `WINAGGREGATOR_SENDER_ID` if needed)
- [ ] Real WinAggregator response samples (success and failure) captured and reviewed — current code only checks HTTP status, no response-body parsing
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
