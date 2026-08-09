# DeliveryOS — Known limitations

Document for stakeholders and UAT testers. Not a roadmap commitment.

---

## External dependencies

| Limitation | Impact | Mitigation |
|------------|--------|------------|
| **Auth SMS OTP** requires Supabase Phone provider / MTN | Cannot login new users in prod without config | Use staging test provider; see PHONE_AUTH.md |
| **MTN MoMo** not integrated | No in-app subscription or COD MoMo settlement | Manual billing / COD flows unchanged |
| **MTN operational SMS** credentials | Real SMS/USSD in prod needs Edge secrets | Stub or partner sandbox |

---

## Authentication & users

- No self-service **phone number change**; admin/support recovery only.
- Legacy **email/password** UI removed; old test users must reset in Supabase.
- **CAPTCHA** not enforced in app code — configure in Supabase for production.

---

## Product / UX

- **Offline mode** for riders: banner is informational only; no offline queue.
- **Delivery drawer** timeline shows current status only (full history RPC not wired in UI).
- **Dashboard trend chart** is illustrative bars from week summary, not a full charting library.
- **Reports** lack PDF export and heat maps in UI.
- **Settings** sections are stacked cards, not full tabbed settings IA.
- **Command palette** not implemented (design-system future-ready only).
- **Catch-all URL** (`/unknown`) redirects to `/dashboard` then login if unauthenticated.

---

## Error handling

- `parseSupabaseError` used on critical flows (deliveries, team, invite, track, admin billing).
- Some pages still display raw `Error.message` (customers, riders, settings, reports, operations subpages) — may expose Postgres codes in edge cases.
- No global toast notification system; inline error text only.

---

## Performance

- Deliveries Kanban fetches up to **100** rows per query when in board view.
- No virtualized tables for very large customer/rider lists.
- Leaflet map bundles ~155KB gzip — acceptable but heavy on low-end phones.
- Multiple Realtime channels per tab — monitor Supabase connection limits at scale.

---

## Security & compliance

- **Penetration test** not performed in this audit.
- **Terms / Privacy** pages are placeholders.
- **Data retention** documented but automated purge requires scheduled jobs verification.
- **Invite preview** (`get_invitation_by_token`) exposed to anon/authenticated — token entropy relies on `random_token_hex`.

---

## Testing

- Default CI runs **unit tests only**; RLS suite requires local/staging Postgres + `RUN_DB_TESTS=1`.
- **End-to-end SMS delivery** not verified in automated tests (mocked).

---

## Mobile

- PWA install supported; **iOS Safari** PWA limitations apply (push, background).
- Touch targets improved on rider nav; some admin tables remain desktop-first.

---

## Marketplace & billing

- Complex marketplace settlement flows require manual UAT per [UAT_PLAN.md](./UAT_PLAN.md).
- **Upgrade plan** UX links to billing/settings — payment gateway not connected (MoMo future).

---

For launch blockers see [PRODUCTION_SCORECARD.md](./PRODUCTION_SCORECARD.md).
