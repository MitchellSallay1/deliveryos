# DeliveryOS — Production Runbook

Operational guide for staging and production. **Do not store real secrets in this file** — use Supabase/Vercel secret managers only.

---

## Environments

| Environment | Frontend | Backend | Purpose |
|-------------|----------|---------|---------|
| **Local** | Vite (`npm run dev`, port 5173) | Supabase CLI (`supabase start`) | Development |
| **Staging** | Vercel preview or dedicated project | Supabase staging project | QA, migration dry-runs |
| **Production** | Vercel production | Supabase production project | Live tenants |

Keep staging on the **same major Postgres version** as production (currently 15 per `supabase/config.toml`).

---

## Required secrets & configuration

### Supabase (Dashboard → Project Settings)

- **Database URL** — migrations, backups, `DATABASE_URL` for `npm run test:db`
- **Anon key** — Vite `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`
- **Auth (phone OTP)** — Phone provider enabled; Send SMS Hook configured (`auth-sms-hook` → WinAggregator) — **production-verified**
- **Service role key** — server-side automation only; never expose to the browser
- **JWT secret** — managed by Supabase; do not rotate without a maintenance window
- **SMS provider** (operational) — Edge Function env for outbound/inbound rider/customer SMS (separate from Auth OTP config)

### Vercel

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`
- `VITE_APP_URL` — public frontend origin for invite/deep links (not required for phone login). Set to `https://app.<domain>` in Production; leave unset in Preview (falls back to the preview deployment's own origin via `window.location.origin`, see `src/lib/app-url.ts`).

`src/lib/supabase/client.ts` now throws at startup (not just a console warning) if `VITE_SUPABASE_URL`/`VITE_SUPABASE_ANON_KEY` are missing — a misconfigured deploy fails loudly instead of shipping a client that silently can't reach the database.

### Domain-dependent database configuration (not part of any migration)

`notify_customer_tracking` (delivery-tracking SMS link) reads the tracking-page base URL from the Postgres GUC `app.public_url` — this is intentionally environment-specific and cannot live in a migration. **Required one-time step against the production database** once the domain is live (Supabase SQL Editor):

```sql
ALTER DATABASE postgres SET app.public_url = 'https://app.<domain>';
SELECT pg_reload_conf();
```

Until this is set, `notify_customer_tracking` sends the status update without a tracking link (fixed in `20260309220000_production_domain_readiness.sql` — it previously fell back to a dead `http://localhost:5173` link, which real customers may have already received before this was set).

### Local `.env` (gitignored)

```env
VITE_SUPABASE_URL=https://<project-ref>.supabase.co
VITE_SUPABASE_ANON_KEY=<anon-key>
VITE_APP_URL=http://localhost:5173
```

### Supabase Auth — phone OTP

1. **Authentication → Providers → Phone** — enable.
2. SMS delivered via **Send SMS Hook** → `auth-sms-hook` → WinAggregator (covers MTN Liberia and Orange Liberia; not a native MTN carrier integration — see [MTN_INTEGRATION.md](./MTN_INTEGRATION.md)).
3. Enable Auth **rate limits** and **CAPTCHA** for production.
4. **Authentication → URL Configuration**: set **Site URL** to `https://app.<domain>` and add `https://app.<domain>/auth/callback` (and, if previewing, the Vercel preview origin) to **Redirect URLs**. The current login flow is phone OTP exchanged directly in-app (`signInWithOtp`/`verifyOtp`, no `redirectTo` passed anywhere in the codebase) so no request today actually depends on these — but Site URL still governs anything Supabase Auth does hosted-side (e.g. Auth API CORS scoping, any future email-based flow), so it should never be left pointing at `localhost` on a production project.

**Manual smoke test — step 1 production-verified (real SMS received, code verified, session issued); steps 2–5 still to be exercised end-to-end with real SMS:**

1. Login → OTP received → session established — ✅ verified in production
2. Register company owner → workspace + 7-day trial
3. Team invite by phone → accept with matching verified phone
4. Rider OTP + invite link → `link_rider_account` → My Jobs
5. Logout → login again with OTP

Steps 2–5 use the same OTP delivery mechanism as step 1, so they're expected to work, but each persona's registration flow should still be run once for real before considering it fully signed off.

Legacy email test users: delete or reset in dev ([PHONE_AUTH.md](./PHONE_AUTH.md)).

---

## Migration deployment

1. Review new files under `supabase/migrations/` in a PR.
2. Apply to **staging** first:

   ```bash
   npx supabase link --project-ref <staging-ref>
   npx supabase db push
   ```

3. Run smoke tests (login, create delivery, admin billing RPCs if changed).
4. Apply to **production** with the same command against the production ref.
5. Regenerate types when schema changes:

   ```bash
   npm run gen:types
   ```

6. **CI:** pull requests run `.github/workflows/ci.yml` (unit tests + Supabase pgTAP on GitHub-hosted Docker).

**Rules:** forward-only migrations; no destructive drops without verifying references; Phase 4 billing data is backfilled from legacy `companies.subscription_id`.

---

## Edge Functions

SMS inbound handler lives in `supabase/functions/sms-inbound/`.

Deploy (linked project):

```bash
npx supabase functions deploy sms-inbound
```

Set function secrets in Supabase Dashboard → Edge Functions → Secrets.

---

## Vercel deployment

1. Connect Git repository to Vercel.
2. Build command: `npm run build`
3. Output directory: `dist`
4. Install command: `npm ci`
5. Set environment variables per environment (Production / Preview).
6. Protect production branch; use preview URLs for staging.

`vercel.json` at the repo root provides the SPA fallback rewrite (every non-static path serves `index.html` — required because the app uses `BrowserRouter`, not hash routing) and baseline security headers (HSTS, `X-Content-Type-Options`, `Referrer-Policy`, `X-Frame-Options`/`frame-ancestors`, `Permissions-Policy`, a CSP scoped to `self` + Supabase + Google Fonts + OpenStreetMap tiles + the Leaflet marker-icon CDN). **Verify the CSP in a Preview deployment first** (browser console will show any violation) before it's live on the production domain — it was written from a full audit of every external origin the app actually loads, not guessed, but a live check is still the safe final step.

---

## Backups

- **Supabase Pro (recommended):** enable daily backups and point-in-time recovery in the dashboard.
- **Manual:** periodic `pg_dump` from the connection pooler or direct DB URL, stored encrypted off-site.
- Include **Storage** bucket policies and object lifecycle in disaster planning (`delivery-photos`).

---

## Restore procedure (high level)

1. Declare incident; freeze writes if possible (maintenance mode message).
2. Create a **new** Supabase restore or restore backup to a clone project (Supabase support/docs for your plan).
3. Point staging Vercel env at clone; validate RLS, billing RPCs, and auth.
4. Update production DNS/env to restored project only after sign-off.
5. Post-incident: root cause, migration fix if schema-related.

---

## Testing before release

```bash
npm run build
npm test
npm run test:db   # requires local Supabase + migrations; sets RUN_DB_TESTS=1
npx supabase test db   # pgTAP suite in supabase/tests/database/
```

---

## Incident response (basics)

1. **Detect** — Vercel/Supabase alerts, user reports, failed CI.
2. **Triage** — auth outage vs data leak vs billing vs SMS; check Supabase logs and Vercel function logs.
3. **Contain** — suspend abusive company via Super Admin; rotate compromised keys; disable Edge Function if abused.
4. **Communicate** — status to affected company owners; document in internal ticket.
5. **Recover** — rollback deploy (Vercel) or hotfix migration (forward fix preferred over revert).
6. **Review** — audit log (`audit_logs`), access patterns, update runbook.

---

## Super Admin operations (Phase 4)

Manual billing (Liberia): Cash, MTN MoMo, Orange Money, bank transfer — recorded via `/admin/payments` and RPCs, not payment gateways.

- Plans: `/admin/plans`
- Subscriptions: `/admin/subscriptions`
- Invoices: `/admin/invoices`
- Payments: `/admin/payments`
- Audit: `/admin/audit`

Company owners see billing usage on `/settings` (owner role only).

---

## Contacts & ownership

Document your on-call rotation, Supabase organization owner, and Vercel team admin in your internal wiki (not in git).
