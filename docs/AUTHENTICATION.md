# Authentication & personas

DeliveryOS uses **phone + SMS OTP** (Supabase Auth) as the primary login for all app users except button-phone riders.

## Personas

| Persona | Registration path | Workspace | After login |
|---------|-------------------|-----------|-------------|
| **Company owner** | `/register/company` | Creates delivery company | Dashboard |
| **Merchant** | `/register/merchant` | Creates merchant workspace | Merchant requests |
| **Smartphone rider** | `/register/rider` | None | Link rider → My Jobs |
| **Button-phone rider** | N/A (no login) | N/A | SMS/USSD only |

Auth metadata (`user.user_metadata.persona`) drives routing:

- `company_owner` / `merchant` — workspace via `finalize_phone_workspace` or legacy `complete_pending_onboarding`
- `rider` — no company provisioning; `/link-rider` then `/my-jobs`

## Entry points

- `/register` — persona chooser
- `/login` — phone OTP (`PhoneOtpFlow`)
- `/auth/callback` — OAuth/magic-link recovery only; email confirmation no longer required for normal login

## Supabase Dashboard configuration (required for production OTP)

1. **Authentication → Providers → Phone** — enable phone sign-in.
2. **SMS provider** — configure gateway or **Send SMS Hook** (MTN TBD; see [MTN_INTEGRATION.md](./MTN_INTEGRATION.md)).
3. **OTP length / expiry** — align with UX (6-digit typical).
4. **Rate limits** — enable Auth rate limiting; tune for OTP abuse.
5. **CAPTCHA** — recommended on `signInWithOtp` in production.
6. **No SMS secrets in Vite** — only `VITE_SUPABASE_URL` and anon key in the browser.

Until SMS is configured, flows work in code/tests with mocks; **real OTP delivery is blocked**.

## Guards

- `PersonaGate` — riders cannot open company dashboard routes
- `OnboardingGate` — skips company auto-provision for `persona: rider`
- `/setup` — redirects riders to `/link-rider`

## Team vs rider invites

- `/invite/:token` — phone-first team invitations
- `/rider/invite/:code` — rider smartphone onboarding → `/register/rider`

See [PHONE_AUTH.md](./PHONE_AUTH.md) and [RIDER_ONBOARDING.md](./RIDER_ONBOARDING.md).

## Authorization

Phone proves **identity** only. Privilege comes from `profiles.is_super_admin`, `company_users.role`, and RLS — never from phone number in frontend code.
