-- DeliveryOS · Commerce Phase E2 — MTN MoMo payment engine (WinAggregator)
--
-- PRODUCTION FINANCIAL SYSTEM. Read the header comments below before
-- touching this file — they encode decisions made after auditing the
-- existing Commerce ledger, payment tables, and RLS conventions, not
-- assumptions. See docs/MTN_MOMO_PAYMENTS.md for the full writeup.
--
-- ============================================================================
-- WHY A NEW TABLE, NOT payments OR subscription_billing_payments
-- ============================================================================
-- public.payments (initial_schema.sql) is COD-specific: it represents cash a
-- RIDER physically collects and later deposits (collected_by -> riders,
-- collected_at/deposited_at). There is no concept of a provider, an
-- externalID, a request/response cycle, or an ambiguous outcome — COD is
-- either "not yet collected" or "collected," decided by a human, not a
-- network call.
--
-- public.subscription_billing_payments (phase4_billing_schema.sql) is
-- explicitly manual: "recorded_by UUID NOT NULL REFERENCES auth.users" — a
-- human admin typing in what they were told happened. It has no state
-- machine, no idempotency key, no concept of "pending" or "unknown."
--
-- Neither can safely represent a real-money provider round-trip where the
-- outcome may be ambiguous. This migration adds the smallest new structure
-- that can: public.payment_attempts.
--
-- ============================================================================
-- WHY A FIRE-THEN-BACKGROUND-POLL DESIGN, NOT A SYNCHRONOUS 70-75s REQUEST
-- ============================================================================
-- Audited: Supabase Edge Functions allow up to 400s wall-clock (paid plan;
-- 150s free) and a 150s request-idle-timeout before a 504 — a single
-- ~70-75s synchronous hold technically fits, but leaves the browser holding
-- an open HTTP connection for over a minute, which is exactly the situation
-- that produces the ambiguous "client disconnected, did the provider still
-- charge them?" case this entire design exists to protect against. Minimizing
-- that window is itself a correctness improvement, not just a UX one.
--
-- Chosen design: the customer-facing Edge Function (mtn-collect, not part of
-- this migration) does fast, synchronous, DB-only work — auth, tenant,
-- order, amount, idempotency/lock — calling initiate_commerce_order_mtn_
-- payment below (sub-second), then returns immediately. It fires the actual
-- provider call via EdgeRuntime.waitUntil (already used once in this
-- codebase for whatsapp-webhook's router), which can safely run for the
-- full ~60s provider window well within the wall-clock budget, decoupled
-- from any browser-held connection. The browser instead polls
-- payment_attempts (or subscribes to it) for status. record_payment_
-- attempt_result below is what that background task calls once it has a
-- normalized outcome; sweep_stuck_payment_attempts is the safety net if the
-- background task itself never completes (worker recycled, etc.) — it can
-- only ever move a stuck 'requesting' row to 'unknown', never re-contact
-- the provider.
--
-- ============================================================================
-- PAYMENT TIMING — REVISED (production-flow correction pass)
-- ============================================================================
-- FIRST DRAFT of this migration charged commerce_orders.subtotal_lrd_cents
-- alone, at checkout time, leaving a hypothetical second MTN charge for the
-- delivery fee once a carrier was assigned. That is NOT the production
-- flow: the delivery fee must be paid together with the merchandise total,
-- in ONE charge, and the state machine audit below explains exactly why
-- payment cannot happen at checkout time and what changed instead.
--
-- State-machine conflict found: commerce_order_payment_eligible_for_
-- acceptance (Phase B.5) already required payment_status = 'paid' before
-- ANY non-COD order could be vendor-accepted — i.e. the existing system
-- already assumed online payment happens BEFORE the vendor even sees the
-- order, which is incompatible with "vendor accepts -> prepares -> ready
-- -> requests delivery -> customer picks a carrier -> pay the final total."
-- At the point a carrier is picked, vendor acceptance has necessarily
-- already happened — so requiring payment before acceptance and wanting
-- payment after carrier selection are mutually exclusive for the same
-- order lifecycle.
--
-- Smallest safe fix (not a bypass): move the online-payment gate from
-- vendor acceptance to carrier acceptance instead of removing it.
--   - commerce_order_payment_eligible_for_acceptance now treats 'mtn_momo'
--     the same as 'cod' (eligible while pending_payment) — vendor accept/
--     prepare/ready/request-delivery all proceed unpaid, exactly like COD.
--   - accept_marketplace_offer (the CARRIER's own commitment step — a real
--     human dispatcher action, not an automatic side effect of payment)
--     now requires payment_status = 'paid' for an mtn_momo commerce order
--     before it can succeed. This is the new home for "payment before
--     fulfillment proceeds," moved from vendor acceptance to carrier
--     acceptance because that is the point the phase brief actually wants
--     it, and the point at which the final total (subtotal + the
--     customer's selected offer) is knowable.
--   - initiate_commerce_order_mtn_payment now requires a delivery offer the
--     customer has already selected (select_commerce_delivery_offer) and
--     charges subtotal_lrd_cents + that offer's quoted_amount_lrd_cents —
--     both server-read from the locked order/offer rows, never client
--     input. See "LOCK ORDERING" below for why this reads the offer FIRST.
--
-- ============================================================================
-- OFFER/PRICE LOCK DURING PAYMENT (correction pass — supersedes the
-- original "bounded reservation window is enough" design below)
-- ============================================================================
-- A 15-minute expires_at extension alone is NOT sufficient: once an MTN
-- attempt exists using subtotal + a selected offer's quoted fee, that offer
-- and price ARE the financial obligation the customer authorized (or is
-- actively authorizing) — a subsequent expiry must never silently allow a
-- differently-priced carrier to replace it after money has moved, or while
-- it might be moving. Two enforcement points, both database-level:
--
--   1. select_commerce_delivery_offer now raises offer_locked_by_active_
--      payment if ANY payment_attempts row exists for the order in a state
--      OTHER than 'failed' (i.e. created/requesting/pending/unknown/
--      successful) — the customer cannot reselect while a payment is
--      unresolved, and cannot EVER reselect after a success (a genuinely
--      different carrier at that point requires an explicit future refund/
--      repricing workflow — deliberately not built in this phase; see
--      docs/MTN_MOMO_PAYMENTS.md). A 'failed' attempt (money never moved)
--      releases the lock and a fresh selection is allowed. This is now the
--      PRIMARY control.
--   2. run_scheduled_maintenance_jobs' offer-expiry sweep now skips any
--      offer that is the selected_offer_id of a payment_attempts row NOT
--      in 'failed' state, regardless of how stale expires_at is — the
--      scheduler must never expire an offer a payment is actively using or
--      has already used.
--
-- The bounded 15-minute expires_at extension (still present in
-- select_commerce_delivery_offer, see below) remains useful for the
-- narrower gap BEFORE any payment_attempts row exists yet (selected, not
-- yet paying) — once initiate_commerce_order_mtn_payment creates that row,
-- control #1/#2 above are the authoritative, unbounded protection, not a
-- race against a timer.
--
-- accept_marketplace_offer additionally asserts (defensively — the lock
-- above should make this unreachable) that for an already-paid mtn_momo
-- order, the offer being accepted is EXACTLY the one, at EXACTLY the price,
-- frozen into the successful payment_attempts row — "carrier acceptance
-- after successful payment must consume that same locked quote."
--
-- If the selected carrier becomes genuinely unavailable AFTER a successful
-- payment (e.g. the carrier can no longer fulfil), this design deliberately
-- does NOT silently substitute another, differently-priced carrier — no
-- such reassignment path exists. That is a recoverable operations state
-- requiring explicit human resolution (admin_reconcile_payment_attempt's
-- notes field, or a support-driven manual process today); a genuine future
-- refund/repricing workflow is documented as deferred, not fabricated here.
--
-- ============================================================================
-- CARRIER RESERVATION DURING PAYMENT (original design, still the mechanism
-- for the PRE-payment-attempt window — see "OFFER/PRICE LOCK" above for the
-- stronger, payment_attempts-based protection once an attempt exists)
-- ============================================================================
-- Between "customer selects an offer" and "an MTN payment attempt exists,"
-- the offer must not be stolen, expired, or double-booked:
--   - Only the SELECTED offer's own provider can call accept_marketplace_
--     offer for a Commerce order — an unrelated provider's offer for the
--     same request is rejected with offer_not_selected_by_customer. This
--     guard already existed (Phase D) and needed no change.
--   - select_commerce_delivery_offer extends the selected offer's
--     expires_at to at least a 15-minute reservation window when the order
--     is mtn_momo and still unpaid, so the routine 5-minute maintenance
--     sweep (run_scheduled_maintenance_jobs) does not expire an offer out
--     from under a customer who has selected it but not yet started paying.
--   - If an offer expires anyway (clock skew, an unusually slow customer)
--     or a payment attempt is created and definitively FAILS, nothing about
--     this design creates a dead end: select_commerce_delivery_offer still
--     allows selecting a DIFFERENT still-pending offer for the same
--     delivery_request as long as delivery_id is NULL and no non-failed
--     payment_attempts row exists (see "OFFER/PRICE LOCK" above) — a paid
--     order with no currently usable offer is a recoverable, visible state
--     (surfaced to the customer/vendor via the existing order/offer UI, and
--     to admins via /admin/commerce-payments), not a silent trap — see
--     docs/MTN_MOMO_PAYMENTS.md "Carrier reservation and recovery."
--
-- ============================================================================
-- LOCK ORDERING (deadlock avoidance)
-- ============================================================================
-- accept_marketplace_offer locks delivery_offers THEN commerce_orders (it
-- always has — offer first, to serialize concurrent accept attempts on the
-- same offer, THEN the linked commerce order). initiate_commerce_order_mtn_
-- payment now also needs both rows locked (to safely read the offer's
-- quoted amount and the order's subtotal together). It acquires them in
-- the SAME order — offer first, then order — even though it logically
-- "starts" from the order, specifically so two concurrent transactions (a
-- carrier dispatcher clicking accept at the same moment a customer starts
-- paying) can never deadlock by taking these two locks in opposite order.
--
-- ============================================================================
-- PAYMENT CERTAINTY vs. ECONOMIC ANOMALY (correction pass, section 1 —
-- supersedes this migration's original fail-closed-on-fee design)
-- ============================================================================
-- A definitively successful MTN collection (provider evidence internally
-- consistent, gross matches the authoritative amount we intended to
-- collect) is ALWAYS recorded as 'successful' — full stop. Whether the
-- provider's processing fee happens to exceed what this transaction earns
-- the platform in commission is a completely separate question: an
-- accounting/margin concern, not a payment-certainty concern. The original
-- design conflated the two (forcing 'unknown' whenever fee > commission,
-- which would have been lying about payment certainty to avoid an
-- unfavorable-looking transaction). Corrected: record_payment_attempt_
-- result now only ever diverts to 'unknown' for genuine evidence problems
-- (inconsistent gross/fee/net, or a gross that doesn't match what we
-- charged) — never for economics. See that function's own header comment.
--
-- ============================================================================
-- LEDGER INTEGRATION
-- ============================================================================
-- recognize_commerce_order_financials (Phase E1) is COD-only by construction
-- (hardcoded idempotency key 'cod_collected:<order>', hardcoded event_type
-- 'cod_collected', debits cod_clearing — a "cash physically held" account
-- that is semantically wrong for electronic prepayment: no cash is held by
-- anyone). This migration adds a parallel recognize_commerce_order_mtn_
-- financials that reuses compute_commerce_vendor_fee_split UNCHANGED (same
-- vendor_payable/platform_revenue split COD uses) AND compute_marketplace_
-- fee_split UNCHANGED (same carrier_payable split COD's carrier leg uses,
-- fed by the SAME frozen amounts this payment charged for — see
-- "SNAPSHOTTING THE AUTHORITATIVE PAYABLE"), but debits a NEW
-- provider_clearing account for the gross amount instead of cod_clearing.
--
-- Provider-fee accounting treatment (corrected — a new dedicated expense
-- account, not a reduction of platform_revenue): the customer is charged
-- the full advertised subtotal + delivery total. Vendor_payable and
-- carrier_payable are computed from the split functions exactly as COD
-- computes them and are NEVER reduced by the provider's processing fee.
-- Platform_revenue is credited with exactly what the Commerce/marketplace
-- fee rules produced — also never reduced by the fee. The fee itself is
-- debited IN FULL to a new payment_processing_expense account (credit
-- provider_clearing), so provider_clearing's net balance still ends up
-- gross - fee = exactly what WinAggregator actually credited, but the
-- expense is now visible and separate from commission, and the resulting
-- transaction margin (platform_revenue - payment_processing_expense,
-- persisted in the event snapshot as transaction_margin_lrd_cents) is
-- allowed to be negative and recorded honestly — never fabricated into a
-- positive number, never silently absorbed by inventing negative revenue.
-- payment_attempts.margin_anomaly flags this for a super admin to review
-- (admin_list_payment_attempts_page's p_margin_anomaly_only), entirely
-- independent of the attempt's `state`. No fee is ever hardcoded — always
-- the provider-returned, internally-validated figure.
--
-- reverse_commerce_order_financials (Phase E1) is widened from matching
-- only event_type = 'cod_collected' to matching either COD or MTN's event
-- type, so the two dormant reversal call sites Phase E1 already left ready
-- for "MoMo pre-payment lands" now actually work for it, with no other
-- change to those call sites.
--
-- ============================================================================
-- SNAPSHOTTING THE AUTHORITATIVE PAYABLE (correction pass, section 3)
-- ============================================================================
-- payment_attempts now freezes subtotal_snapshot_lrd_cents and delivery_
-- fee_snapshot_lrd_cents at initiation time (in addition to the existing
-- gross_amount_cents, selected_offer_id, and currency), enforced equal to
-- gross_amount_cents by a CHECK constraint. Every downstream calculation
-- that needs "what did the customer actually authorize" — the margin-
-- anomaly estimate, ledger recognition itself — reads these frozen columns,
-- never commerce_orders.subtotal_lrd_cents or delivery_offers.quoted_
-- amount_lrd_cents live. Structural lookups (company ids for ledger
-- scoping, order_number for descriptions) still join the live rows, since
-- those aren't prices and aren't what this guarantee is about.
--
-- ============================================================================
-- DUPLICATION PROOF (see docs/MTN_MOMO_PAYMENTS.md for the full trace)
-- ============================================================================
-- recognize_commerce_order_mtn_financials is idempotent on idempotency_key
-- 'mtn_momo_collected:<order_id>' — a UNIQUE constraint on commerce_
-- financial_events.idempotency_key makes a second INSERT attempt fail, and
-- the function checks-then-returns 'already_recognized' before ever
-- reaching that INSERT. Its only two callers are finalize_successful_
-- payment_attempt's two callers: record_payment_attempt_result (only fires
-- FROM state 'requesting', a one-shot transition per attempt — see that
-- function) and admin_reconcile_payment_attempt (only fires FROM 'pending'/
-- 'unknown', both already-terminal-for-this-attempt once resolved). COD's
-- recognize_commerce_order_financials is never called for an mtn_momo
-- order (its only caller, trg_sync_commerce_order_payment_from_cod, is
-- itself gated on payment_method = 'cod'). accept_marketplace_offer writes
-- to marketplace_transactions/marketplace_ledger_entries, a SEPARATE ledger
-- (the carrier's own earnings book, not commerce_ledger_entries) that has
-- always run independently of commerce financial recognition, for COD too
-- — not a new duplication risk introduced here. commerce_phase_e2.test.sql
-- carries this order through carrier selection -> MTN success -> carrier
-- acceptance -> delivered -> completed and asserts exactly one
-- 'mtn_momo_collected' financial event exists at the end.

-- ---------------------------------------------------------------------------
-- Enums / new ledger vocabulary (additive only)
-- ---------------------------------------------------------------------------
CREATE TYPE public.payment_attempt_state AS ENUM (
  'created', 'requesting', 'pending', 'successful', 'failed', 'unknown'
);

-- Additive to existing enums used by Phase E1's ledger — safe on Postgres
-- 12+ (this project runs 15, per supabase/config.toml) as long as a newly
-- added value isn't used in the SAME statement that adds it; every use
-- below is in a later, separate statement.
ALTER TYPE public.commerce_ledger_account_type ADD VALUE IF NOT EXISTS 'provider_clearing';
-- Payment-processing cost account (correction pass, section 1): the
-- provider's fee is a platform EXPENSE, distinct from platform_revenue
-- (which reflects exactly what the Commerce fee rules produced, never
-- reduced by the fee) and distinct from payment CERTAINTY (a definitively
-- successful collection is never reclassified as 'unknown' just because
-- this expense happens to exceed commission on the transaction).
ALTER TYPE public.commerce_ledger_account_type ADD VALUE IF NOT EXISTS 'payment_processing_expense';
ALTER TYPE public.commerce_financial_event_type ADD VALUE IF NOT EXISTS 'mtn_momo_collected';

-- ---------------------------------------------------------------------------
-- payment_attempts
-- ---------------------------------------------------------------------------
CREATE TABLE public.payment_attempts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Tenant owner (the vendor company) — mirrors how commerce_ledger_entries
  -- scopes tenant ownership for vendor_payable rows.
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE RESTRICT,
  -- TEXT+CHECK, not an enum: purpose is explicitly meant to grow
  -- (subscription, sms_allowance, ...) in future phases without an enum-
  -- widening migration each time. Only 'commerce_order' is implemented now.
  purpose TEXT NOT NULL DEFAULT 'commerce_order' CHECK (purpose IN ('commerce_order')),
  commerce_order_id UUID REFERENCES public.commerce_orders (id) ON DELETE RESTRICT,
  -- The delivery_offers row whose quoted_amount_lrd_cents was priced into
  -- gross_amount_cents (subtotal + this offer's fee). Captured once at
  -- initiation and reused, unchanged, at successful-payment ledger
  -- recognition — the amount charged and the carrier split calculation are
  -- anchored to the exact same offer, not re-derived later. NULL once the
  -- offer's own row is gone (ON DELETE SET NULL) — the amount already
  -- charged is unaffected either way, only the carrier ledger split would
  -- need manual reconciliation in that unlikely case.
  selected_offer_id UUID REFERENCES public.delivery_offers (id) ON DELETE SET NULL,
  provider TEXT NOT NULL DEFAULT 'winaggregator_mtn' CHECK (provider IN ('winaggregator_mtn')),
  payment_method TEXT NOT NULL DEFAULT 'mtn_momo' CHECK (payment_method IN ('mtn_momo')),
  currency TEXT NOT NULL DEFAULT 'LRD' CHECK (currency IN ('LRD', 'USD')),
  -- Authoritative amount DeliveryOS decided to charge — always server-
  -- computed (see initiate_commerce_order_mtn_payment), never client input.
  gross_amount_cents BIGINT NOT NULL CHECK (gross_amount_cents > 0),
  -- Immutable snapshot of what the customer actually authorized (correction
  -- pass, section 3): the merchandise subtotal and the selected offer's
  -- delivery fee, frozen at the exact moment of initiation, on the exact
  -- locked rows initiate_commerce_order_mtn_payment read. Reconciliation and
  -- later auditing must be able to prove what was charged without re-
  -- querying commerce_orders.subtotal_lrd_cents or delivery_offers.
  -- quoted_amount_lrd_cents, both of which are mutable rows that could in
  -- principle change or disappear after this attempt is created.
  -- selected_offer_id above remains a stable pointer for traceability, but
  -- these two columns — not a live join — are the amounts every downstream
  -- calculation (commission estimate, ledger recognition) must use.
  subtotal_snapshot_lrd_cents BIGINT NOT NULL CHECK (subtotal_snapshot_lrd_cents >= 0),
  delivery_fee_snapshot_lrd_cents BIGINT NOT NULL DEFAULT 0 CHECK (delivery_fee_snapshot_lrd_cents >= 0),
  -- Operational/financial review flag (correction pass, section 1): true
  -- when a SUCCESSFUL attempt's provider fee exceeded the platform's own
  -- commission on this transaction. This is an accounting anomaly, not a
  -- payment-certainty question — it never affects `state`. Lets a super
  -- admin identify thin/negative-margin transactions without conflating
  -- "we lost money on this" with "we don't know if the customer was
  -- charged."
  margin_anomaly BOOLEAN NOT NULL DEFAULT false,
  payer_msisdn TEXT NOT NULL,
  -- Server-generated (generate_payment_external_id), immutable, sent to the
  -- provider as externalID. UNIQUE below — never client-supplied.
  external_id TEXT NOT NULL,
  provider_reference_id TEXT,
  financial_transaction_id TEXT,
  state public.payment_attempt_state NOT NULL DEFAULT 'created',
  raw_provider_status TEXT,
  http_status INT,
  -- Provider-reported figures, kept separate from gross_amount_cents (our
  -- own authoritative figure) so a mismatch is visible rather than silently
  -- overwriting what we know we asked for.
  provider_gross_amount_cents BIGINT,
  provider_fee_cents BIGINT,
  provider_net_cents BIGINT,
  failure_category TEXT,
  last_error TEXT,
  attempt_count INT NOT NULL DEFAULT 0,
  requested_at TIMESTAMPTZ,
  submitted_at TIMESTAMPTZ,
  resolved_at TIMESTAMPTZ,
  reconciliation_state TEXT NOT NULL DEFAULT 'not_applicable'
    CHECK (reconciliation_state IN ('not_applicable', 'needs_reconciliation', 'reconciled')),
  reconciled_by UUID REFERENCES auth.users (id) ON DELETE SET NULL,
  reconciled_at TIMESTAMPTZ,
  reconciliation_notes TEXT,
  created_by UUID NOT NULL REFERENCES auth.users (id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT payment_attempts_purpose_shape CHECK (
    purpose <> 'commerce_order' OR commerce_order_id IS NOT NULL
  ),
  CONSTRAINT payment_attempts_provider_amounts_nonneg CHECK (
    (provider_gross_amount_cents IS NULL OR provider_gross_amount_cents >= 0)
    AND (provider_fee_cents IS NULL OR provider_fee_cents >= 0)
    AND (provider_net_cents IS NULL OR provider_net_cents >= 0)
  ),
  -- The authoritative charge is always exactly subtotal + delivery fee, by
  -- construction — this is a structural guarantee that the snapshot and the
  -- amount actually sent to the provider can never silently diverge.
  CONSTRAINT payment_attempts_gross_matches_snapshot CHECK (
    gross_amount_cents = subtotal_snapshot_lrd_cents + delivery_fee_snapshot_lrd_cents
  )
);

CREATE UNIQUE INDEX idx_payment_attempts_external_id ON public.payment_attempts (external_id);

-- THE double-charge guard: at most one "still active" attempt per order at
-- a time, enforced by Postgres itself (a concurrent second INSERT violates
-- this index and fails atomically), not by application-level locking or a
-- disabled React button. 'successful' and 'failed' are terminal and excluded
-- — a failed attempt legitimately allows a new one (see section 15/customer
-- retry policy in docs/MTN_MOMO_PAYMENTS.md).
CREATE UNIQUE INDEX idx_payment_attempts_order_active ON public.payment_attempts (commerce_order_id)
  WHERE state IN ('created', 'requesting', 'pending', 'unknown');

CREATE INDEX idx_payment_attempts_company ON public.payment_attempts (company_id, created_at DESC);
CREATE INDEX idx_payment_attempts_order ON public.payment_attempts (commerce_order_id, created_at DESC);
CREATE INDEX idx_payment_attempts_reconciliation ON public.payment_attempts (reconciliation_state, created_at)
  WHERE reconciliation_state = 'needs_reconciliation';
CREATE INDEX idx_payment_attempts_stuck_requesting ON public.payment_attempts (requested_at)
  WHERE state = 'requesting';

CREATE TRIGGER payment_attempts_updated_at
  BEFORE UPDATE ON public.payment_attempts
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- The customer-facing payment status UI subscribes to this row (see
-- src/hooks/use-payment-attempts.ts) rather than polling on an interval —
-- same postgres_changes idiom already used for commerce_orders/deliveries
-- in use-customer-orders.ts. RLS (payment_attempts_select below) already
-- scopes what a given realtime subscriber can receive.
ALTER PUBLICATION supabase_realtime ADD TABLE public.payment_attempts;

-- ---------------------------------------------------------------------------
-- RLS — SELECT only for the paying customer and the vendor tenant; every
-- write goes through a SECURITY DEFINER RPC below (same idiom as
-- commerce_financial_events/commerce_ledger_entries in Phase E1). Mirrors
-- commerce_orders_select's exact shape (customer_id = auth.uid() OR
-- vendor_company_id IN user_company_ids()) via created_by/company_id.
-- ---------------------------------------------------------------------------
ALTER TABLE public.payment_attempts ENABLE ROW LEVEL SECURITY;

CREATE POLICY payment_attempts_select ON public.payment_attempts
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR created_by = auth.uid()
    OR company_id IN (SELECT public.user_company_ids())
  );

-- ---------------------------------------------------------------------------
-- External ID generation — mirrors generate_tracking_code's loop-until-
-- unique shape, built on public.random_token_hex (portable, gen_random_uuid-
-- based — NOT gen_random_bytes, which lives in the extensions schema, not
-- public, and was already found unreliable here once before: see
-- 20260308130000_random_tokens_without_gen_random_bytes.sql). Safe to
-- expose to the provider (no internal structure beyond a random token);
-- impossible for a client to choose (server-side only, never accepted as
-- RPC input from the browser).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.generate_payment_external_id()
RETURNS TEXT
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_id TEXT;
BEGIN
  LOOP
    v_id := 'PAY-' || upper(public.random_token_hex(20));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.payment_attempts p WHERE p.external_id = v_id);
  END LOOP;
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.generate_payment_external_id FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- initiate_commerce_order_mtn_payment — the ONLY entry point a customer can
-- reach. Fast (no provider call). Authenticates, resolves tenant, requires
-- an already-selected carrier offer, locks BOTH rows in the SAME order
-- accept_marketplace_offer uses (offer, then order — see migration header
-- "LOCK ORDERING"), verifies authorization/payability, determines the
-- server-authoritative amount (subtotal + the selected offer's quoted
-- amount), and creates exactly one payment_attempt. Never accepts amount/
-- currency/tenant/status/offer choice from the caller as authoritative —
-- p_order_id only identifies WHICH order; every figure charged is read
-- fresh from the locked rows.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.initiate_commerce_order_mtn_payment(
  p_order_id UUID,
  p_msisdn TEXT
)
RETURNS public.payment_attempts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.commerce_orders;
  v_candidate_offer_id UUID;
  v_offer public.delivery_offers;
  v_norm_msisdn TEXT;
  v_amount BIGINT;
  v_attempt public.payment_attempts;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  -- Platform-wide activation control (20260312000000_mtn_momo_activation_
  -- control.sql) — checked FIRST, before touching the order/offer at all.
  -- Defaults closed: an unset/missing row reads as NULL, and only the
  -- literal 'true' opens the gate — anything else (NULL, 'false', a stray
  -- value) fails closed. This is a deliberate Super-Admin runtime switch,
  -- independent of mtn-collect's own WINAGGREGATOR_MTN_* credentials check
  -- — neither condition alone is sufficient to reach the provider.
  IF public.get_platform_setting('mtn_momo_collections_enabled') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'mtn_momo_collections_disabled';
  END IF;

  -- Unlocked pre-read: confirms ownership and finds the candidate offer to
  -- lock FIRST (see "LOCK ORDERING"). Everything read here is re-verified
  -- against the LOCKED rows below before it's trusted for anything.
  SELECT * INTO v_order FROM public.commerce_orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;
  IF v_order.customer_id <> auth.uid() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT o.id INTO v_candidate_offer_id
  FROM public.delivery_offers o
  WHERE o.delivery_request_id = v_order.delivery_request_id
    AND o.selected_by_customer_at IS NOT NULL
    AND o.status = 'pending'
  ORDER BY o.selected_by_customer_at DESC
  LIMIT 1;

  IF v_candidate_offer_id IS NULL THEN
    RAISE EXCEPTION 'no_carrier_selected';
  END IF;

  -- Lock order: offer FIRST, then commerce order — matching
  -- accept_marketplace_offer's lock order exactly to avoid a cross-function
  -- deadlock between a concurrent "customer pays" and "carrier accepts".
  SELECT * INTO v_offer FROM public.delivery_offers WHERE id = v_candidate_offer_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no_carrier_selected';
  END IF;

  SELECT * INTO v_order FROM public.commerce_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;

  -- Re-verify everything against the now-locked, freshly-reread rows — the
  -- pre-read above could be stale by the time both locks are held.
  IF v_order.customer_id <> auth.uid() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF v_order.payment_method <> 'mtn_momo' THEN
    RAISE EXCEPTION 'order_not_mtn_momo';
  END IF;
  IF v_order.payment_status <> 'pending_payment' THEN
    RAISE EXCEPTION 'order_not_payable';
  END IF;
  IF v_order.delivery_id IS NOT NULL THEN
    RAISE EXCEPTION 'delivery_already_created';
  END IF;
  IF v_offer.delivery_request_id <> v_order.delivery_request_id
     OR v_offer.selected_by_customer_at IS NULL
     OR v_offer.status <> 'pending' THEN
    RAISE EXCEPTION 'no_carrier_selected';
  END IF;
  IF v_offer.expires_at IS NOT NULL AND v_offer.expires_at <= now() THEN
    RAISE EXCEPTION 'selected_offer_expired';
  END IF;

  IF NOT public.can_use_feature(v_order.vendor_company_id, 'commerce_enabled') THEN
    RAISE EXCEPTION 'commerce_not_enabled';
  END IF;

  v_norm_msisdn := public.normalize_phone_lr(p_msisdn);
  IF v_norm_msisdn = '' OR length(v_norm_msisdn) < 12 THEN
    RAISE EXCEPTION 'invalid_msisdn';
  END IF;

  -- The final authoritative total: merchandise subtotal + the customer's
  -- selected carrier's quoted delivery fee. Both read from locked rows —
  -- never accepted from the browser. See migration header "PAYMENT TIMING."
  v_amount := COALESCE(v_order.subtotal_lrd_cents, 0) + v_offer.quoted_amount_lrd_cents;
  IF v_amount IS NULL OR v_amount <= 0 THEN
    RAISE EXCEPTION 'invalid_amount';
  END IF;

  BEGIN
    INSERT INTO public.payment_attempts (
      company_id, purpose, commerce_order_id, selected_offer_id, currency, gross_amount_cents,
      subtotal_snapshot_lrd_cents, delivery_fee_snapshot_lrd_cents,
      payer_msisdn, external_id, created_by
    ) VALUES (
      v_order.vendor_company_id, 'commerce_order', v_order.id, v_offer.id, 'LRD', v_amount,
      COALESCE(v_order.subtotal_lrd_cents, 0), v_offer.quoted_amount_lrd_cents,
      v_norm_msisdn, public.generate_payment_external_id(), auth.uid()
    )
    RETURNING * INTO v_attempt;
  EXCEPTION
    WHEN unique_violation THEN
      -- idx_payment_attempts_order_active fired: an attempt is already
      -- active for this order. Translate the raw constraint violation into
      -- a stable, friendly error rather than leaking Postgres internals.
      RAISE EXCEPTION 'payment_already_in_progress';
  END;

  PERFORM public.log_audit_event(
    v_order.vendor_company_id, 'payment_attempt_created', 'payment_attempts', v_attempt.id,
    jsonb_build_object(
      'order_id', v_order.id, 'external_id', v_attempt.external_id, 'gross_amount_cents', v_amount,
      'selected_offer_id', v_offer.id
    )
  );

  RETURN v_attempt;
END;
$$;

REVOKE ALL ON FUNCTION public.initiate_commerce_order_mtn_payment(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.initiate_commerce_order_mtn_payment TO authenticated;

-- ---------------------------------------------------------------------------
-- commerce_order_payment_eligible_for_acceptance (Phase B.5) — 'mtn_momo'
-- now behaves exactly like 'cod': eligible for VENDOR acceptance while
-- genuinely still pending_payment. See migration header "PAYMENT TIMING":
-- the online-payment gate moved to accept_marketplace_offer (carrier
-- acceptance), not vendor acceptance. 'orange_money' (not implemented, can
-- never reach this function since submit_commerce_order blocks it) keeps
-- the old "must already be paid" behavior, so a genuinely different future
-- online method defaults to the safer original semantics unless explicitly
-- opted into the mtn_momo-style flow.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.commerce_order_payment_eligible_for_acceptance(p_order_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN o.payment_method IN ('cod', 'mtn_momo') THEN o.payment_status IN ('pending_payment', 'paid')
    ELSE o.payment_status = 'paid'
  END
  FROM public.commerce_orders o
  WHERE o.id = p_order_id;
$$;

REVOKE ALL ON FUNCTION public.commerce_order_payment_eligible_for_acceptance(UUID) FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- select_commerce_delivery_offer (Phase D) — Phase E2's body plus, per this
-- correction pass, a FINANCIAL LOCK: once a payment_attempts row exists for
-- this order in any state other than 'failed' (created/requesting/pending/
-- unknown/successful), the selected offer/price is part of the financial
-- obligation the customer already authorized (or is actively authorizing)
-- and can never be swapped for a different, differently-priced carrier —
-- not by the customer, not by anything else. See migration header "OFFER/
-- PRICE LOCK DURING PAYMENT". A definitively 'failed' attempt (money never
-- moved) releases the lock — the unique-filtered EXISTS below naturally
-- finds nothing once every attempt for this order is 'failed', allowing a
-- fresh selection.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.select_commerce_delivery_offer(p_order_id UUID, p_offer_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.commerce_orders;
  v_offer public.delivery_offers;
  v_req public.delivery_requests;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT * INTO v_order FROM public.commerce_orders WHERE id = p_order_id AND customer_id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'order_not_found'; END IF;

  IF v_order.delivery_id IS NOT NULL THEN
    RAISE EXCEPTION 'delivery_already_created';
  END IF;
  IF v_order.delivery_request_id IS NULL THEN
    RAISE EXCEPTION 'delivery_not_requested_yet';
  END IF;

  -- Financial lock (correction pass, section 2) — see header comment above.
  IF EXISTS (
    SELECT 1 FROM public.payment_attempts
    WHERE commerce_order_id = v_order.id AND state <> 'failed'
  ) THEN
    RAISE EXCEPTION 'offer_locked_by_active_payment';
  END IF;

  SELECT * INTO v_offer FROM public.delivery_offers WHERE id = p_offer_id FOR UPDATE;
  IF NOT FOUND OR v_offer.delivery_request_id <> v_order.delivery_request_id THEN
    RAISE EXCEPTION 'invalid_offer';
  END IF;
  IF v_offer.status <> 'pending' THEN
    RAISE EXCEPTION 'offer_not_available';
  END IF;
  IF v_offer.expires_at IS NOT NULL AND v_offer.expires_at <= now() THEN
    RAISE EXCEPTION 'offer_expired';
  END IF;

  SELECT * INTO v_req FROM public.delivery_requests WHERE id = v_order.delivery_request_id;
  IF NOT public.provider_matches_delivery_request(v_offer.provider_company_id, v_req) THEN
    RAISE EXCEPTION 'provider_not_available';
  END IF;

  -- A customer can change their mind among still-pending offers — clear
  -- any prior selection on this request before setting the new one.
  UPDATE public.delivery_offers SET selected_by_customer_at = NULL
  WHERE delivery_request_id = v_req.id AND id <> p_offer_id AND selected_by_customer_at IS NOT NULL;

  UPDATE public.delivery_offers SET
    selected_by_customer_at = now(),
    expires_at = CASE
      WHEN v_order.payment_method = 'mtn_momo' AND v_order.payment_status = 'pending_payment' THEN
        GREATEST(COALESCE(expires_at, now()), now() + interval '15 minutes')
      ELSE expires_at
    END
  WHERE id = p_offer_id
  RETURNING * INTO v_offer;

  RETURN to_jsonb(v_offer);
END;
$$;

REVOKE ALL ON FUNCTION public.select_commerce_delivery_offer(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.select_commerce_delivery_offer(UUID, UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- mark_payment_attempt_requesting — called by mtn-collect immediately
-- before the actual provider HTTP call. Only transitions FROM 'created';
-- called twice (e.g. a retried Edge Function invocation) is a safe no-op on
-- the second call, which is exactly what prevents an accidental second POST
-- to the provider for the same attempt.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.mark_payment_attempt_requesting(p_attempt_id UUID)
RETURNS public.payment_attempts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.payment_attempts;
BEGIN
  UPDATE public.payment_attempts SET
    state = 'requesting',
    requested_at = now(),
    attempt_count = attempt_count + 1
  WHERE id = p_attempt_id AND state = 'created'
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'attempt_not_in_created_state';
  END IF;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_payment_attempt_requesting(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_payment_attempt_requesting TO service_role;

-- ---------------------------------------------------------------------------
-- Computes what platform commission this transaction WOULD earn (vendor
-- split + carrier split, the exact same functions recognize_commerce_
-- order_mtn_financials uses below), fed entirely by FROZEN scalar amounts
-- (correction pass, section 3) rather than re-reading commerce_orders.
-- subtotal_lrd_cents / delivery_offers.quoted_amount_lrd_cents live — the
-- offer/order rows are joined only for structural company ids (provider_
-- company_id, merchant_company_id), never for a price. Used by
-- record_payment_attempt_result purely to compute the margin_anomaly flag
-- (correction pass, section 1) — this NEVER gates payment state. STABLE,
-- read-only — safe to call speculatively.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.estimate_commerce_mtn_platform_commission_cents(
  p_vendor_company_id UUID,
  p_subtotal_cents BIGINT,
  p_selected_offer_id UUID,
  p_delivery_fee_cents BIGINT
)
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_offer public.delivery_offers;
  v_req public.delivery_requests;
  v_vendor_split RECORD;
  v_carrier_split RECORD;
  v_total BIGINT := 0;
BEGIN
  SELECT * INTO v_vendor_split
  FROM public.compute_commerce_vendor_fee_split(p_subtotal_cents::INT, p_vendor_company_id);
  v_total := v_total + COALESCE(v_vendor_split.platform_fee_lrd_cents, 0);

  IF p_selected_offer_id IS NOT NULL THEN
    SELECT * INTO v_offer FROM public.delivery_offers WHERE id = p_selected_offer_id;
    IF FOUND THEN
      SELECT * INTO v_req FROM public.delivery_requests WHERE id = v_offer.delivery_request_id;
      SELECT * INTO v_carrier_split
      FROM public.compute_marketplace_fee_split(p_delivery_fee_cents::INT, v_req.merchant_company_id, v_offer.provider_company_id);
      v_total := v_total + COALESCE(v_carrier_split.platform_fee_lrd_cents, 0);
    END IF;
  END IF;

  RETURN v_total;
END;
$$;

REVOKE ALL ON FUNCTION public.estimate_commerce_mtn_platform_commission_cents(UUID, BIGINT, UUID, BIGINT) FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- Ledger recognition — the MTN analog of Phase E1's recognize_commerce_
-- order_financials. See migration header "LEDGER INTEGRATION." Internal
-- only — called by finalize_successful_payment_attempt below, never
-- directly by a client. Recognizes BOTH the vendor leg (subtotal) and the
-- carrier leg (the selected offer's fee, via compute_marketplace_fee_split
-- — the same split accept_marketplace_offer computes for its own, separate
-- marketplace_transactions record) in one balanced event.
--
-- p_subtotal_cents/p_delivery_fee_cents are the FROZEN snapshot amounts
-- from payment_attempts (correction pass, section 3) — never re-read from
-- the live commerce_orders/delivery_offers rows for the purpose of
-- computing what the customer paid. v_order/v_offer/v_req below are still
-- looked up, but only for structural fields (company ids, order_number,
-- customer_id) that a ledger description/company scoping needs, never for
-- an amount.
--
-- Correction pass, section 1: this function NEVER refuses to recognize a
-- genuinely successful payment because the provider fee is economically
-- unfavorable — that would misrepresent payment certainty as an accounting
-- problem. Vendor/carrier payable are exactly what the fee rules produced,
-- untouched by the provider fee. Platform_revenue is exactly the platform's
-- own commission, also untouched. The provider fee is recorded in full as a
-- separate payment_processing_expense debit — the resulting transaction
-- margin (platform_revenue - payment_processing_expense) may be negative,
-- and that is recorded honestly, not fabricated away.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.recognize_commerce_order_mtn_financials(
  p_order_id UUID,
  p_selected_offer_id UUID,
  p_subtotal_cents BIGINT,
  p_delivery_fee_cents BIGINT,
  p_provider_fee_cents BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.commerce_orders;
  v_offer public.delivery_offers;
  v_req public.delivery_requests;
  v_key TEXT := 'mtn_momo_collected:' || p_order_id::TEXT;
  v_existing_event_id UUID;
  v_vendor_split RECORD;
  v_carrier_split RECORD;
  v_carrier_platform_fee BIGINT := 0;
  v_carrier_amount BIGINT := 0;
  v_total_platform_fee BIGINT;
  v_gross BIGINT := GREATEST(COALESCE(p_subtotal_cents, 0), 0) + GREATEST(COALESCE(p_delivery_fee_cents, 0), 0);
  v_event public.commerce_financial_events;
  v_fee BIGINT := GREATEST(COALESCE(p_provider_fee_cents, 0), 0);
  v_margin BIGINT;
BEGIN
  SELECT id INTO v_existing_event_id
  FROM public.commerce_financial_events
  WHERE idempotency_key = v_key;
  IF FOUND THEN
    RETURN jsonb_build_object('event_id', v_existing_event_id, 'already_recognized', true);
  END IF;

  SELECT * INTO v_order FROM public.commerce_orders WHERE id = p_order_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'order_not_found'; END IF;

  -- Structural sanity check: the fee can never legitimately exceed the
  -- entire amount collected — that is not "economically unfavorable," it is
  -- implausible provider data. record_payment_attempt_result's own
  -- consistency check (gross - fee ~= net, all non-negative) already
  -- prevents this from ever reaching a 'successful' state in the first
  -- place, so this is a defensive, should-never-fire second layer.
  IF v_fee > v_gross THEN
    RAISE EXCEPTION 'provider_fee_exceeds_gross_amount';
  END IF;

  SELECT * INTO v_vendor_split
  FROM public.compute_commerce_vendor_fee_split(p_subtotal_cents::INT, v_order.vendor_company_id);

  IF p_selected_offer_id IS NOT NULL THEN
    SELECT * INTO v_offer FROM public.delivery_offers WHERE id = p_selected_offer_id;
    IF FOUND THEN
      SELECT * INTO v_req FROM public.delivery_requests WHERE id = v_offer.delivery_request_id;
      SELECT * INTO v_carrier_split
      FROM public.compute_marketplace_fee_split(p_delivery_fee_cents::INT, v_req.merchant_company_id, v_offer.provider_company_id);
      v_carrier_platform_fee := COALESCE(v_carrier_split.platform_fee_lrd_cents, 0);
      v_carrier_amount := COALESCE(v_carrier_split.provider_amount_lrd_cents, 0);
    END IF;
  END IF;

  v_total_platform_fee := COALESCE(v_vendor_split.platform_fee_lrd_cents, 0) + v_carrier_platform_fee;
  v_margin := v_total_platform_fee - v_fee;

  INSERT INTO public.commerce_financial_events (
    event_type, commerce_order_id, idempotency_key, snapshot, created_by
  ) VALUES (
    'mtn_momo_collected', v_order.id, v_key,
    jsonb_build_object(
      'gross_lrd_cents', v_gross,
      'provider_fee_lrd_cents', v_fee,
      'vendor_gross_lrd_cents', p_subtotal_cents,
      'vendor_fee_rule_id', v_vendor_split.fee_rule_id,
      'vendor_platform_fee_lrd_cents', v_vendor_split.platform_fee_lrd_cents,
      'vendor_net_lrd_cents', v_vendor_split.vendor_amount_lrd_cents,
      'selected_offer_id', p_selected_offer_id,
      'carrier_gross_lrd_cents', p_delivery_fee_cents,
      'carrier_platform_fee_lrd_cents', v_carrier_platform_fee,
      'carrier_net_lrd_cents', v_carrier_amount,
      'total_platform_fee_lrd_cents', v_total_platform_fee,
      -- Honest accounting outcome (correction pass, section 1) — may be
      -- negative. Never fabricated into a non-negative figure.
      'transaction_margin_lrd_cents', v_margin,
      'margin_anomaly', v_fee > v_total_platform_fee
    ),
    v_order.customer_id
  )
  RETURNING * INTO v_event;

  -- Gross collected via the provider, held in DeliveryOS's provider
  -- balance — NOT cod_clearing, no cash is physically held by anyone.
  INSERT INTO public.commerce_ledger_entries (financial_event_id, account_type, direction, company_id, amount_lrd_cents, description)
  VALUES (v_event.id, 'provider_clearing', 'debit', v_order.vendor_company_id, v_gross, 'MTN MoMo collected for order ' || v_order.order_number);

  IF v_vendor_split.vendor_amount_lrd_cents > 0 THEN
    INSERT INTO public.commerce_ledger_entries (financial_event_id, account_type, direction, company_id, amount_lrd_cents, description)
    VALUES (v_event.id, 'vendor_payable', 'credit', v_order.vendor_company_id, v_vendor_split.vendor_amount_lrd_cents, 'Vendor payable for order ' || v_order.order_number);
  END IF;

  IF v_carrier_amount > 0 THEN
    INSERT INTO public.commerce_ledger_entries (financial_event_id, account_type, direction, company_id, amount_lrd_cents, description)
    VALUES (v_event.id, 'carrier_payable', 'credit', v_offer.provider_company_id, v_carrier_amount, 'Carrier payable for order ' || v_order.order_number);
  END IF;

  -- Platform commission is exactly what the Commerce/marketplace fee rules
  -- produced — never reduced by the provider fee.
  IF v_total_platform_fee > 0 THEN
    INSERT INTO public.commerce_ledger_entries (financial_event_id, account_type, direction, company_id, amount_lrd_cents, description)
    VALUES (v_event.id, 'platform_revenue', 'credit', NULL, v_total_platform_fee, 'Platform commission for order ' || v_order.order_number);
  END IF;

  -- Provider processing fee: a payment-processing EXPENSE, entirely
  -- separate from platform_revenue — debited here in FULL (never capped at
  -- available commission), credit provider_clearing so its net balance
  -- ends up gross - fee = what WinAggregator actually credited. This can
  -- legitimately make the transaction's margin negative; that is recorded
  -- honestly via transaction_margin_lrd_cents/margin_anomaly above, not
  -- hidden or fabricated into a positive number.
  IF v_fee > 0 THEN
    INSERT INTO public.commerce_ledger_entries (financial_event_id, account_type, direction, company_id, amount_lrd_cents, description)
    VALUES (v_event.id, 'payment_processing_expense', 'debit', NULL, v_fee, 'WinAggregator MTN processing fee for order ' || v_order.order_number);
    INSERT INTO public.commerce_ledger_entries (financial_event_id, account_type, direction, company_id, amount_lrd_cents, description)
    VALUES (v_event.id, 'provider_clearing', 'credit', v_order.vendor_company_id, v_fee, 'WinAggregator MTN processing fee for order ' || v_order.order_number);
  END IF;

  RETURN jsonb_build_object('event_id', v_event.id, 'already_recognized', false, 'snapshot', v_event.snapshot);
END;
$$;

REVOKE ALL ON FUNCTION public.recognize_commerce_order_mtn_financials(UUID, UUID, BIGINT, BIGINT, BIGINT) FROM PUBLIC;

-- Widen Phase E1's reversal to also find an MTN-collected event — the two
-- call sites (vendor_reject_commerce_order, customer_cancel_commerce_order)
-- were already left ready for this ("once MoMo pre-payment lands, ... these
-- will correctly reverse ... no future rewrite of these functions
-- required" — see 20260309200000_commerce_phase_e1_finance_ledger.sql).
-- Identical body otherwise.
CREATE OR REPLACE FUNCTION public.reverse_commerce_order_financials(p_order_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_original_event public.commerce_financial_events;
  v_reversal_key TEXT;
  v_reversal_event public.commerce_financial_events;
  v_entry RECORD;
BEGIN
  SELECT * INTO v_original_event
  FROM public.commerce_financial_events
  WHERE commerce_order_id = p_order_id AND event_type IN ('cod_collected', 'mtn_momo_collected')
  ORDER BY created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no_financial_event_to_reverse';
  END IF;

  v_reversal_key := 'reversal:' || v_original_event.id::TEXT;

  IF EXISTS (SELECT 1 FROM public.commerce_financial_events WHERE idempotency_key = v_reversal_key) THEN
    RETURN jsonb_build_object('already_reversed', true);
  END IF;

  INSERT INTO public.commerce_financial_events (
    event_type, commerce_order_id, delivery_id, payment_id, reverses_event_id, idempotency_key, snapshot, reason, created_by
  ) VALUES (
    'reversal', v_original_event.commerce_order_id, v_original_event.delivery_id, v_original_event.payment_id,
    v_original_event.id, v_reversal_key, v_original_event.snapshot, p_reason, auth.uid()
  )
  RETURNING * INTO v_reversal_event;

  FOR v_entry IN SELECT * FROM public.commerce_ledger_entries WHERE financial_event_id = v_original_event.id LOOP
    INSERT INTO public.commerce_ledger_entries (financial_event_id, account_type, direction, company_id, amount_lrd_cents, description)
    VALUES (
      v_reversal_event.id, v_entry.account_type,
      (CASE WHEN v_entry.direction = 'debit' THEN 'credit' ELSE 'debit' END)::public.commerce_ledger_direction,
      v_entry.company_id, v_entry.amount_lrd_cents,
      'Reversal of ' || v_entry.description
    );
  END LOOP;

  RETURN jsonb_build_object('event_id', v_reversal_event.id, 'already_reversed', false);
END;
$$;

REVOKE ALL ON FUNCTION public.reverse_commerce_order_financials(UUID, TEXT) FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- Shared success-fulfillment core — used by BOTH the automatic path
-- (record_payment_attempt_result, below) and the manual reconciliation path
-- (admin_reconcile_payment_attempt, below), so "mark paid + recognize
-- financials" happens through exactly one code path regardless of how the
-- success was established. mark_commerce_order_paid's own payment_status <>
-- 'pending_payment' guard plus recognize_commerce_order_mtn_financials'
-- idempotency_key both make this safe to call more than once.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.finalize_successful_payment_attempt(p_attempt_id UUID)
RETURNS public.payment_attempts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_attempt public.payment_attempts;
BEGIN
  SELECT * INTO v_attempt FROM public.payment_attempts WHERE id = p_attempt_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'attempt_not_found'; END IF;

  IF v_attempt.purpose = 'commerce_order' AND v_attempt.commerce_order_id IS NOT NULL THEN
    -- mark_commerce_order_paid raises if the order is already past
    -- pending_payment — caught here so a duplicate fulfillment call is a
    -- safe no-op rather than an error surfaced to the caller.
    BEGIN
      PERFORM public.mark_commerce_order_paid(v_attempt.commerce_order_id);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
    PERFORM public.recognize_commerce_order_mtn_financials(
      v_attempt.commerce_order_id, v_attempt.selected_offer_id,
      v_attempt.subtotal_snapshot_lrd_cents, v_attempt.delivery_fee_snapshot_lrd_cents,
      COALESCE(v_attempt.provider_fee_cents, 0)
    );
  END IF;

  RETURN v_attempt;
END;
$$;

REVOKE ALL ON FUNCTION public.finalize_successful_payment_attempt(UUID) FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- record_payment_attempt_result — called by mtn-collect's background task
-- (EdgeRuntime.waitUntil) with an ALREADY-NORMALIZED outcome (see
-- _shared/winaggregator-mtn-provider.ts's response normalization — this
-- function never sees raw provider JSON). Only transitions FROM
-- 'requesting', which is what makes this idempotent: a retried background
-- task, or a duplicate provider response somehow arriving twice, finds the
-- attempt no longer 'requesting' and this call is a safe, audited no-op.
--
-- Correction pass, section 1 — PAYMENT CERTAINTY vs. ECONOMIC ANOMALY are
-- kept strictly separate here. The ONLY thing that can force a 'successful'
-- claim down to 'unknown' is genuine untrustworthiness of the provider's
-- own evidence (internally inconsistent gross/fee/net). A provider fee that
-- is simply larger than the platform's commission on this transaction is
-- NOT evidence of anything about whether the customer was charged — it is
-- computed into v_margin_anomaly (persisted on the row, surfaced to admins)
-- and otherwise has zero effect on `state`.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_payment_attempt_result(
  p_attempt_id UUID,
  p_state public.payment_attempt_state,
  p_raw_status TEXT,
  p_http_status INT,
  p_provider_reference_id TEXT DEFAULT NULL,
  p_financial_transaction_id TEXT DEFAULT NULL,
  p_provider_gross_cents BIGINT DEFAULT NULL,
  p_provider_fee_cents BIGINT DEFAULT NULL,
  p_provider_net_cents BIGINT DEFAULT NULL,
  p_failure_category TEXT DEFAULT NULL,
  p_error_message TEXT DEFAULT NULL
)
RETURNS public.payment_attempts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_attempt public.payment_attempts;
  v_before public.payment_attempts;
  v_final_state public.payment_attempt_state := p_state;
  v_reconciliation TEXT;
  v_failure_category TEXT := p_failure_category;
  v_available_commission BIGINT;
  v_margin_anomaly BOOLEAN := false;
BEGIN
  IF p_state = 'created' OR p_state = 'requesting' THEN
    RAISE EXCEPTION 'invalid_result_state';
  END IF;

  -- Read the attempt's own frozen snapshot BEFORE the state transition — we
  -- need company_id/subtotal_snapshot/delivery_fee_snapshot/selected_offer_id
  -- for the margin-anomaly computation below regardless of outcome.
  SELECT * INTO v_before FROM public.payment_attempts WHERE id = p_attempt_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'attempt_not_found'; END IF;

  -- Fail-closed sanity check on provider-reported figures (payment
  -- CERTAINTY, not economics): an internally inconsistent gross/fee/net
  -- triple must never be trusted enough to drive successful fulfillment —
  -- force unknown instead, exact values are still stored for later manual
  -- reconciliation. This is the ONLY certainty-related diversion left.
  IF p_state = 'successful' AND p_provider_gross_cents IS NOT NULL
     AND p_provider_fee_cents IS NOT NULL AND p_provider_net_cents IS NOT NULL THEN
    IF p_provider_gross_cents < 0 OR p_provider_fee_cents < 0 OR p_provider_net_cents < 0
       OR abs((p_provider_gross_cents - p_provider_fee_cents) - p_provider_net_cents) > 1
       OR p_provider_gross_cents <> v_before.gross_amount_cents THEN
      v_final_state := 'unknown';
      v_failure_category := 'inconsistent_provider_figures';
    END IF;
  END IF;

  -- Margin-anomaly computation (correction pass, section 1) — an
  -- ACCOUNTING flag only. Computed from the attempt's own frozen snapshot
  -- (never a live re-read of the order/offer), and never changes
  -- v_final_state. A genuinely successful, evidence-trustworthy collection
  -- stays 'successful' no matter how thin or negative the resulting margin.
  IF v_final_state = 'successful' AND p_provider_fee_cents IS NOT NULL THEN
    v_available_commission := public.estimate_commerce_mtn_platform_commission_cents(
      v_before.company_id, v_before.subtotal_snapshot_lrd_cents,
      v_before.selected_offer_id, v_before.delivery_fee_snapshot_lrd_cents
    );
    v_margin_anomaly := p_provider_fee_cents > v_available_commission;
  END IF;

  v_reconciliation := CASE WHEN v_final_state IN ('pending', 'unknown') THEN 'needs_reconciliation' ELSE 'not_applicable' END;

  UPDATE public.payment_attempts SET
    state = v_final_state,
    raw_provider_status = p_raw_status,
    http_status = p_http_status,
    provider_reference_id = p_provider_reference_id,
    financial_transaction_id = p_financial_transaction_id,
    provider_gross_amount_cents = p_provider_gross_cents,
    provider_fee_cents = p_provider_fee_cents,
    provider_net_cents = p_provider_net_cents,
    failure_category = CASE WHEN v_final_state = 'successful' THEN NULL ELSE v_failure_category END,
    last_error = CASE WHEN v_final_state = 'successful' THEN NULL ELSE p_error_message END,
    resolved_at = CASE WHEN v_final_state IN ('successful', 'failed') THEN now() ELSE resolved_at END,
    reconciliation_state = v_reconciliation,
    margin_anomaly = v_margin_anomaly
  WHERE id = p_attempt_id AND state = 'requesting'
  RETURNING * INTO v_attempt;

  IF NOT FOUND THEN
    -- Not an error: the attempt was already resolved (duplicate/retried
    -- call) — return current row as-is, no second state transition.
    SELECT * INTO v_attempt FROM public.payment_attempts WHERE id = p_attempt_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'attempt_not_found'; END IF;
    RETURN v_attempt;
  END IF;

  PERFORM public.log_audit_event(
    v_attempt.company_id, 'payment_attempt_' || v_final_state::TEXT, 'payment_attempts', v_attempt.id,
    jsonb_build_object(
      'external_id', v_attempt.external_id, 'http_status', p_http_status, 'raw_status', p_raw_status,
      'reconciliation_state', v_reconciliation
    )
  );

  IF v_final_state = 'successful' THEN
    PERFORM public.finalize_successful_payment_attempt(v_attempt.id);
  END IF;

  RETURN v_attempt;
END;
$$;

REVOKE ALL ON FUNCTION public.record_payment_attempt_result(
  UUID, public.payment_attempt_state, TEXT, INT, TEXT, TEXT, BIGINT, BIGINT, BIGINT, TEXT, TEXT
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_payment_attempt_result TO service_role;

-- ---------------------------------------------------------------------------
-- Reconciliation safety net — the ONLY automatic transition out of
-- 'requesting' besides record_payment_attempt_result itself. Never calls
-- the provider. Exists for the case where mtn-collect's background task
-- never completes at all (worker recycled mid-flight, etc.) — without this,
-- such an attempt would be stuck in 'requesting' forever with no signal.
-- Threshold is deliberately generous (3 minutes, comfortably longer than
-- the documented ~60s provider window plus normal latency) so it never
-- fires while a genuine in-flight request could still resolve normally.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sweep_stuck_payment_attempts(p_stuck_after_minutes INT DEFAULT 3)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  WITH stuck AS (
    UPDATE public.payment_attempts SET
      state = 'unknown',
      reconciliation_state = 'needs_reconciliation',
      failure_category = 'no_result_recorded',
      last_error = 'No provider result was recorded within the expected window.'
    WHERE state = 'requesting'
      AND requested_at < now() - make_interval(mins => GREATEST(p_stuck_after_minutes, 1))
    RETURNING id, company_id
  )
  SELECT COUNT(*)::INT INTO v_count FROM stuck;

  IF v_count > 0 THEN
    PERFORM public.log_audit_event(
      NULL, 'payment_attempts_swept_unknown', 'payment_attempts', NULL,
      jsonb_build_object('count', v_count)
    );
  END IF;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.sweep_stuck_payment_attempts(INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sweep_stuck_payment_attempts TO service_role;

-- ---------------------------------------------------------------------------
-- Manual reconciliation seam (section 14). A super admin who has verified
-- the true outcome out-of-band (provider support, a future real lookup API)
-- records it here. Deliberately narrow: only resolves an attempt already in
-- 'pending' or 'unknown' — never touches 'successful'/'failed' (already
-- terminal) and never re-contacts the provider itself. When the provider
-- eventually documents a real reconciliation mechanism (externalID lookup,
-- idempotent resubmission, etc.), that mechanism calls
-- finalize_successful_payment_attempt / this same resolution path instead
-- of a human — the seam does not need to be redesigned, only its caller
-- changed from a human to an automated lookup.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_reconcile_payment_attempt(
  p_attempt_id UUID,
  p_resolution TEXT,
  p_notes TEXT DEFAULT NULL
)
RETURNS public.payment_attempts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_attempt public.payment_attempts;
  v_new_state public.payment_attempt_state;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF p_resolution NOT IN ('confirmed_successful', 'confirmed_failed', 'still_unresolved') THEN
    RAISE EXCEPTION 'invalid_resolution';
  END IF;

  SELECT * INTO v_attempt FROM public.payment_attempts WHERE id = p_attempt_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'attempt_not_found'; END IF;
  IF v_attempt.state NOT IN ('pending', 'unknown') THEN
    RAISE EXCEPTION 'attempt_not_reconcilable';
  END IF;

  IF p_resolution = 'still_unresolved' THEN
    UPDATE public.payment_attempts SET
      reconciliation_notes = p_notes
    WHERE id = p_attempt_id
    RETURNING * INTO v_attempt;

    PERFORM public.log_audit_event(
      v_attempt.company_id, 'payment_attempt_reconciliation_note', 'payment_attempts', v_attempt.id,
      jsonb_build_object('notes_recorded', p_notes IS NOT NULL)
    );
    RETURN v_attempt;
  END IF;

  v_new_state := CASE WHEN p_resolution = 'confirmed_successful' THEN 'successful' ELSE 'failed' END;

  UPDATE public.payment_attempts SET
    state = v_new_state,
    reconciliation_state = 'reconciled',
    reconciled_by = auth.uid(),
    reconciled_at = now(),
    reconciliation_notes = p_notes,
    resolved_at = now(),
    failure_category = CASE WHEN v_new_state = 'failed' THEN 'manually_reconciled_failed' ELSE NULL END
  WHERE id = p_attempt_id
  RETURNING * INTO v_attempt;

  PERFORM public.log_audit_event(
    v_attempt.company_id, 'payment_attempt_manually_reconciled', 'payment_attempts', v_attempt.id,
    jsonb_build_object('resolution', p_resolution, 'new_state', v_new_state)
  );

  IF v_new_state = 'successful' THEN
    PERFORM public.finalize_successful_payment_attempt(v_attempt.id);
  END IF;

  RETURN v_attempt;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_reconcile_payment_attempt(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_reconcile_payment_attempt TO authenticated;

-- ---------------------------------------------------------------------------
-- Admin visibility — masked MSISDN, no secret ever stored so none to leak.
-- p_margin_anomaly_only (correction pass, section 1) lets a super admin
-- isolate successful transactions where the provider fee exceeded platform
-- commission — an operational/financial review queue, never conflated with
-- payment-state uncertainty (those are 'pending'/'unknown', a separate
-- filter already covered by p_state).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_list_payment_attempts_page(
  p_state TEXT[] DEFAULT NULL,
  p_reconciliation_state TEXT[] DEFAULT NULL,
  p_limit INT DEFAULT 50,
  p_offset INT DEFAULT 0,
  p_margin_anomaly_only BOOLEAN DEFAULT false
)
RETURNS TABLE (
  id UUID,
  company_id UUID,
  company_name TEXT,
  commerce_order_id UUID,
  order_number TEXT,
  payer_msisdn_masked TEXT,
  currency TEXT,
  gross_amount_cents BIGINT,
  provider_fee_cents BIGINT,
  provider_net_cents BIGINT,
  external_id TEXT,
  state public.payment_attempt_state,
  raw_provider_status TEXT,
  http_status INT,
  failure_category TEXT,
  reconciliation_state TEXT,
  margin_anomaly BOOLEAN,
  attempt_count INT,
  created_at TIMESTAMPTZ,
  requested_at TIMESTAMPTZ,
  resolved_at TIMESTAMPTZ,
  total_count BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  RETURN QUERY
  SELECT
    p.id, p.company_id, c.name, p.commerce_order_id, o.order_number,
    CASE WHEN length(p.payer_msisdn) > 4 THEN '***' || right(p.payer_msisdn, 4) ELSE '***' END,
    p.currency, p.gross_amount_cents, p.provider_fee_cents, p.provider_net_cents,
    p.external_id, p.state, p.raw_provider_status, p.http_status, p.failure_category,
    p.reconciliation_state, p.margin_anomaly, p.attempt_count, p.created_at, p.requested_at, p.resolved_at,
    COUNT(*) OVER ()::BIGINT
  FROM public.payment_attempts p
  LEFT JOIN public.companies c ON c.id = p.company_id
  LEFT JOIN public.commerce_orders o ON o.id = p.commerce_order_id
  WHERE (p_state IS NULL OR p.state::TEXT = ANY (p_state))
    AND (p_reconciliation_state IS NULL OR p.reconciliation_state = ANY (p_reconciliation_state))
    AND (NOT p_margin_anomaly_only OR p.margin_anomaly = true)
  ORDER BY p.created_at DESC
  LIMIT LEAST(GREATEST(p_limit, 1), 200)
  OFFSET GREATEST(p_offset, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_list_payment_attempts_page TO authenticated;

-- ---------------------------------------------------------------------------
-- Open the gate: submit_commerce_order now accepts 'mtn_momo' (still blocks
-- 'orange_money' — not implemented). Identical body otherwise to the Phase
-- F version (20260309210000_commerce_phase_f_production_readiness.sql).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_commerce_order(
  p_cart_id UUID,
  p_customer_name TEXT,
  p_delivery_address TEXT DEFAULT NULL,
  p_delivery_area_summary TEXT DEFAULT NULL,
  p_delivery_latitude DOUBLE PRECISION DEFAULT NULL,
  p_delivery_longitude DOUBLE PRECISION DEFAULT NULL,
  p_delivery_instructions TEXT DEFAULT NULL,
  p_payment_method TEXT DEFAULT 'cod'
)
RETURNS public.commerce_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_phone_confirmed TIMESTAMPTZ;
  v_auth_phone TEXT;
  v_cart public.carts;
  v_item RECORD;
  v_product public.products;
  v_stock public.product_stock;
  v_available NUMERIC;
  v_option_delta INT;
  v_option_snapshot JSONB;
  v_unit_price INT;
  v_line_total INT;
  v_subtotal INT := 0;
  v_order public.commerce_orders;
  v_payment_method public.commerce_payment_method;
  v_allow_cod BOOLEAN;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT phone, phone_confirmed_at INTO v_auth_phone, v_phone_confirmed
  FROM auth.users WHERE id = auth.uid();
  IF v_phone_confirmed IS NULL THEN
    RAISE EXCEPTION 'phone_not_verified';
  END IF;

  SELECT * INTO v_cart FROM public.carts WHERE id = p_cart_id AND customer_id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'cart_not_found';
  END IF;
  IF v_cart.status <> 'open' THEN
    RAISE EXCEPTION 'cart_not_open';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.cart_items WHERE cart_id = v_cart.id) THEN
    RAISE EXCEPTION 'cart_empty';
  END IF;
  IF NOT public.store_is_publicly_visible(v_cart.vendor_company_id) THEN
    RAISE EXCEPTION 'vendor_not_available';
  END IF;
  IF NOT public.can_use_feature(v_cart.vendor_company_id, 'commerce_enabled') THEN
    RAISE EXCEPTION 'commerce_not_enabled';
  END IF;

  IF p_payment_method NOT IN ('cod', 'mtn_momo', 'orange_money') THEN
    RAISE EXCEPTION 'invalid_payment_method';
  END IF;
  IF p_payment_method = 'orange_money' THEN
    RAISE EXCEPTION 'payment_method_not_available';
  END IF;
  v_payment_method := p_payment_method::public.commerce_payment_method;

  SELECT allow_cash_on_delivery INTO v_allow_cod
  FROM public.store_profiles WHERE company_id = v_cart.vendor_company_id;
  IF v_payment_method = 'cod' AND NOT COALESCE(v_allow_cod, false) THEN
    RAISE EXCEPTION 'cod_not_allowed';
  END IF;

  INSERT INTO public.commerce_orders (
    customer_id, vendor_company_id, cart_id, customer_name, customer_phone,
    delivery_address, delivery_area_summary, delivery_latitude, delivery_longitude, delivery_instructions,
    payment_method
  ) VALUES (
    auth.uid(), v_cart.vendor_company_id, v_cart.id,
    NULLIF(trim(p_customer_name), ''), public.normalize_phone_lr(v_auth_phone),
    p_delivery_address, p_delivery_area_summary, p_delivery_latitude, p_delivery_longitude, p_delivery_instructions,
    v_payment_method
  )
  RETURNING * INTO v_order;

  IF v_order.customer_name IS NULL THEN
    RAISE EXCEPTION 'customer_name_required';
  END IF;

  FOR v_item IN SELECT * FROM public.cart_items WHERE cart_id = v_cart.id LOOP
    SELECT * INTO v_product FROM public.products WHERE id = v_item.product_id;
    IF NOT FOUND OR v_product.status <> 'active' OR v_product.company_id <> v_cart.vendor_company_id THEN
      RAISE EXCEPTION 'product_not_available';
    END IF;

    PERFORM public.assert_valid_product_options(v_product.id, v_item.selected_options);

    v_unit_price := v_product.price_lrd_cents;
    v_option_snapshot := '[]'::JSONB;

    IF COALESCE(jsonb_array_length(v_item.selected_options), 0) > 0 THEN
      SELECT COALESCE(SUM(po.price_delta_lrd_cents), 0),
             COALESCE(jsonb_agg(jsonb_build_object('name', po.name, 'price_delta_lrd_cents', po.price_delta_lrd_cents)), '[]'::JSONB)
      INTO v_option_delta, v_option_snapshot
      FROM public.product_options po
      WHERE po.id IN (SELECT (jsonb_array_elements_text(v_item.selected_options))::UUID);

      v_unit_price := v_unit_price + COALESCE(v_option_delta, 0);
    END IF;

    v_line_total := v_unit_price * v_item.quantity;
    v_subtotal := v_subtotal + v_line_total;

    INSERT INTO public.commerce_order_items (
      order_id, product_id, product_name, unit_price_lrd_cents, quantity, selected_options, line_total_lrd_cents
    ) VALUES (
      v_order.id, v_product.id, v_product.name, v_unit_price, v_item.quantity, v_option_snapshot, v_line_total
    );

    IF v_product.tracks_inventory THEN
      SELECT * INTO v_stock FROM public.product_stock WHERE product_id = v_product.id FOR UPDATE;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'stock_not_configured';
      END IF;
      v_available := v_stock.quantity_on_hand - v_stock.quantity_reserved;
      IF v_available < v_item.quantity THEN
        RAISE EXCEPTION 'insufficient_stock';
      END IF;

      UPDATE public.product_stock SET
        quantity_reserved = quantity_reserved + v_item.quantity, updated_at = now()
      WHERE product_id = v_product.id;

      INSERT INTO public.product_stock_movements (
        product_id, company_id, quantity, movement_type, reference_type, reference_id, actor_user_id
      ) VALUES (
        v_product.id, v_cart.vendor_company_id, v_item.quantity, 'reservation', 'commerce_order', v_order.id, auth.uid()
      );
    END IF;
  END LOOP;

  UPDATE public.commerce_orders SET
    subtotal_lrd_cents = v_subtotal,
    total_lrd_cents = v_subtotal + delivery_fee_lrd_cents
  WHERE id = v_order.id
  RETURNING * INTO v_order;

  UPDATE public.carts SET status = 'converted', updated_at = now() WHERE id = v_cart.id;

  PERFORM public.notify_vendor_new_commerce_order(v_order);

  RETURN v_order;
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_commerce_order TO authenticated;

-- ---------------------------------------------------------------------------
-- accept_marketplace_offer — identical body to the WhatsApp Phase A version
-- (20260310000000_whatsapp_phase_a_foundation.sql, the current latest —
-- NOT the older Phase F body, to keep its dispatch_channel_notification
-- integration), plus two changes, both required by this correction pass:
--
--  1. Payment gate: for an mtn_momo commerce order, this — the CARRIER's
--     own human acceptance, a real dispatcher action — now requires
--     payment_status = 'paid' first. See migration header "PAYMENT TIMING"
--     for why this moved here from vendor acceptance. Additionally
--     (correction pass, section 2/3): for an already-paid order, the offer
--     being accepted must be EXACTLY the one frozen into the successful
--     payment_attempts row, at EXACTLY the frozen price — "carrier
--     acceptance after successful payment must consume that same locked
--     quote," not a live re-read that could in principle have drifted.
--  2. amount_to_collect_lrd_cents bug fix: for an mtn_momo order this MUST
--     be 0, not subtotal + delivery fee. The pre-existing formula computed
--     the same "collect on delivery" amount for EVERY commerce order
--     regardless of payment_method — harmless for COD (that IS what should
--     be collected) but for an MTN order that amount was already charged
--     electronically; leaving it non-zero would have told a rider to
--     collect cash a second time for an order the customer already paid
--     for. Found while tracing this exact code path for this correction,
--     not a pre-existing MTN bug shipped anywhere (MTN could not reach
--     this function at all before this migration).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.accept_marketplace_offer(
  p_offer_id UUID,
  p_provider_company_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_offer public.delivery_offers;
  v_req public.delivery_requests;
  v_delivery public.deliveries;
  v_merchant_name TEXT;
  v_fee RECORD;
  v_tx public.marketplace_transactions;
  v_commerce_order public.commerce_orders;
  v_amount_to_collect INT;
  v_locked_attempt public.payment_attempts;
BEGIN
  PERFORM public.assert_provider_marketplace(p_provider_company_id);
  IF NOT public.has_company_role(p_provider_company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[]) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT * INTO v_offer FROM public.delivery_offers
  WHERE id = p_offer_id AND provider_company_id = p_provider_company_id
  FOR UPDATE;

  IF NOT FOUND OR v_offer.status <> 'pending' THEN
    RAISE EXCEPTION 'invalid_offer';
  END IF;

  SELECT * INTO v_req FROM public.delivery_requests WHERE id = v_offer.delivery_request_id FOR UPDATE;
  IF v_req.status NOT IN ('open', 'offered') THEN
    RAISE EXCEPTION 'request_not_available';
  END IF;

  SELECT * INTO v_commerce_order FROM public.commerce_orders WHERE delivery_request_id = v_req.id FOR UPDATE;
  IF v_commerce_order.id IS NOT NULL AND v_offer.selected_by_customer_at IS NULL THEN
    RAISE EXCEPTION 'offer_not_selected_by_customer';
  END IF;

  -- (1) Payment gate — see header comment above.
  IF v_commerce_order.id IS NOT NULL
     AND v_commerce_order.payment_method = 'mtn_momo'
     AND v_commerce_order.payment_status <> 'paid' THEN
    RAISE EXCEPTION 'payment_not_confirmed';
  END IF;

  -- Frozen-quote consistency check (correction pass, section 2/3) — for an
  -- already-paid mtn_momo order, the offer/price being accepted must be
  -- exactly what the successful payment_attempts row froze at charge time.
  -- select_commerce_delivery_offer's financial lock already prevents the
  -- selection from changing after payment, so this should never fire in
  -- practice — it exists as a defensive, should-never-trip assertion, not
  -- the primary control.
  IF v_commerce_order.id IS NOT NULL
     AND v_commerce_order.payment_method = 'mtn_momo'
     AND v_commerce_order.payment_status = 'paid' THEN
    SELECT * INTO v_locked_attempt FROM public.payment_attempts
    WHERE commerce_order_id = v_commerce_order.id AND state = 'successful'
    ORDER BY resolved_at DESC NULLS LAST, created_at DESC
    LIMIT 1;

    IF v_locked_attempt.id IS NULL
       OR v_locked_attempt.selected_offer_id IS DISTINCT FROM v_offer.id
       OR v_locked_attempt.delivery_fee_snapshot_lrd_cents <> v_offer.quoted_amount_lrd_cents THEN
      RAISE EXCEPTION 'offer_price_mismatch_with_payment';
    END IF;
  END IF;

  UPDATE public.delivery_offers SET status = 'accepted', accepted_at = now() WHERE id = p_offer_id;

  UPDATE public.delivery_offers SET status = 'expired'
  WHERE delivery_request_id = v_req.id AND id <> p_offer_id AND status = 'pending';

  UPDATE public.delivery_requests SET
    status = 'accepted',
    selected_provider_id = p_provider_company_id,
    quoted_amount_lrd_cents = v_offer.quoted_amount_lrd_cents,
    accepted_at = now()
  WHERE id = v_req.id
  RETURNING * INTO v_req;

  SELECT name INTO v_merchant_name FROM public.companies WHERE id = v_req.merchant_company_id;

  -- (2) amount_to_collect fix — see header comment above.
  v_amount_to_collect := CASE
    WHEN v_commerce_order.id IS NOT NULL AND v_commerce_order.payment_method = 'mtn_momo' THEN 0
    WHEN v_commerce_order.id IS NOT NULL THEN v_commerce_order.subtotal_lrd_cents + v_offer.quoted_amount_lrd_cents
    ELSE v_req.cod_amount_lrd_cents
  END;

  INSERT INTO public.deliveries (
    company_id, merchant_company_id, delivery_request_id,
    tracking_code, pickup_business_name, pickup_address,
    customer_id, customer_name, customer_phone, destination_address,
    package_description, amount_to_collect_lrd_cents, delivery_fee_lrd_cents,
    delivery_zone_id, status, created_by, commerce_order_id
  ) VALUES (
    p_provider_company_id, v_req.merchant_company_id, v_req.id,
    public.generate_tracking_code(),
    COALESCE(v_merchant_name, 'Merchant pickup'),
    v_req.pickup_address,
    v_req.customer_id,
    COALESCE(v_req.customer_name, 'Customer'),
    COALESCE(v_req.customer_phone, ''),
    v_req.destination_address,
    v_req.package_description,
    v_amount_to_collect,
    v_offer.quoted_amount_lrd_cents,
    v_req.zone_id,
    'pending',
    auth.uid(),
    v_commerce_order.id
  )
  RETURNING * INTO v_delivery;

  UPDATE public.delivery_requests SET status = 'converted', converted_delivery_id = v_delivery.id WHERE id = v_req.id;

  IF v_commerce_order.id IS NOT NULL THEN
    UPDATE public.commerce_orders SET
      delivery_id = v_delivery.id,
      delivery_fee_lrd_cents = v_offer.quoted_amount_lrd_cents,
      total_lrd_cents = subtotal_lrd_cents + v_offer.quoted_amount_lrd_cents,
      updated_at = now()
    WHERE id = v_commerce_order.id
    RETURNING * INTO v_commerce_order;

    IF v_commerce_order.customer_phone IS NOT NULL AND v_commerce_order.customer_phone <> '' THEN
      PERFORM public.dispatch_channel_notification(
        p_provider_company_id, v_commerce_order.customer_phone, 'carrier_accepted_customer',
        format(E'A carrier has accepted your DeliveryOS order #%s. You will be notified when it is picked up.', v_commerce_order.order_number),
        jsonb_build_array(v_commerce_order.order_number),
        v_delivery.id, v_commerce_order.id,
        'carrier_accepted_customer:' || v_commerce_order.id::TEXT
      );
    END IF;
  END IF;

  SELECT * INTO v_fee FROM public.compute_marketplace_fee_split(
    v_offer.quoted_amount_lrd_cents, v_req.merchant_company_id, p_provider_company_id
  );

  INSERT INTO public.marketplace_transactions (
    delivery_request_id, merchant_company_id, provider_company_id, delivery_id,
    gross_amount_lrd_cents, platform_fee_lrd_cents, provider_amount_lrd_cents, status
  ) VALUES (
    v_req.id, v_req.merchant_company_id, p_provider_company_id, v_delivery.id,
    v_offer.quoted_amount_lrd_cents, v_fee.platform_fee_lrd_cents, v_fee.provider_amount_lrd_cents, 'pending'
  )
  RETURNING * INTO v_tx;

  INSERT INTO public.marketplace_ledger_entries (company_id, account_type, marketplace_transaction_id, amount_lrd_cents, description)
  VALUES
    (v_req.merchant_company_id, 'merchant_payable', v_tx.id, v_offer.quoted_amount_lrd_cents, 'Marketplace delivery accepted'),
    (p_provider_company_id, 'provider_receivable', v_tx.id, v_fee.provider_amount_lrd_cents, 'Provider earnings'),
    (NULL, 'platform_revenue', v_tx.id, v_fee.platform_fee_lrd_cents, 'Platform fee');

  PERFORM public.enqueue_webhook_event(v_req.merchant_company_id, 'delivery_request.accepted', v_req.id,
    jsonb_build_object('request', to_jsonb(v_req), 'delivery_id', v_delivery.id));
  PERFORM public.enqueue_webhook_event(p_provider_company_id, 'marketplace_job.accepted', v_req.id,
    jsonb_build_object('delivery_id', v_delivery.id));
  PERFORM public.enqueue_webhook_event(v_req.merchant_company_id, 'marketplace.offer.accepted', v_offer.id, to_jsonb(v_offer));

  RETURN jsonb_build_object('delivery_request', to_jsonb(v_req), 'delivery', to_jsonb(v_delivery), 'transaction', to_jsonb(v_tx));
END;
$$;

GRANT EXECUTE ON FUNCTION public.accept_marketplace_offer TO authenticated;

-- ---------------------------------------------------------------------------
-- Wire the reconciliation safety net into the EXISTING maintenance RPC
-- (jobs-scheduler already calls this every 5 minutes) rather than adding a
-- new call site or a new cron system — identical body to the Phase 8/
-- seven-day-trial version (20260308120000_seven_day_free_trial.sql) plus
-- one additional line and one additional field in the returned summary.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.run_scheduled_maintenance_jobs()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub_past_due INT := 0;
  v_trials_expired INT := 0;
  v_inv_overdue INT := 0;
  v_req_expired INT := 0;
  v_offers_expired INT := 0;
  v_gps_purged BIGINT := 0;
  v_inv_expired INT := 0;
  v_payment_attempts_swept INT := 0;
BEGIN
  v_trials_expired := public.expire_elapsed_company_trials(NULL);

  UPDATE public.company_subscriptions cs SET
    status = 'past_due',
    updated_at = now()
  WHERE cs.status = 'active'
    AND cs.current_period_end < now()
    AND NOT EXISTS (
      SELECT 1 FROM public.company_subscriptions cs2
      WHERE cs2.company_id = cs.company_id AND cs2.status IN ('trialing', 'active') AND cs2.id <> cs.id
    );
  GET DIAGNOSTICS v_sub_past_due = ROW_COUNT;

  UPDATE public.invoices SET status = 'overdue', updated_at = now()
  WHERE status = 'issued' AND due_at < now();
  GET DIAGNOSTICS v_inv_overdue = ROW_COUNT;

  SELECT COUNT(*)::INT INTO v_inv_expired
  FROM public.company_invitations
  WHERE expires_at < now() AND accepted_at IS NULL AND revoked_at IS NULL;

  UPDATE public.delivery_requests SET status = 'expired', updated_at = now()
  WHERE status IN ('open', 'offered') AND expires_at IS NOT NULL AND expires_at < now();
  GET DIAGNOSTICS v_req_expired = ROW_COUNT;

  -- Correction pass, section 2: an offer tied to an unresolved OR
  -- successful MTN payment attempt is financially locked (see
  -- select_commerce_delivery_offer) and must never be expired out from
  -- under that payment, no matter how old expires_at is. Only a
  -- definitively 'failed' attempt (or no attempt at all) leaves an offer
  -- eligible for the routine expiry sweep.
  UPDATE public.delivery_offers SET status = 'expired'
  WHERE status = 'pending' AND expires_at IS NOT NULL AND expires_at < now()
    AND id NOT IN (
      SELECT selected_offer_id FROM public.payment_attempts
      WHERE selected_offer_id IS NOT NULL AND state <> 'failed'
    );
  GET DIAGNOSTICS v_offers_expired = ROW_COUNT;

  v_gps_purged := public.purge_old_rider_location_samples(interval '48 hours');

  -- Payment reconciliation safety net (Commerce Phase E2) — moves attempts
  -- stuck in 'requesting' to 'unknown' after a generous timeout. Never
  -- re-contacts the provider; see sweep_stuck_payment_attempts.
  v_payment_attempts_swept := public.sweep_stuck_payment_attempts();

  RETURN jsonb_build_object(
    'trials_expired', v_trials_expired,
    'subscriptions_marked_past_due', v_sub_past_due,
    'invoices_marked_overdue', v_inv_overdue,
    'delivery_requests_expired', v_req_expired,
    'delivery_offers_expired', v_offers_expired,
    'gps_samples_purged', v_gps_purged,
    'invitations_expired_checked', v_inv_expired,
    'payment_attempts_swept_to_unknown', v_payment_attempts_swept
  );
END;
$$;
