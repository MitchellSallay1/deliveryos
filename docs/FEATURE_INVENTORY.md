# DeliveryOS — Feature inventory (launch audit)

Audit date: 2026-08-08 · Static codebase review (not live SMS/MTN verification).

| Module | Status | Implementation summary | Key routes / entry | Backend |
|--------|--------|------------------------|-------------------|---------|
| **Authentication (phone OTP)** | Implemented | Supabase `signInWithOtp` / `verifyOtp`; Liberia normalization | `/login`, `PhoneOtpFlow` | `auth.users`, `sync_profile_from_auth_user` |
| **Company onboarding** | Implemented | OTP → company form → `finalize_phone_workspace` | `/register/company` | `create_company_with_owner`, 7-day trial |
| **Merchant onboarding** | Implemented | Same as company with `business_type: merchant` | `/register/merchant` | `finalize_phone_workspace` |
| **Smartphone rider onboarding** | Implemented | OTP → name → link invite | `/register/rider`, `/link-rider` | `link_rider_account` |
| **Button-phone riders** | Implemented | No app login; SMS/USSD MSISDN | Edge `sms-inbound`, `ussd-rider` | `apply_rider_channel_command` |
| **Persona routing** | Implemented | Metadata `persona` + RBAC | `PersonaGate`, `post-auth-navigation` | RLS + `company_users` |
| **Dashboard / operations center** | Implemented | KPIs, recent deliveries, trends (UI) | `/dashboard` | `get_workspace_report` |
| **Deliveries** | Implemented | CRUD, assign, transitions, realtime | `/deliveries` | `create_delivery`, Kanban uses existing RPCs |
| **Customers** | Implemented | Upsert by phone, list, edit | `/customers` | Customer RPCs + RLS |
| **Riders** | Implemented | Create, status, access mode, invite codes | `/riders` | `riders`, channel settings |
| **Rider PWA (My Jobs)** | Implemented | Job list, transitions, photo proof | `/my-jobs`, `RiderLayout` | `rider_transition_delivery_status` |
| **Reports** | Implemented | Day/week/month workspace report | `/reports` | `get_workspace_report` |
| **Billing / subscriptions** | Implemented | Trial banner, plan usage, admin billing | `/billing`, `/settings` | Phase 4 billing RPCs |
| **Marketplace** | Implemented | Merchant requests, provider jobs, settlements | `/merchant/requests`, `/marketplace/*` | Phase 7 migrations |
| **Notifications / SMS log** | Implemented | Outbound log UI; credits display | `/notifications` | `queue_outbound_sms`, logs tables |
| **SMS (operational)** | Implemented | Assign job SMS, inbound keywords | Edge `sms-inbound`, `sms-dispatch` | Postgres queue |
| **USSD** | Implemented | Rider commands via USSD handler | Edge `ussd-rider` | `handle_ussd_request` |
| **OTP (proof / button-phone)** | Implemented | Separate from auth OTP | Rider channel migration | SQL proof flows |
| **Auth SMS OTP** | **Implemented, production-verified** | Send SMS Hook → `auth-sms-hook` → WinAggregator; real end-to-end OTP confirmed | `auth-sms-provider.ts`, `supabase/functions/auth-sms-hook/` | Supabase Phone provider + Send SMS Hook |
| **Maps / live map** | Implemented | Leaflet map, rider locations | `/live-map` | Location samples + RLS |
| **Realtime** | Implemented | Deliveries postgres_changes | `useDeliveries` | Supabase Realtime |
| **REST API v1** | Implemented | API keys, rate limits | Edge `api-v1` | `verify_api_key` |
| **Webhooks** | Implemented | Outbound dispatch | Edge `webhooks-dispatch` | `enqueue_webhook_event` |
| **Settings** | Implemented | Company, profile, zones, integrations | `/settings` | Settings RPCs |
| **Team invites** | Implemented | Phone-first invite + token accept | `/team`, `/invite/:token` | `create_company_invitation` |
| **Roles / permissions** | Implemented | Frontend `can()` + RLS | `RequireAccess`, `rbac.ts` | `has_company_role` |
| **Subscriptions / trial** | Implemented | 7-day trial, plan limits | Banners, billing | `ensure_initial_company_subscription` |
| **Operations (fleet, inventory, COD)** | Implemented | Optional modules per plan | `/operations/*` | Phase 5–6 RPCs |
| **Super admin** | Implemented | Platform admin console | `/admin/*` | `is_super_admin` |
| **Public tracking** | Implemented | Tracking page by code | `/track/:code` | `get_delivery_tracking` |
| **Branding (MTN deployment)** | Implemented | Theme provider, powered-by | Layouts, login | Client-only |
| **PWA** | Implemented | vite-plugin-pwa | manifest, SW | — |
| **MTN MoMo / MTN Auth SMS** | Not integrated | Placeholders only | UI “Coming soon” | See `MTN_INTEGRATION.md` |

## Documentation index

| Topic | Doc |
|-------|-----|
| Architecture | `ARCHITECTURE.md` |
| Auth | `docs/AUTHENTICATION.md`, `docs/PHONE_AUTH.md` |
| Riders | `docs/RIDER_ONBOARDING.md`, `docs/RIDER_CHANNELS.md`, `docs/RIDER_SMS.md`, `docs/RIDER_USSD.md` |
| Marketplace | `docs/MARKETPLACE.md`, `docs/MARKETPLACE_SECURITY.md` |
| Billing | Phase 4 + `docs/COD_RECONCILIATION.md` |
| API / webhooks | `docs/API.md`, `docs/WEBHOOKS.md` |
| Security (functions) | `docs/SECURITY_FUNCTION_AUDIT.md` |
| Ops | `docs/PRODUCTION_RUNBOOK.md`, `docs/DISASTER_RECOVERY.md` |
| Design | `docs/DESIGN_SYSTEM.md` |
| MTN (future) | `docs/MTN_INTEGRATION.md` |

## Automated test coverage (unit)

- Vitest: auth onboarding, phone normalization, RBAC, rider channels, workspace setup, webhook signature, delivery schemas (~66+ unit tests).
- DB: RLS suite + integration (`RUN_DB_TESTS=1`) — skipped in default CI unless configured.
