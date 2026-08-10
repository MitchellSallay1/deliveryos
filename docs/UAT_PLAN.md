# DeliveryOS — UAT plan

**Version:** 1.0 · **Audit date:** 2026-08-08  
**Purpose:** Manual enterprise UAT before production / private beta.  
**Legend — Priority:** P0 launch blocker · P1 must pass for beta · P2 should pass · P3 nice-to-have  
**Status column:** leave blank during execution (Pass / Fail / Blocked / N/A)

**Owner default:** QA · **Environment:** Staging with production-like Supabase + Edge Functions deployed

---

## How to use

1. Apply all migrations to staging (`supabase db push`).
2. Configure Supabase Phone provider + Send SMS Hook (`auth-sms-hook` → WinAggregator) — production-verified end-to-end; AUTH tests below are no longer blocked on SMS delivery.
3. Deploy Edge Functions (`sms-inbound`, `ussd-rider`, `jobs-scheduler`, `api-v1`, `auth-sms-hook`, etc.).
4. Execute tests in order; log defects with Test ID reference.

---

## Authentication & onboarding

| Test ID | Module | Scenario | Steps | Expected result | Priority | Est. |
|---------|--------|----------|-------|-----------------|----------|------|
| AUTH-001 | Auth | Login OTP happy path | Open `/login` → enter valid LR mobile → receive OTP → verify | Session created; redirected to dashboard or setup | P0 | 5m |
| AUTH-002 | Auth | Invalid OTP | Enter wrong code 3× | Friendly error; no session | P0 | 3m |
| AUTH-003 | Auth | Resend cooldown | Request OTP → tap resend before cooldown | Button disabled / countdown | P1 | 2m |
| AUTH-004 | Auth | Logout / login again | Sign out → login with OTP | Same user; no duplicate workspace | P0 | 5m |
| AUTH-005 | Auth | Invite redirect | Open `/invite/:token` logged out → Sign in link → complete OTP | Returns to invite page after login | P0 | 5m |
| ONB-001 | Company | Register delivery company | `/register/company` → OTP → company details → submit | Company + owner membership + trial | P0 | 10m |
| ONB-002 | Merchant | Register merchant | `/register/merchant` → OTP → details | Merchant workspace + trial | P0 | 10m |
| ONB-003 | Rider | Register smartphone rider | Owner creates rider → rider OTP → link invite | Linked rider; `/my-jobs`; no owner workspace | P0 | 15m |
| ONB-004 | Rider | Phone mismatch on link | OTP with different phone than rider record | `invitation_phone_mismatch` / link blocked | P0 | 5m |
| ONB-005 | Setup | Incomplete owner | Auth user without company → `/setup` | Workspace form completes via RPC | P1 | 5m |

---

## Team & access control

| Test ID | Module | Scenario | Steps | Expected result | Priority | Est. |
|---------|--------|----------|-------|-----------------|----------|------|
| TEAM-001 | Team | Phone invite dispatcher | Owner invites phone → invitee OTP → accept token | `company_users` role dispatcher | P0 | 10m |
| TEAM-002 | RBAC | Dispatcher denied admin | Login as dispatcher → navigate `/team` | Access denied / hidden nav | P0 | 3m |
| TEAM-003 | RBAC | Rider blocked from dashboard | Rider persona → `/dashboard` | Redirect to rider routes | P0 | 3m |
| TEAM-004 | Super admin | Admin console | `is_super_admin` user → `/admin` | Admin layout loads | P1 | 5m |

---

## Deliveries & operations

| Test ID | Module | Scenario | Steps | Expected result | Priority | Est. |
|---------|--------|----------|-------|-----------------|----------|------|
| DEL-001 | Deliveries | Create delivery | Fill new delivery form → submit | Tracking code; status pending | P0 | 5m |
| DEL-002 | Deliveries | Assign rider | Pending delivery → select rider → Assign | Status assigned; SMS queued if button-phone | P0 | 5m |
| DEL-003 | Deliveries | Status transition | Advance through allowed next statuses | RPC success; history updated | P0 | 10m |
| DEL-004 | Deliveries | Realtime update | Two browsers same company | Board/table refresh on change | P1 | 5m |
| DEL-005 | Deliveries | Kanban drag | Drag card to valid next column | Same as transition button | P2 | 3m |
| DEL-006 | Deliveries | Trial expired block | Expire trial → create delivery | Friendly `trial_expired` message | P0 | 5m |
| DEL-007 | Tracking | Public track | Open `/track/:code` | Limited fields; no PII leak | P1 | 3m |

---

## Riders & channels

| Test ID | Module | Scenario | Steps | Expected result | Priority | Est. |
|---------|--------|----------|-------|-----------------|----------|------|
| RID-001 | Riders | Create smartphone rider | Add rider with phone + invite | Invite code visible | P0 | 5m |
| RID-002 | Riders | Button-phone rider | access_mode button_phone | No app login; SMS job on assign | P0 | 10m |
| RID-003 | SMS inbound | Accept via SMS | Simulate inbound `A` to edge function | Delivery accepted (staging secret) | P1 | 10m |
| RID-004 | USSD | Menu flow | Hit `ussd-rider` test payload | Valid JSON response | P2 | 10m |
| RID-005 | Rider app | My Jobs transition | Rider advances job on phone | Status updates for company | P0 | 10m |
| RID-006 | Rider | Photo proof | Upload photo on eligible status | Storage + delivery record | P1 | 5m |

---

## Customers, billing, reports

| Test ID | Module | Scenario | Steps | Expected result | Priority | Est. |
|---------|--------|----------|-------|-----------------|----------|------|
| CRM-001 | Customers | Add customer | Save name + phone | Appears in list; selectable on delivery | P1 | 3m |
| CRM-002 | Customers | Duplicate phone upsert | Same phone twice | Upsert behavior per RPC | P1 | 3m |
| BIL-001 | Billing | Trial banner | New company | 7-day trial visible | P0 | 2m |
| BIL-002 | Billing | Plan limits | Exceed rider limit | Friendly limit error | P1 | 5m |
| REP-001 | Reports | Day report | `/reports` day period | Totals match deliveries | P1 | 5m |

---

## Marketplace

| Test ID | Module | Scenario | Steps | Expected result | Priority | Est. |
|---------|--------|----------|-------|-----------------|----------|------|
| MKT-001 | Marketplace | Merchant request | Create external request | Visible to provider | P1 | 10m |
| MKT-002 | Marketplace | Provider accept | Accept offer → delivery | Linked delivery created | P1 | 15m |

---

## Notifications, API, webhooks

| Test ID | Module | Scenario | Steps | Expected result | Priority | Est. |
|---------|--------|----------|-------|-----------------|----------|------|
| NOT-001 | SMS log | Assign delivery SMS | Assign rider | Log row; credit decrement | P1 | 5m |
| API-001 | API v1 | Valid API key | Call edge with key header | 200 + tenant scoped data | P1 | 10m |
| API-002 | API v1 | Rate limit | Burst requests | `rate_limited` friendly error | P2 | 10m |
| WH-001 | Webhooks | Delivery event | Trigger transition | Webhook dispatch queued | P2 | 10m |

---

## UI / cross-cutting

| Test ID | Module | Scenario | Steps | Expected result | Priority | Est. |
|---------|--------|----------|-------|-----------------|----------|------|
| UX-001 | Responsive | Mobile dashboard | 375px viewport | Nav usable; no horizontal overflow | P1 | 10m |
| UX-002 | PWA | Install rider app | Add to home screen | Opens `/my-jobs` | P2 | 5m |
| UX-003 | A11y | Keyboard login | Tab through OTP form | Focus visible | P2 | 5m |
| UX-004 | Branding | Powered by MTN | Login + dashboard | DeliveryOS + partner line | P3 | 2m |
| ERR-001 | Errors | Suspended company | RPC while suspended | Mapped message not raw SQL | P0 | 3m |

---

## Sign-off

| Role | Name | Date | UAT complete (Y/N) |
|------|------|------|-------------------|
| Product | | | |
| QA | | | |
| Engineering | | | |
| Security | | | |
| MTN stakeholder | | | |

**Estimated total (P0+P1):** ~4–6 hours with staging + SMS stub.
