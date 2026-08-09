# Rider onboarding (smartphone)

Button-phone riders do not use this flow. They operate via SMS/USSD and MSISDN identity only.

## Owner steps

1. Create rider in **Riders** (access mode `smartphone` or `both`).
2. Copy **invite code** or **invite link** (`/rider/invite/RDR-XXXX`).
3. Rider opens `/register/rider` (not company registration).

## Rider steps

1. Verify **registered rider phone** via SMS OTP (same number the dispatcher saved on the rider record).
2. Enter full name (optional display).
3. Open **Link rider profile** (`/link-rider`):
   - **Invite code** (recommended), or
   - **Rider ID** + matching verified phone.
4. **My Jobs** — PWA, GPS, photo proof unchanged.

No rider email or password. No rider workspace is created.

## RPC: `link_rider_account`

- Requires `auth.uid()` and verified auth phone (`auth.users.phone`)
- **Verified phone must match rider MSISDN** (even when using invite code)
- Validates rider active, company active, access mode not `button_phone`
- One rider profile per auth user
- Creates `company_users` row with role `rider`
- Idempotent if already linked to same rider

Legacy `claim_rider_profile(company_id, rider_code)` remains for dispatchers linking within a selected workspace.

## Invite codes

- Column: `riders.invite_code` (unique, auto-generated on insert)
- Regenerate: `regenerate_rider_invite_code(rider_id)` (owner/dispatcher)
- Public preview: `get_rider_invite_preview(code)` for invite landing page

See [PHONE_AUTH.md](./PHONE_AUTH.md).
