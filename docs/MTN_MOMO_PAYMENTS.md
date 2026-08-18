# MTN MoMo payments (Commerce Phase E2)

PRODUCTION FINANCIAL SYSTEM. Real customer money moves through this code path once configured. Read this document — especially "Known provider-contract uncertainty" and "Never do this" — before touching anything here.

## Architecture

```
Customer submits order (unpaid) -> vendor accepts/prepares/readies (unpaid, same as COD)
  -> vendor requests delivery -> customer selects a carrier offer
  -> select_commerce_delivery_offer locks in that offer + extends its
     reservation so it can't expire mid-payment
  -> customer pays: initiate_commerce_order_mtn_payment (Postgres, fast, sub-second)
                          -> charges subtotal + the SELECTED offer's quoted fee
                          -> creates payment_attempts row, state='created'
                     -> mtn-collect (Edge Function) marks it 'requesting', returns immediately
                     -> EdgeRuntime.waitUntil background task:
                          -> WinAggregatorMtnProvider.collect() (up to ~75s)
                          -> normalizeMtnCollectionResult()
                          -> record_payment_attempt_result (Postgres)
                               -> successful: finalize_successful_payment_attempt
                                    -> mark_commerce_order_paid (existing, Phase A/B)
                                    -> recognize_commerce_order_mtn_financials (vendor + carrier + platform ledger entries)
                               -> failed/pending/unknown: state recorded, nothing else happens automatically
  -> carrier can now accept_marketplace_offer (blocked with payment_not_confirmed until paid)
  -> rider delivery lifecycle proceeds as normal

Customer's browser: subscribes to the payment_attempts row via Supabase Realtime
                     (src/hooks/use-payment-attempts.ts) — never holds an HTTP
                     connection open for the ~60s provider round trip.

Safety net: run_scheduled_maintenance_jobs (jobs-scheduler, every 5 min)
            -> sweep_stuck_payment_attempts() moves a 'requesting' row stuck
               past 3 minutes to 'unknown'. Never re-contacts the provider.
```

## Activation control — off by default, everywhere

MTN MoMo collection does **not** become reachable just because this code and migration are deployed. `initiate_commerce_order_mtn_payment` — the one RPC that can ever create a `payment_attempts` row — checks a platform-wide Super-Admin setting, `mtn_momo_collections_enabled`, as the very first thing it does (before even loading the order):

```sql
IF public.get_platform_setting('mtn_momo_collections_enabled') IS DISTINCT FROM 'true' THEN
  RAISE EXCEPTION 'mtn_momo_collections_disabled';
END IF;
```

This reuses the codebase's one existing Super-Admin runtime-configuration mechanism (`platform_settings` + `get_platform_setting`/`admin_list_platform_settings`/`admin_set_platform_setting`, introduced for `public_app_url` — see `20260309230000_platform_settings_public_app_url.sql`) rather than inventing a parallel one. `20260312000000_mtn_momo_activation_control.sql` extends that RPC's key allowlist to include `mtn_momo_collections_enabled`, adds boolean-specific validation (only the literal `'true'`/`'false'` are accepted — anything else, including an accidental blank, is rejected outright rather than silently stored), and seeds the row as **`'false'`**.

**Why this is the real security control, not the frontend**: the check lives inside the `SECURITY DEFINER` RPC itself, so it applies identically whether the caller is the checkout UI, `mtn-collect` (which calls this exact RPC first), or a direct `supabase.rpc('initiate_commerce_order_mtn_payment', ...)` call from anywhere else — there is no separate code path that skips it. Hiding the MTN option in the checkout UI when this setting is off is a UX nicety on top, not the enforcement boundary.

**Independent of provider credentials, deliberately**: `mtn-collect` still fails closed on its own with `503 not_configured` if `WINAGGREGATOR_MTN_SECRET_STRING`/`WINAGGREGATOR_MTN_COMPANY_NAME` are missing — that check is unchanged and unrelated. Neither condition is a proxy for the other: credentials present + the platform setting `false` still fails closed at the RPC (`mtn_momo_collections_disabled`, mapped to `503` in `mtn-collect`'s `ERROR_MAP`); the platform setting `true` + credentials missing still fails closed at the Edge Function. Both must independently be true before a customer can be charged.

**Activation requires no code deployment.** A super admin flips it live via `/admin/commerce-payments`'s sibling configuration page (`AdminConfigurationPage`, `src/pages/admin/platform-config.tsx` → "MTN MoMo collection — real-money kill switch") calling `admin_set_platform_setting('mtn_momo_collections_enabled', 'true' | 'false')`, or directly via the RPC. `get_platform_setting` is `STABLE`, not cached across calls/connections, so the very next `initiate_commerce_order_mtn_payment` call after activation sees the new value — no redeploy, no connection reset, no propagation delay.

**Disabling never destroys visibility.** The gate exists *only* in `initiate_commerce_order_mtn_payment` (new-attempt creation). `record_payment_attempt_result`, `admin_reconcile_payment_attempt`, `sweep_stuck_payment_attempts`, `admin_list_payment_attempts_page`, and `payment_attempts`' own RLS `SELECT` policy are all completely untouched by this setting — every existing `pending`/`unknown`/`successful` attempt stays fully visible and reconcilable at `/admin/commerce-payments` regardless of whether collection is currently enabled or disabled.

**COD and Orange Money are structurally unaffected.** COD never calls `initiate_commerce_order_mtn_payment` at all (it has its own, separate cash-collection path), so this setting has zero effect on it. `orange_money` is already unconditionally rejected in `submit_commerce_order` (`payment_method_not_available`) independent of this setting, and remains so.

## Why this design, not a single 70-75s request

Supabase Edge Functions allow up to 400s wall-clock (150s on the free plan) and a 150s request-idle-timeout before a 504 — a single ~70-75s synchronous hold technically fits, but leaves the browser holding an open connection for over a minute, which is exactly the situation that produces the ambiguous "did the connection drop before or after the charge?" case this whole system exists to protect against. `mtn-collect` instead does fast, synchronous, DB-only work (creates the attempt, marks it `requesting`) and returns in well under a second; the actual provider round trip runs in `EdgeRuntime.waitUntil`, decoupled from any browser-held connection. The browser watches the `payment_attempts` row via Realtime instead.

**Residual risk of this design**: `EdgeRuntime.waitUntil` background execution is not formally guaranteed to complete (a worker could be recycled mid-flight). This is exactly why `sweep_stuck_payment_attempts` exists — if the background task never reports back, the attempt surfaces as `unknown` for reconciliation rather than being silently lost in `requesting` forever.

## Provider configuration (Edge Function secrets — never in source, never client-side)

| Secret | Purpose |
|---|---|
| `WINAGGREGATOR_MTN_SECRET_STRING` | The provider's `secret_string` credential |
| `WINAGGREGATOR_MTN_COMPANY_NAME` | The provider's `company_name` field |
| `WINAGGREGATOR_MTN_BASE_URL` | Optional override; defaults to `https://winaggregator-mtn.com/mtn/api/v1` |

Missing `WINAGGREGATOR_MTN_SECRET_STRING`/`WINAGGREGATOR_MTN_COMPANY_NAME` makes `mtn-collect` respond `503 {"error":"not_configured"}` **before creating any `payment_attempts` row** — an attempt that could never be processed is worse than no attempt at all.

None of these three values, nor any provider credential, appear in React, Vite env vars (no `VITE_WINAGGREGATOR_*`), browser bundles, public tables, logs, or error responses — verified by grep across the implementation as part of this phase's review.

## Payment state machine

`payment_attempt_state`: `created` → `requesting` → (`successful` | `failed` | `pending` | `unknown`).

| State | Meaning | Automatic transitions out |
|---|---|---|
| `created` | Attempt exists, provider not yet contacted | → `requesting` (`mark_payment_attempt_requesting`, one-shot) |
| `requesting` | Provider request in flight | → any terminal-ish state via `record_payment_attempt_result`; → `unknown` via `sweep_stuck_payment_attempts` if stuck >3 min |
| `pending` | Provider explicitly said "processing" (HTTP 202) | none automatic — see "Reconciliation" |
| `successful` | Provider definitively confirmed the collection | none — terminal |
| `failed` | Provider definitively confirmed rejection/failure | none — terminal |
| `unknown` | DeliveryOS cannot determine what happened | none automatic — see "Reconciliation" |

**`unknown` is never collapsed into `failed`**, and vice versa — enforced structurally: `record_payment_attempt_result` only accepts an explicit `state` parameter built by `normalizeMtnCollectionResult`, which defaults to `unknown` for every case it isn't certain about (timeout, network error, malformed body, unrecognized status vocabulary, contradictory status fields, a 5xx, provider-reported gross/fee/net that don't reconcile even when the provider claimed "successful"). See `_shared/winaggregator-mtn-provider.ts`'s file header for the full, explicit list of conservative branches, and `tests/edge/winaggregator-mtn-provider.test.ts` for the money-failure matrix each one is tested against.

## Double-charge protection

Two independent layers, both database-level, neither merely a disabled React button:

1. **One active attempt per order**: `idx_payment_attempts_order_active`, a partial unique index on `payment_attempts (commerce_order_id) WHERE state IN ('created','requesting','pending','unknown')`. A concurrent second `initiate_commerce_order_mtn_payment` call for the same order fails atomically with `payment_already_in_progress` — this is enforced by Postgres itself, not application logic, and holds even under genuinely concurrent transactions (two browser tabs, a double-click, a retry after a dropped response).
2. **One-shot provider contact per attempt**: `mark_payment_attempt_requesting` only transitions `created` → `requesting`; a second call on the same attempt (e.g. a retried Edge Function invocation) fails outright, so the actual provider `/collection` POST can only ever be sent once per attempt.

**We never automatically resubmit an ambiguous collection.** A network timeout, connection reset, malformed provider response, HTTP 202, or Edge Function interruption never causes DeliveryOS to call `/collection` again for the same (or any) `externalID`. The only way a *new* provider call happens for the same order is a brand-new attempt with a brand-new `externalID`, and that is only ever created by an explicit customer action after a genuinely `failed` attempt — `pending` and `unknown` both continue to block a new attempt via the same unique index above.

## Server-authoritative amounts

The browser sends `{ orderId, msisdn }` to `mtn-collect` — nothing else. `initiate_commerce_order_mtn_payment` (Postgres, `SECURITY DEFINER`) independently: authenticates the caller, loads and locks the customer's currently-selected delivery offer, then locks the order, verifies `customer_id = auth.uid()`, verifies `payment_method = 'mtn_momo'` and `payment_status = 'pending_payment'`, re-verifies the offer is still the selected/pending/unexpired one for this order, and computes the charge as `commerce_orders.subtotal_lrd_cents + delivery_offers.quoted_amount_lrd_cents` on the locked rows. No amount, currency, fee, delivery fee, tenant id, or payment status is ever accepted from the client — the delivery fee component specifically can never be manipulated by the browser because it is read from the locked, server-selected `delivery_offers` row, never from the request body.

## Payment timing — the production flow, and the conflict this phase fixed

**Final flow**: customer submits (unpaid) → vendor accepts → vendor prepares → ready for pickup → vendor requests delivery → customer selects a carrier offer → the final total (merchandise subtotal + that offer's quoted fee) becomes chargeable → customer pays the complete total via MTN MoMo → payment confirmed → carrier can accept and fulfillment proceeds. There is exactly **one** MTN charge per order, for the full gross amount — never a separate second charge for the delivery fee.

This required a real state-machine fix, not just a new RPC. Before this phase, `commerce_order_payment_eligible_for_acceptance` (Phase B.5) required `payment_status = 'paid'` before **any** non-COD order could be vendor-accepted — i.e. the pre-existing system assumed online payment happens *before* the vendor ever sees the order, which is structurally incompatible with "vendor prepares first, payment happens after carrier selection." The fix: `mtn_momo` is now bucketed with `cod` in that function (`payment_status IN ('pending_payment', 'paid')` is eligible for acceptance) — vendor prep proceeds honestly unpaid, exactly like COD. The online-payment gate **moved** to `accept_marketplace_offer` instead: a carrier's own dispatcher acceptance now raises `payment_not_confirmed` for an `mtn_momo` order whose `payment_status <> 'paid'`. This is the correct place for the gate, because carrier acceptance is the point where DeliveryOS commits to real-world fulfillment (assigning a rider, promising the customer a delivery) — everything before that (vendor prep, carrier shopping/selection) is reversible and doesn't require money to have moved yet.

A related latent bug was found and fixed while tracing this: `accept_marketplace_offer` computed `deliveries.amount_to_collect_lrd_cents` (what a rider is told to collect in **cash** on delivery) as `subtotal + offer fee` for every Commerce order regardless of `payment_method` — which would have told a rider to collect cash again for an order the customer already paid electronically. Fixed with an explicit `payment_method = 'mtn_momo' → 0` branch. This could not have shipped before this phase, since no MTN order could previously reach `accept_marketplace_offer` at all (payment happened at checkout in the original design, before any carrier existed).

## Offer/price financial lock during payment

A bounded expiry extension alone is not sufficient protection once real money is involved: once a payment attempt exists using `subtotal + the selected offer's quoted fee`, that offer and price ARE the financial obligation the customer authorized (or is actively authorizing), and must never be silently swappable for a different, differently-priced carrier — not while payment is unresolved, and never after success. Two database-level controls, both keyed off `payment_attempts`, not a timer:

1. **`select_commerce_delivery_offer` refuses to run** (`offer_locked_by_active_payment`) whenever *any* `payment_attempts` row exists for the order in a state other than `failed` — i.e. `created`/`requesting`/`pending`/`unknown`/`successful` all lock. A `failed` attempt (money never moved) is the only thing that releases the lock and allows a fresh selection, including of a different carrier. This is the **primary** control, and it is unbounded — it doesn't matter how long the payment takes.
2. **The routine offer-expiry sweep** (`run_scheduled_maintenance_jobs`) skips any offer that is the `selected_offer_id` of a non-`failed` `payment_attempts` row, no matter how stale its `expires_at` is. The scheduler must never expire an offer a payment is actively using or has already used.

The **bounded 15-minute `expires_at` extension** in `select_commerce_delivery_offer` (still present, unchanged) remains useful for the narrower window *before* any `payment_attempts` row exists yet — selected, not yet paying. Once `initiate_commerce_order_mtn_payment` creates that row, controls #1/#2 above take over as the authoritative, unbounded protection, not a race against a clock.

`accept_marketplace_offer` additionally asserts, defensively, that for an already-paid `mtn_momo` order the offer being accepted is exactly the one — at exactly the price — frozen into the successful `payment_attempts` row (`offer_price_mismatch_with_payment` if not). The lock above should make this unreachable in practice; it exists as a second layer, not the primary control.

**If the selected carrier becomes genuinely unavailable after a successful payment** (e.g. cannot fulfil), this design deliberately does **not** silently substitute a different, differently-priced carrier — no such reassignment path exists. That is a recoverable *operations* state requiring explicit human resolution today (via `admin_reconcile_payment_attempt`'s notes field or a manual support process); a genuine refund/repricing workflow for this case is a documented future item (see "Deferred"), not fabricated here.

**Recovery paths, not dead ends, for the unpaid/failed case**: if a payment attempt definitively fails, `select_commerce_delivery_offer` allows selecting a *different* still-pending offer for the same delivery request (as long as `delivery_id IS NULL`, which stays true until a carrier actually accepts). The order detail page (`src/pages/orders/detail.tsx`) surfaces this: no selected offer or an expired one → "choose a carrier" prompt; selected but unpaid → pay panel; `pending`/`unknown` payment → status panel, no silent retry.

## Lock ordering

`accept_marketplace_offer` has always locked `delivery_offers` first, then `commerce_orders`. `initiate_commerce_order_mtn_payment` deliberately acquires locks in the **same order** (an unlocked pre-read to find the candidate offer, then `FOR UPDATE` on the offer, then `FOR UPDATE` on the order, then re-verifying everything against the now-locked rows) specifically to prevent a cross-function deadlock if a customer is paying and a carrier dispatcher is accepting at the same moment.

## Payment certainty vs. economic anomaly

These are two separate questions, and this system never conflates them. A **definitively successful** MTN collection — provider evidence internally consistent, and the reported gross matches the authoritative amount DeliveryOS intended to collect — is **always** recorded as `successful`, full stop, regardless of how the provider's processing fee compares to what the platform earns on the transaction. Whether that fee happens to exceed platform commission is purely an **accounting** question, tracked as `payment_attempts.margin_anomaly` and in the recognized ledger event's snapshot — it never changes `state`.

`record_payment_attempt_result` only ever diverts a claimed-`successful` result to `unknown` for genuine evidence problems:
- an internally inconsistent gross/fee/net triple (`gross - fee ≉ net`, or any figure negative), or
- a reported gross that does **not match** `payment_attempts.gross_amount_cents` — the authoritative amount DeliveryOS actually charged for. If the provider's own figures don't agree with what we asked it to collect, that is not trustworthy evidence for *this* charge, regardless of how internally consistent it looks in isolation.

Neither of these is an economic judgment — both are "can we trust this evidence enough to fulfil the order," which is the only thing `unknown` means.

## Ledger integration

`recognize_commerce_order_mtn_financials` recognizes **both** legs in one balanced financial event, fed entirely by the frozen `payment_attempts` snapshot (see "Snapshotting the authoritative payable" below), never a live re-read of the order/offer:

- **Vendor leg**: `compute_commerce_vendor_fee_split(subtotal, vendor_company_id)` — same function, same split, COD uses.
- **Carrier leg**: `compute_marketplace_fee_split(delivery_fee, merchant_company_id, provider_company_id)` — the same split `accept_marketplace_offer` computes independently for its own, separate `marketplace_transactions` ledger.
- Debits a new `provider_clearing` account for the gross amount instead of `cod_clearing` — no cash is physically held by anyone in a MoMo collection, so the COD "cash held pending deposit" semantics would be wrong here.
- Credits `platform_revenue` with **exactly** what the Commerce/marketplace fee rules produced (vendor commission + carrier commission) — never reduced by the provider fee.
- In the **same** event, debits a dedicated `payment_processing_expense` account with the **full** provider fee (never capped at available commission) and credits `provider_clearing` for it, so `provider_clearing`'s net balance still ends up `gross - fee`, matching what WinAggregator actually credited.

**Provider-fee accounting treatment (corrected)**: the customer is charged the advertised gross total (subtotal + delivery fee). **Vendor and carrier payables are never reduced by the provider's processing fee** — their contractual payable is exactly what `compute_commerce_vendor_fee_split`/`compute_marketplace_fee_split` would have paid them anyway. **Platform revenue is also never reduced by the fee** — it is exactly the commission the fee rules produced. The fee is instead a separate, honestly-recorded expense, and the resulting transaction margin (`platform_revenue - payment_processing_expense`, stored as `transaction_margin_lrd_cents` in the event's `snapshot`) is allowed to be **negative** — recorded as-is, never fabricated into a positive number, never silently absorbed by inventing negative revenue. `margin_anomaly` (`true` when `fee > commission`) is set on both the `payment_attempts` row and the event snapshot, and a super admin can isolate every such transaction via `admin_list_payment_attempts_page(p_margin_anomaly_only := true)` or the "Margin anomaly" filter at `/admin/commerce-payments` — an operational/financial review queue, not a payment-uncertainty signal.

Note the platform's current commission rate on the merchandise leg is `zero_commission` by default (`commerce_fee_rules`, "no commission yet") — meaning for a store with no fee-rule override, *any* nonzero provider fee currently produces a `margin_anomaly` unless the carrier leg's commission (10% platform default, `marketplace_fee_rules`) covers it on its own. This is a real, current business-policy consequence of the zero-commission default — worth reviewing before charging real customers, since it means most transactions may show as margin anomalies until vendor-side commission is turned on. It no longer blocks fulfillment; it is now purely a visibility/reporting concern.

`reverse_commerce_order_financials` (Phase E1) was widened to match `event_type IN ('cod_collected', 'mtn_momo_collected')` — the two reversal call sites (`vendor_reject_commerce_order`, `customer_cancel_commerce_order`) were already written in Phase E1 anticipating this and now correctly reverse an MTN-prepaid order's financials too, unchanged otherwise.

**Provider fee is never a hardcoded percentage.** `record_payment_attempt_result` stores whatever `gross_amount`/`provider_fee_deducted`/`net_merchant_credited` the provider actually reported (via `provider_gross_amount_cents`/`provider_fee_cents`/`provider_net_cents`), and validates internal consistency (`gross - fee ≈ net`, within 1 cent, all non-negative, and gross matching what was actually charged) before trusting a `successful` claim — see "Payment certainty vs. economic anomaly" above. A DB-level `CHECK` constraint (`payment_attempts_provider_amounts_nonneg`) additionally forbids ever *storing* a negative gross/fee/net, as a second, structural layer under the application-level check. Money is parsed via `parseDecimalToCents` (string-safe digit reconstruction, never naive `value * 100` floating-point multiplication) wherever the provider gives a string.

## Snapshotting the authoritative payable

`payment_attempts` freezes `subtotal_snapshot_lrd_cents` and `delivery_fee_snapshot_lrd_cents` at initiation time (alongside the existing `gross_amount_cents`, `selected_offer_id`, and `currency`), enforced equal to `gross_amount_cents` by a `CHECK` constraint. Every downstream calculation that needs "what did the customer actually authorize" — the margin-anomaly commission estimate, ledger recognition itself — reads these frozen columns, never `commerce_orders.subtotal_lrd_cents` or `delivery_offers.quoted_amount_lrd_cents` live. This is what makes provider reconciliation and later auditing able to prove exactly what was charged, independent of anything that happens to the live order/offer rows afterward. Structural lookups (company ids for ledger scoping, `order_number` for descriptions) still join the live rows, since those aren't prices and aren't what this guarantee covers.

## Duplication proof

`recognize_commerce_order_mtn_financials` is idempotent via a `UNIQUE` `commerce_financial_events.idempotency_key = 'mtn_momo_collected:<order_id>'` (check-then-return before insert). Its only callers are `finalize_successful_payment_attempt`, itself only called from `record_payment_attempt_result` (gated to fire only from `state = 'requesting'`, itself one-shot per attempt) and `admin_reconcile_payment_attempt` (gated to fire only from `pending`/`unknown`). COD's `recognize_commerce_order_financials` is never invoked for an `mtn_momo` order — its only caller, `trg_sync_commerce_order_payment_from_cod`, is itself gated on `payment_method = 'cod'`. `accept_marketplace_offer` writes to a separate, independent ledger (`marketplace_transactions`/`marketplace_ledger_entries` — the carrier's own earnings book) that has always run independently of `commerce_ledger_entries`, for COD too — not a new duplication surface. `commerce_phase_e2.test.sql` proves this end-to-end: one MTN order taken through carrier selection → MTN success → carrier acceptance → rider assignment → delivered → completed produces exactly one `mtn_momo_collected` financial event, checked once immediately after carrier acceptance and again after the full delivery lifecycle completes.

## Reconciliation

Two seams, both deliberately manual/passive — no automated provider lookup exists, because none is confirmed to exist (see below):

- **`sweep_stuck_payment_attempts`** (automatic, via the scheduler): moves a `requesting` attempt stuck past 3 minutes to `unknown`. Never contacts the provider.
- **`admin_reconcile_payment_attempt`** (manual, super-admin-only): after independently verifying the true outcome out-of-band (WinAggregator support, a future real provider lookup), an admin records `confirmed_successful` / `confirmed_failed` / `still_unresolved` for a `pending`/`unknown` attempt. A `confirmed_successful` resolution runs through the exact same `finalize_successful_payment_attempt` path as an automatic success, so fulfillment logic exists in exactly one place regardless of who/what established the outcome. Visible at `/admin/commerce-payments`.

When the provider eventually documents a real reconciliation mechanism (confirmed idempotent `externalID`, a transaction-status lookup endpoint, webhook notifications carrying `externalID`), that mechanism should call the same underlying resolution path `admin_reconcile_payment_attempt` uses — the seam does not need to be redesigned, only its caller changed from a human to an automated lookup.

## Customer retry policy

| Attempt state | New payment allowed? |
|---|---|
| `failed` | Yes — a brand-new attempt with a brand-new `externalID` |
| `pending` | No — blocked by the active-attempt unique index |
| `unknown` | No — blocked the same way, until a human reconciles it |
| `successful` | No — the order is already paid; `order_not_payable` |

The UI (`MtnPaymentStatusPanel`) only ever offers "Try again" when `state = 'failed'`. It never tells a customer "payment failed, try again" for an `unknown` result — the copy explicitly says DeliveryOS could not confirm the outcome and that a retry is not being offered because it can't yet be proven safe.

## MSISDN handling

`validateMtnMsisdn` (`_shared/winaggregator-mtn-provider.ts`) reuses the exact same Liberia digit-handling rules as `normalizeLiberianPhone` (`_shared/sms-provider.ts`) and `normalize_phone_lr` (Postgres) — not a second, divergent formatter. A malformed number is rejected outright, never silently coerced into a different, valid-looking number. **Carrier-specific (MTN-only vs. Orange) prefix validation is NOT implemented** — see "Known provider-contract uncertainty."

## Tenant isolation

`payment_attempts` RLS: `is_super_admin() OR created_by = auth.uid() OR company_id IN user_company_ids()` — the paying customer and the vendor tenant can see an attempt; no one else can. No INSERT/UPDATE/DELETE policy exists for any client role — every write goes through a `SECURITY DEFINER` RPC. Proven by adversarial pgTAP tests (`commerce_phase_e2.test.sql`): cross-vendor visibility, cross-customer initiation, anonymous initiation, and non-admin reconciliation are all explicitly tested as blocked.

## Known provider-contract uncertainty

Documented here, not guessed around anywhere in the code:

- **Is `externalID` a true idempotency key?** Not confirmed. This system never relies on it being one — it never resubmits the same `externalID`, and treats every ambiguous outcome as `unknown` rather than assuming a retry would be safe.
- **Can a transaction be looked up by `externalID`?** Not confirmed. No such lookup is implemented; `admin_reconcile_payment_attempt` exists as the seam for when this is confirmed.
- **Does a timeout/202 mean the customer was or wasn't charged?** Not confirmed either way — treated as `unknown`/`pending` respectively, never as proof of anything.
- **Exact `transaction_status`/`response.status` vocabulary** — not documented beyond the brief's examples. `normalizeMtnCollectionResult` only trusts a small explicit allow-list (`successful`/`success`/`completed`/`confirmed` and `failed`/`failure`/`declined`/`rejected`/`cancelled`); anything else is `unrecognized_status` → `unknown`.
- **Units of `gross_amount`/`provider_fee_deducted`/`net_merchant_credited`** — the documentation examples show decimal-style values (`25.0`, `0.50`, `24.50`), not confirmed against a real response. If the real provider returns integer cents instead, `parseDecimalToCents` would misinterpret every figure by 100x. Parsing is kept isolated to `_shared/winaggregator-mtn-provider.ts` and fails closed (an unparseable or inconsistent figure forces `unknown`, never `successful`) specifically because this is unconfirmed.
- **Liberian MTN-specific MSISDN prefixes** — the brief references "supported Liberian MTN prefixes" without enumerating them; inventing digits would be a fabricated business fact, so this is not implemented. Liberia-general MSISDN validation is enforced instead.

**Never manually retry an UNKNOWN collection by blindly sending another provider request.** If a real reconciliation mechanism is confirmed later, wire it into `admin_reconcile_payment_attempt`'s call path — do not add a new "just try again" button anywhere in this system.

## Mandatory production activation test (before any real-money deployment)

This is a hard gate, not a suggestion. Before `WINAGGREGATOR_MTN_SECRET_STRING`/`WINAGGREGATOR_MTN_COMPANY_NAME` are ever set to real production credentials and this path is used for a real customer:

1. Perform one controlled, minimum-value real MTN MoMo transaction against WinAggregator's live endpoint (the smallest amount the provider will accept — a few LRD).
2. Record, side by side: the amount **sent** in the request, the `gross_amount` **returned**, the `provider_fee_deducted` **returned**, the `net_merchant_credited` **returned**, and the **actual debit** observed on the MTN wallet used to pay (via the wallet's own transaction history/SMS receipt, not anything DeliveryOS computed).
3. Confirm all four/five figures agree once run through `parseDecimalToCents` — i.e. that the assumed decimal-string unit convention is correct, not off by 100x or otherwise misparsed.
4. Only after this is confirmed and documented (date, amount, provider response payload, wallet evidence) should real customer traffic be allowed to reach `mtn-collect` with production credentials configured.

Do not skip this because the code "looks correct" — the entire point is that provider unit conventions are documented inconsistently and this system has never seen a real response.

## Incident recovery

1. Check `/admin/commerce-payments`, filter "Needs attention" (`pending`/`unknown`/`requesting`).
2. For a `requesting` row older than a few minutes with no sweep having run yet: wait for the next scheduler tick (≤5 min) or manually run `select public.sweep_stuck_payment_attempts();` in the SQL editor.
3. For `pending`/`unknown` rows: contact WinAggregator/MTN support directly with the `external_id` (and `provider_reference_id`/`financial_transaction_id` if present) to determine the true outcome. Never assume either way.
4. Once confirmed, an admin resolves it via `/admin/commerce-payments` → expand the row → "Confirm successful" / "Confirm failed" / "Save note only", with the verification method recorded in the notes field (this becomes part of the audit trail via `log_audit_event`).
5. A `confirmed_failed` resolution does **not** create a new payment attempt — the customer (or a support agent on their behalf) initiates a fresh one afterward, same as any other failed-attempt retry.

## Safe test procedure (no real credentials, no real transactions)

- With `WINAGGREGATOR_MTN_SECRET_STRING`/`WINAGGREGATOR_MTN_COMPANY_NAME` unset locally, `mtn-collect` fails closed with `503` before ever writing a `payment_attempts` row. To exercise the state machine without real credentials, call the Postgres RPCs directly (`initiate_commerce_order_mtn_payment`, `mark_payment_attempt_requesting`, `record_payment_attempt_result`) as done throughout `commerce_phase_e2.test.sql` — this is the supported, real way to test every state transition, ledger entry, and RLS boundary without touching the network.
- `tests/edge/winaggregator-mtn-provider.test.ts` mocks `fetch` entirely — no real credentials are used or needed, and none should ever be added to a test file.

## Deferred (explicitly, not silently)

- **Post-payment carrier reassignment/refund-and-reprice workflow**: if the carrier locked into a successful payment becomes genuinely unable to fulfil, there is no automated path to substitute a different, differently-priced carrier or adjust/refund the difference — see "Offer/price financial lock during payment." Today this is a manual operations/support resolution. A real workflow (partial refund, re-charge the difference, or similar) is future work, not built here.
- Automated provider reconciliation (externalID lookup / webhook) — the manual seam exists; the automated caller does not, because no confirmed mechanism exists to call.
- Subscription payments and SMS-allowance top-ups via MTN MoMo (`payment_attempts.purpose` is designed to extend to these; only `'commerce_order'` is implemented).
- Withdrawals/disbursement (`/withdraw`) — explicitly out of scope per the phase brief; a materially higher-risk feature deserving its own audited phase.
- Refunds — `reverse_commerce_order_financials` is the ledger-side reversal primitive (already existed, now correctly reachable for MTN too), but no actual MTN/WinAggregator refund API call is implemented; a reversal today is bookkeeping only.
- A company-facing "preferred payment method" setting, an admin-configurable provider-fee display, and a dedicated MTN template/branding on the payment status panel.
