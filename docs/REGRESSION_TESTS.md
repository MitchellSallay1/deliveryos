# DeliveryOS — Regression test suite

Run **before every production deployment** after migrations or auth/billing/delivery changes.

Automated: `npm test` + `npm run build` + (optional) `RUN_DB_TESTS=1 npm run test:db` on staging DB.

---

## REG-AUTH — Authentication & identity

| ID | Workflow | Pass criteria |
|----|----------|---------------|
| REG-AUTH-01 | Phone OTP login | Session + `auth.uid()` stable |
| REG-AUTH-02 | Company register E2E | One company, one owner, trial started |
| REG-AUTH-03 | Rider link E2E | Verified phone + invite → `company_users.rider` |
| REG-AUTH-04 | Team phone invite | Accept with matching phone |
| REG-AUTH-05 | Login redirect to invite | `?redirect=/invite/:token` honored |

---

## REG-DEL — Deliveries core

| ID | Workflow | Pass criteria |
|----|----------|---------------|
| REG-DEL-01 | Create → assign → deliver | Terminal status `delivered` |
| REG-DEL-02 | Subscription guard | Cannot create when trial expired |
| REG-DEL-03 | Cross-tenant isolation | User A cannot read company B delivery (DB test) |
| REG-DEL-04 | Realtime invalidation | Second client sees update within 30s |

---

## REG-RIDER — Rider channels

| ID | Workflow | Pass criteria |
|----|----------|---------------|
| REG-RID-01 | Smartphone rider app job flow | Status transitions via rider RPC |
| REG-RID-02 | Button-phone SMS accept | Inbound edge + status change |
| REG-RID-03 | Button-phone cannot app-login | `link_rider_account` rejects |

---

## REG-BIL — Billing & limits

| ID | Workflow | Pass criteria |
|----|----------|---------------|
| REG-BIL-01 | Trial creation on onboarding | `company_subscriptions` trial row |
| REG-BIL-02 | Rider plan limit | RPC error at limit |
| REG-BIL-03 | SMS credits | Queue fails gracefully at 0 credits |

---

## REG-MKT — Marketplace (if enabled)

| ID | Workflow | Pass criteria |
|----|----------|---------------|
| REG-MKT-01 | Merchant posts request | Provider can view scoped list |
| REG-MKT-02 | Offer accept creates delivery | Single delivery linkage |

---

## REG-ADM — Platform admin

| ID | Workflow | Pass criteria |
|----|----------|---------------|
| REG-ADM-01 | Non-admin blocked from `/admin` | Redirect / deny |
| REG-ADM-02 | Admin activate company | `companies.status` → active |

---

## REG-SEC — Security smoke

| ID | Workflow | Pass criteria |
|----|----------|---------------|
| REG-SEC-01 | No service role in browser bundle | grep `service_role` in `dist/` empty |
| REG-SEC-02 | Public tracking rate limit | Excessive anon calls throttled |
| REG-SEC-03 | Invitation token expiry | Expired token rejected |

---

## CI gate (minimum)

```bash
npm test
npm run build
```

Optional staging gate:

```bash
RUN_DB_TESTS=1 npm run test:db
```

---

## Release record template

| Release | Date | REG run by | Automated CI | Manual REG | Notes |
|---------|------|------------|--------------|------------|-------|
| | | | | | |
