# Phone authentication

DeliveryOS uses **phone number + SMS OTP** as the primary sign-in method for:

- Company owners, dispatchers, support staff (via team invites)
- Merchants
- Smartphone riders

Button-phone riders **do not** use Supabase login (MSISDN + SMS/USSD only).

## Flow

1. User enters mobile number (Liberia-first normalization; stored as E.164 where possible).
2. Client calls `supabase.auth.signInWithOtp({ phone })` (see `src/services/auth-sms-provider.ts`).
3. User enters SMS code → `supabase.auth.verifyOtp({ phone, token, type: 'sms' })`.
4. Session + `auth.uid()` unchanged; RLS and roles unchanged.
5. Post-auth routing via `resolvePostAuthPath`.

Registration mirrors login: **persona → OTP → persona setup** (company/merchant workspace or rider link).

## Phone normalization

Single client helper: `src/lib/phone.ts` (`normalizePhoneE164`, `phoneMatchesMsisdn`, `maskPhoneForDisplay`).

Database: `public.normalize_phone()` → `normalize_phone_lr()` (migration `20260308160000_phone_auth.sql`).

Examples that resolve consistently:

- `0881697769` → `+231881697769`
- `+231881697769`
- `231881697769`

## Profiles

After OTP, call RPC `sync_profile_from_auth_user()` to copy verified auth phone into `profiles.phone` / `profiles.phone_normalized`.

Email on `profiles` and company records is **optional** (contact/notifications).

## Rider linking security

`link_rider_account` requires:

- Authenticated Supabase user with verified phone
- Invite code and/or rider code
- **Verified phone must match rider registered MSISDN**

## Team invitations

Owners invite by **phone** (`create_company_invitation` with `p_phone`).

Acceptance requires authenticated phone to match `phone_normalized` on the invitation.

## Development / test users

No production users yet. Recommended **development reset**:

1. Supabase Dashboard → Authentication → delete legacy email test users, or reset project auth.
2. `npx supabase db push` for phone auth migration.
3. Re-register via phone OTP flows.

Legacy email/password test accounts are not supported in the UI; metadata-only pending onboarding (name + phone, no email) still works via `complete_pending_onboarding`.

## Rate limiting & abuse

- Client: 60s resend cooldown (`PhoneOtpFlow`).
- Enable Supabase Auth rate limits and CAPTCHA in production (see Supabase dashboard docs below).
- OTP costs money — monitor send volume per phone/IP.

## Account recovery

There is no “forgot password”. Recovery = sign in again with phone + OTP.

Lost phone number: **no self-service phone change** in v1; admin/support recovery only (document in runbook).

## End-to-end SMS

**Production-verified.** The Supabase Auth Send SMS Hook (`auth-sms-hook` → WinAggregator) is configured and a real end-to-end OTP was sent, received, and verified in production (see `docs/SCHEDULED_JOBS.md`).

Local/dev environments still need the hook configured (or a stub) to receive real SMS — without it, OTP generation/verification still works in Supabase Auth, but no message is actually delivered. Don’t assume delivery works in an environment where the hook hasn’t been set up.

See [MTN_INTEGRATION.md](./MTN_INTEGRATION.md) for the distinction between this WinAggregator-based delivery (live) and a native MTN carrier integration (not built), and Supabase phone provider setup in this repo’s `docs/AUTHENTICATION.md`.
