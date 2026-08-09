# DeliveryOS — Supabase architecture (steps 1–7)

## Why Supabase instead of a custom API?

- **Multi-tenant security** is enforced in PostgreSQL via **RLS**, not in app code alone.
- **Supabase Auth** handles sessions, refresh, and identity; the frontend uses the anon key only.
- **Direct client reads/writes** reduce latency and ops cost; **Edge Functions** are reserved for secrets (SMS gateways, webhooks, payment providers).

The legacy `backend/` Go service is **deprecated** for this product direction. Do not deploy it alongside Supabase for new work.

## Folder structure

```
src/
  components/     UI + route guards
  layouts/        Dashboard, auth, marketing, rider shells
  pages/          Route screens (app + marketing/)
  hooks/          Auth + TanStack Query hooks
  lib/            Supabase client, utils
  services/       Thin wrappers (auth, later deliveries)
  types/          Database typings (replace with `supabase gen types`)
  utils/          Zod schemas
supabase/
  migrations/     Schema + RLS (source of truth)
```

## Local setup

1. Create a project at [supabase.com](https://supabase.com).
2. Copy `.env.example` → `.env.local` and set `VITE_SUPABASE_*`.
3. Install CLI and apply migrations:

   ```bash
   npm install
   npx supabase link --project-ref YOUR_REF
   npx supabase db push
   ```

4. In Supabase Dashboard → Authentication, enable **Phone** provider and configure SMS (MTN TBD — see `docs/MTN_INTEGRATION.md`).
5. Promote a platform admin:

   ```sql
   UPDATE public.profiles SET is_super_admin = true WHERE id = 'YOUR_USER_UUID';
   ```

6. Run the app:

   ```bash
   npm run dev
   ```

Deploy frontend to **Vercel** with the same env vars. Database and auth stay on **Supabase Cloud**.

## Security model (RLS)

| Layer | Responsibility |
|--------|----------------|
| `company_users` | Maps `auth.uid()` → `company_id` + `role` |
| `user_company_ids()` | Used in policies for tenant isolation |
| `has_company_role()` | Dispatcher vs owner vs rider write gates |
| `is_super_admin()` | Platform operator bypass |
| `create_company_with_owner()` | SECURITY DEFINER onboarding RPC |

**Never trust the frontend for authorization** — UI hides links; Postgres policies enforce access.

## Completed in this step

1. Folder structure  
2. Dependencies (React 19, Vite, Tailwind 4, TanStack Query, Supabase, Zod)  
3. Supabase client config  
4–5. SQL migrations (schema + RLS)  
6. Phone OTP auth + register via RPC (`finalize_phone_workspace`, `link_rider_account`)  
7. Dashboard layout + today stats query  

## Next features (one module at a time)

1. ~~**Deliveries**~~ — RPC, Realtime, tracking page (`20260307130000_deliveries_functions.sql`)
2. ~~**Riders / Customers**~~ — CRUD pages + plan rider limit trigger
3. ~~**Reports**~~ — `get_workspace_report` RPC + `/reports` UI
4. ~~**Notifications**~~ — SMS credits, outbound on assign/status, inbound Edge Function
5. ~~**Storage**~~ — `delivery-photos` bucket, `register_delivery_photo`, upload on deliveries board
6. ~~**Super Admin UI**~~ — `/admin`, company activate/suspend, SMS top-up via `admin_add_sms_credits`

## Phase 2 (continued)

1. ~~**Settings**~~ — profile, company (owner), plan, workspace switcher, COD payments
2. ~~**Rider jobs**~~ — `/my-jobs`, claim rider profile, rider status RPC, proof photos

## Phase 3 — Production hardening (complete)

See [PHASE3_AUDIT.md](./PHASE3_AUDIT.md) for before/after scores and migration list.

1. ~~Typed Supabase client~~ — `src/types/supabase.ts`, `npm run gen:types`
2. ~~Legacy removal~~ — `backend/`, `frontend/` removed
3. ~~RBAC~~ — `lib/rbac.ts`, `RequireAccess`, role nav
4. ~~Team~~ — invitations RPC + `/team`, `/invite/:token`
5. ~~SQL guards~~ — active company, plan limits, payment RLS

## Phase 4 (complete)

See [PHASE4_AUDIT.md](./PHASE4_AUDIT.md) — billing, usage, audit log, manual payments.

## Phase 5 (complete)

See [PHASE5_AUDIT.md](./PHASE5_AUDIT.md).

## Phase 6 (complete)

See [PHASE6_AUDIT.md](./PHASE6_AUDIT.md) — branches, fleet, inventory, COD settlements.

## Phase 7 (complete)

See [PHASE7_AUDIT.md](./PHASE7_AUDIT.md) — logistics network & marketplace (merchant ↔ provider).

## Phase 8 (complete)

See [PHASE8_AUDIT.md](./PHASE8_AUDIT.md) — production launch & validation (CI DB tests, hardening, ops docs).

**Note:** Production readiness requires passing database tests in CI or local Docker — see Phase 8 audit.

Marketplace docs:

- [docs/MARKETPLACE.md](./docs/MARKETPLACE.md)
- [docs/MARKETPLACE_FINANCE.md](./docs/MARKETPLACE_FINANCE.md)
- [docs/MARKETPLACE_SECURITY.md](./docs/MARKETPLACE_SECURITY.md)

Operations docs:

- [docs/FLEET.md](./docs/FLEET.md)
- [docs/INVENTORY.md](./docs/INVENTORY.md)
- [docs/COD_RECONCILIATION.md](./docs/COD_RECONCILIATION.md)

Field ops & platform docs:

- [docs/API.md](./docs/API.md)
- [docs/WEBHOOKS.md](./docs/WEBHOOKS.md)
- [docs/GPS_AND_PRIVACY.md](./docs/GPS_AND_PRIVACY.md)
- [docs/PRODUCTION_RUNBOOK.md](./docs/PRODUCTION_RUNBOOK.md)

Rider channels (smartphone + button phone):

- [docs/RIDER_CHANNELS.md](./docs/RIDER_CHANNELS.md)
- [docs/RIDER_SMS.md](./docs/RIDER_SMS.md)
- [docs/RIDER_USSD.md](./docs/RIDER_USSD.md)
- [docs/AUTHENTICATION.md](./docs/AUTHENTICATION.md)
- [docs/RIDER_ONBOARDING.md](./docs/RIDER_ONBOARDING.md)
- Migration: `20260308140000_rider_channels.sql`
- Edge Functions: `sms-inbound`, `ussd-rider`

Multi-persona auth:

- Registration landing `/register` → company, merchant, or rider paths
- Migration: `20260308150000_auth_personas.sql` (`link_rider_account`, invite codes)
- Phone-first auth: `20260308160000_phone_auth.sql` — see [docs/PHONE_AUTH.md](./docs/PHONE_AUTH.md)

Public marketing site:

- Routes under `MarketingLayout` (`/`, `/features`, `/pricing`, …) — see [docs/PUBLIC_WEBSITE.md](./docs/PUBLIC_WEBSITE.md)
- `/` redirects authenticated users to app home via `MarketingRootPage`

Super Admin control tower:

- Routes under `SuperAdminRoute` + `AdminLayout` (`/admin`, …) — see [docs/SUPER_ADMIN.md](./docs/SUPER_ADMIN.md)
- Platform RPCs in `20260308180000_super_admin_control_tower.sql`
