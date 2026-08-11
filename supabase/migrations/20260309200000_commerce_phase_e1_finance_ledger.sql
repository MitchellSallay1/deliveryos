-- DeliveryOS Commerce — Phase E1: Finance, Ledger & Settlement Foundation.
--
-- Makes Commerce financially correct and auditable before MTN MoMo/Orange
-- Money touch the system. No external payment integration here — this is
-- the accounting substrate a future payment-verification event will post
-- through, unchanged.
--
-- ===========================================================================
-- Financial architecture audit — what already exists, what is reused, what
-- is new (see the Phase E1 report for the full narrative)
-- ===========================================================================
--   - marketplace_transactions / marketplace_ledger_entries / marketplace_
--     settlements (Phase 7) already exist, but are scoped EXCLUSIVELY to the
--     B2B/Commerce CARRIER delivery-fee commission split, recognized at
--     JOB ACCEPTANCE time (accept_marketplace_offer), not at cash
--     collection. marketplace_ledger_entries has no signed debit/credit
--     column and no balance invariant — it is a flat, append-only
--     three-row annotation per transaction, not a real double-entry
--     ledger. It has never modeled product-sale economics and cannot
--     safely be extended to do so without conflating two different
--     economic events (delivery-fee acceptance vs. merchandise-sale
--     collection) into one table shape it wasn't designed for.
--   - compute_marketplace_fee_split already reads a real, Super-Admin-
--     configurable fee-rule table (marketplace_fee_rules) with merchant-
--     specific > provider-specific > platform-default precedence — this
--     exact pattern is reused (not reinvented) below for the vendor side
--     via commerce_fee_rules and a new compute_commerce_vendor_fee_split.
--   - commerce_fee_rules (Phase A) already exists with the right shape
--     (fee_model, fixed/percentage, is_platform_default, a single-company
--     override via applies_to_vendor_company_id) and an admin RPC
--     (admin_upsert_commerce_fee_rule) — but ZERO consumers: no RPC ever
--     reads it, no frontend page ever writes it. It is used for real
--     starting with this migration; no schema change to it was needed.
--   - The CARRIER side of Commerce economics is therefore ALREADY
--     independently configurable today via the pre-existing
--     marketplace_fee_rules (applies_to_provider_company_id) — Commerce
--     does not need its own carrier-fee config table. What's missing is
--     only the VENDOR (merchandise) side, which commerce_fee_rules
--     already covers. No "smallest schema extension" was needed here: the
--     existing two-table split (commerce_fee_rules for vendor,
--     marketplace_fee_rules for carrier) already expresses vendor and
--     carrier fees fully independently.
--   - Subscription billing (subscriptions/company_subscriptions/invoices/
--     subscription_billing_payments) has NO ledger of any kind — status/
--     period tracking plus flat logs. There is no existing double-entry
--     ledger anywhere in this codebase to extend or to force-merge with.
--     Commerce's ledger below is therefore a green-field build, kept
--     deliberately SEPARATE from subscription billing: they are different
--     bounded contexts (platform<->tenant subscription fees vs.
--     customer<->vendor<->carrier<->platform order economics), the same
--     reasoning Phase B.5 already applied when it created
--     commerce_payment_method instead of reusing billing_payment_method.
--   - mark_commerce_order_paid (Phase A, REVOKE ALL FROM PUBLIC) is the
--     exact seam where "payment received" already happens for a Commerce
--     order — today it only mutates payment_status and finalizes
--     inventory. This migration adds a sibling, equally internal-only RPC
--     (recognize_commerce_order_financials) called from the SAME trigger
--     right after it, rather than folding ledger-posting into
--     mark_commerce_order_paid itself — separating "did the customer pay"
--     from "how is that money allocated" is exactly the distinction
--     requirement 6 asks to keep explicit, and it keeps
--     mark_commerce_order_paid's existing, already-tested behavior
--     untouched.
--   - This new recognition RPC is deliberately payment-method-agnostic:
--     it only needs commerce_orders/deliveries/marketplace_transactions
--     state, never anything COD-specific. Phase E2's MoMo integration can
--     call the exact same function once its own webhook independently
--     verifies payment and calls mark_commerce_order_paid — it will never
--     need to understand or duplicate the accounting rules below.
--
-- ===========================================================================
-- Ledger model
-- ===========================================================================
-- A journal/entry model: commerce_financial_events is the journal header
-- (one per economic event — a COD collection, a reversal, a future manual
-- adjustment), commerce_ledger_entries are its balanced entry lines. Every
-- event's entries must sum to zero (SUM of credits = SUM of debits) —
-- enforced by a DEFERRED CONSTRAINT TRIGGER, not merely application
-- discipline, so no financial event can ever commit unbalanced regardless
-- of which RPC posted it. Four account types model where money is
-- economically owed once COD cash is collected:
--   cod_clearing   (debit)  — the FULL cash collected by the carrier from
--                             the customer (subtotal + delivery fee); a
--                             clearing/custodial account, not owned by any
--                             party, since real remittance from carrier to
--                             platform to vendor is an operational/payout
--                             concern for a later phase, not core
--                             double-entry accounting.
--   vendor_payable  (credit) — what the platform owes the vendor, net of
--                              the vendor's platform commission.
--   carrier_payable (credit) — what the platform owes the carrier, net of
--                              the carrier's platform commission. Sourced
--                              from the ALREADY-frozen marketplace_
--                              transactions row created at carrier-
--                              acceptance time (Phase D), not recomputed —
--                              a delivery has exactly one fee-split
--                              decision, made once, at acceptance.
--   platform_revenue (credit) — vendor commission + carrier commission.
-- cod_clearing (debit) always equals vendor_payable + carrier_payable +
-- platform_revenue (credits) = subtotal + delivery fee, by construction.

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
CREATE TYPE public.commerce_ledger_account_type AS ENUM (
  'cod_clearing', 'vendor_payable', 'carrier_payable', 'platform_revenue'
);
CREATE TYPE public.commerce_ledger_direction AS ENUM ('debit', 'credit');
CREATE TYPE public.commerce_financial_event_type AS ENUM (
  'cod_collected', 'reversal', 'adjustment'
);
CREATE TYPE public.commerce_settlement_status AS ENUM (
  'pending', 'processing', 'settled', 'failed', 'reversed'
);
CREATE TYPE public.commerce_settlement_payee_type AS ENUM ('vendor', 'carrier');

-- ---------------------------------------------------------------------------
-- Journal header
-- ---------------------------------------------------------------------------
CREATE TABLE public.commerce_financial_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type public.commerce_financial_event_type NOT NULL,
  commerce_order_id UUID NOT NULL REFERENCES public.commerce_orders (id) ON DELETE RESTRICT,
  delivery_id UUID REFERENCES public.deliveries (id) ON DELETE SET NULL,
  payment_id UUID REFERENCES public.payments (id) ON DELETE SET NULL,
  reverses_event_id UUID REFERENCES public.commerce_financial_events (id) ON DELETE RESTRICT,
  idempotency_key TEXT NOT NULL UNIQUE,
  -- Frozen inputs to the computation that produced this event's entries —
  -- fee rule ids/rates, gross/commission/net breakdown, source
  -- marketplace_transaction id — so historical economics remain provably
  -- reconstructable even if commerce_fee_rules/marketplace_fee_rules
  -- change tomorrow.
  snapshot JSONB NOT NULL DEFAULT '{}'::JSONB,
  reason TEXT,
  created_by UUID REFERENCES auth.users (id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_commerce_financial_events_order ON public.commerce_financial_events (commerce_order_id, created_at DESC);
CREATE INDEX idx_commerce_financial_events_delivery ON public.commerce_financial_events (delivery_id) WHERE delivery_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Settlements (created before ledger entries so entries can reference one)
-- ---------------------------------------------------------------------------
CREATE TABLE public.commerce_settlements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  payee_type public.commerce_settlement_payee_type NOT NULL,
  payee_company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE RESTRICT,
  status public.commerce_settlement_status NOT NULL DEFAULT 'pending',
  total_amount_lrd_cents INT NOT NULL DEFAULT 0 CHECK (total_amount_lrd_cents >= 0),
  currency TEXT NOT NULL DEFAULT 'LRD',
  external_reference TEXT,
  notes TEXT,
  created_by UUID REFERENCES auth.users (id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  settled_by UUID REFERENCES auth.users (id) ON DELETE SET NULL,
  settled_at TIMESTAMPTZ,
  -- Distinct actor/timestamp per terminal transition (not just a status
  -- flip) so "who failed/reversed this and when" is a real, queryable
  -- fact, not something inferred from updated_at.
  failed_by UUID REFERENCES auth.users (id) ON DELETE SET NULL,
  failed_at TIMESTAMPTZ,
  reversed_by UUID REFERENCES auth.users (id) ON DELETE SET NULL,
  reversed_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_commerce_settlements_payee ON public.commerce_settlements (payee_type, payee_company_id, status, created_at DESC);

CREATE TRIGGER commerce_settlements_updated_at
  BEFORE UPDATE ON public.commerce_settlements
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Ledger entry lines
-- ---------------------------------------------------------------------------
CREATE TABLE public.commerce_ledger_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  financial_event_id UUID NOT NULL REFERENCES public.commerce_financial_events (id) ON DELETE RESTRICT,
  account_type public.commerce_ledger_account_type NOT NULL,
  direction public.commerce_ledger_direction NOT NULL,
  -- The owning tenant company for vendor_payable/carrier_payable/
  -- cod_clearing rows; NULL for platform_revenue (platform-level, no
  -- tenant owner), mirroring marketplace_ledger_entries' existing
  -- (company_id IS NULL <=> platform) convention.
  company_id UUID REFERENCES public.companies (id) ON DELETE SET NULL,
  amount_lrd_cents INT NOT NULL CHECK (amount_lrd_cents > 0),
  currency TEXT NOT NULL DEFAULT 'LRD',
  description TEXT,
  -- Set once a payable entry is claimed by a settlement; NULL again if
  -- that settlement fails, freeing it for a future settlement attempt.
  -- commerce_settlement_items is the durable historical record of what a
  -- given settlement attempt included — this column is only a fast
  -- "currently claimed" pointer for the unsettled-balance queries.
  settlement_id UUID REFERENCES public.commerce_settlements (id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_commerce_ledger_entries_event ON public.commerce_ledger_entries (financial_event_id);
CREATE INDEX idx_commerce_ledger_entries_company_account
  ON public.commerce_ledger_entries (company_id, account_type, created_at DESC);
CREATE INDEX idx_commerce_ledger_entries_unsettled
  ON public.commerce_ledger_entries (company_id, account_type)
  WHERE settlement_id IS NULL AND account_type IN ('vendor_payable', 'carrier_payable');

-- A ledger entry may legitimately appear in MORE THAN ONE row here over its
-- lifetime: if the settlement that first claimed it later fails or is
-- reversed, the entry is freed (commerce_ledger_entries.settlement_id set
-- back to NULL) and becomes claimable by a new settlement attempt, which
-- inserts its own row. The uniqueness that actually matters is "claimed by
-- at most one settlement AT A TIME" — that is enforced by the single-valued
-- settlement_id column on commerce_ledger_entries, not by this table. The
-- UNIQUE (settlement_id, ledger_entry_id) below only guards against a single
-- settlement claiming the same entry twice; it deliberately does NOT
-- constrain ledger_entry_id globally, so history across failed/reversed
-- attempts is never blocked from being re-claimed.
CREATE TABLE public.commerce_settlement_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  settlement_id UUID NOT NULL REFERENCES public.commerce_settlements (id) ON DELETE RESTRICT,
  ledger_entry_id UUID NOT NULL REFERENCES public.commerce_ledger_entries (id) ON DELETE RESTRICT,
  amount_lrd_cents INT NOT NULL CHECK (amount_lrd_cents > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (settlement_id, ledger_entry_id)
);

CREATE INDEX idx_commerce_settlement_items_settlement ON public.commerce_settlement_items (settlement_id);

-- ---------------------------------------------------------------------------
-- Balance invariant: every financial event's entries must net to zero
-- (debits = credits). A real DB-level guarantee, not application
-- discipline — checked once per inserted row but deferred to transaction
-- commit, so all of an event's rows are present by the time it runs.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_commerce_ledger_event_balance()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_debits INT;
  v_credits INT;
BEGIN
  SELECT
    COALESCE(SUM(amount_lrd_cents) FILTER (WHERE direction = 'debit'), 0),
    COALESCE(SUM(amount_lrd_cents) FILTER (WHERE direction = 'credit'), 0)
  INTO v_debits, v_credits
  FROM public.commerce_ledger_entries
  WHERE financial_event_id = NEW.financial_event_id;

  IF v_debits <> v_credits THEN
    RAISE EXCEPTION 'unbalanced_ledger_event: event % debits=% credits=%', NEW.financial_event_id, v_debits, v_credits;
  END IF;

  RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_check_commerce_ledger_balance
  AFTER INSERT ON public.commerce_ledger_entries
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.check_commerce_ledger_event_balance();

-- ---------------------------------------------------------------------------
-- RLS: SELECT-only for tenants/customers, all writes via SECURITY DEFINER
-- RPCs below (same idiom as every other Commerce/marketplace table).
-- ---------------------------------------------------------------------------
ALTER TABLE public.commerce_financial_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commerce_ledger_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commerce_settlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commerce_settlement_items ENABLE ROW LEVEL SECURITY;

-- Financial events are visible to super admin and to the order's own
-- vendor (via commerce_orders) — not to the customer directly (a customer
-- already sees payment_status/total on their own order; the internal fee
-- split is a tenant/platform concern) and not to the carrier directly
-- (carrier visibility is scoped through ledger_entries.company_id below,
-- which is simpler to authorize than joining back through delivery_id).
CREATE POLICY commerce_financial_events_select ON public.commerce_financial_events
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR EXISTS (
      SELECT 1 FROM public.commerce_orders o
      WHERE o.id = commerce_financial_events.commerce_order_id
        AND o.vendor_company_id IN (SELECT public.user_company_ids())
    )
  );

CREATE POLICY commerce_ledger_entries_select ON public.commerce_ledger_entries
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR (company_id IS NOT NULL AND company_id IN (SELECT public.user_company_ids()))
  );

CREATE POLICY commerce_settlements_select ON public.commerce_settlements
  FOR SELECT TO authenticated
  USING (public.is_super_admin() OR payee_company_id IN (SELECT public.user_company_ids()));

CREATE POLICY commerce_settlement_items_select ON public.commerce_settlement_items
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR EXISTS (
      SELECT 1 FROM public.commerce_settlements s
      WHERE s.id = commerce_settlement_items.settlement_id
        AND s.payee_company_id IN (SELECT public.user_company_ids())
    )
  );

-- No INSERT/UPDATE/DELETE policy on any of the four tables above — every
-- write happens inside a SECURITY DEFINER RPC below, which bypasses RLS
-- internally as the function owner. No client role, including a company
-- owner, can mutate a ledger entry, alter a frozen event, or write a
-- settlement row directly.

-- ---------------------------------------------------------------------------
-- Vendor-side fee split — mirrors compute_marketplace_fee_split exactly,
-- reads commerce_fee_rules with vendor-specific > platform-default
-- precedence. Never hardcoded.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.compute_commerce_vendor_fee_split(
  p_gross_lrd_cents INT,
  p_vendor_company_id UUID
)
RETURNS TABLE (platform_fee_lrd_cents INT, vendor_amount_lrd_cents INT, fee_rule_id UUID)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rule public.commerce_fee_rules;
  v_gross INT := GREATEST(COALESCE(p_gross_lrd_cents, 0), 0);
  v_fee INT := 0;
BEGIN
  SELECT * INTO v_rule
  FROM public.commerce_fee_rules r
  WHERE r.is_active = true
    AND (r.applies_to_vendor_company_id = p_vendor_company_id OR r.is_platform_default = true)
  ORDER BY (r.applies_to_vendor_company_id IS NOT NULL)::INT DESC, r.is_platform_default DESC
  LIMIT 1;

  IF NOT FOUND THEN
    platform_fee_lrd_cents := 0;
    vendor_amount_lrd_cents := v_gross;
    fee_rule_id := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  v_fee := CASE v_rule.fee_model
    WHEN 'fixed' THEN v_rule.fixed_fee_lrd_cents
    WHEN 'percentage' THEN (v_gross * v_rule.percentage_bps / 10000)::INT
    WHEN 'subscription_only' THEN 0
    WHEN 'zero_commission' THEN 0
    ELSE 0
  END;

  v_fee := LEAST(GREATEST(v_fee, 0), v_gross);
  platform_fee_lrd_cents := v_fee;
  vendor_amount_lrd_cents := v_gross - v_fee;
  fee_rule_id := v_rule.id;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.compute_commerce_vendor_fee_split(INT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.compute_commerce_vendor_fee_split(INT, UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- The recognition seam: posts one balanced financial event the moment a
-- Commerce order's payment is genuinely confirmed. Internal-only (REVOKE
-- ALL FROM PUBLIC, no GRANT) — called from trg_sync_commerce_order_
-- payment_from_cod today, and intended to be the exact same call site a
-- future MoMo webhook handler uses once it independently verifies payment
-- and calls mark_commerce_order_paid; this function never needs to know
-- or care which payment method triggered it. Idempotent via a unique
-- idempotency_key — calling it twice for the same order is a safe no-op
-- on the second call.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.recognize_commerce_order_financials(p_order_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.commerce_orders;
  v_key TEXT := 'cod_collected:' || p_order_id::TEXT;
  v_existing_event_id UUID;
  v_vendor_split RECORD;
  v_carrier_gross INT := 0;
  v_carrier_fee INT := 0;
  v_carrier_amount INT := 0;
  v_carrier_tx public.marketplace_transactions;
  v_event public.commerce_financial_events;
  v_total_collected INT;
BEGIN
  SELECT id INTO v_existing_event_id
  FROM public.commerce_financial_events
  WHERE idempotency_key = v_key;
  IF FOUND THEN
    RETURN jsonb_build_object('event_id', v_existing_event_id, 'already_recognized', true);
  END IF;

  SELECT * INTO v_order FROM public.commerce_orders WHERE id = p_order_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'order_not_found'; END IF;

  SELECT * INTO v_vendor_split
  FROM public.compute_commerce_vendor_fee_split(v_order.subtotal_lrd_cents, v_order.vendor_company_id);

  -- Carrier leg: reuse the split ALREADY frozen at carrier-acceptance time
  -- (Phase D) rather than recomputing it — a delivery's fee split is
  -- decided once, when the carrier accepts, and must not silently change
  -- here if marketplace_fee_rules has since been edited.
  IF v_order.delivery_id IS NOT NULL THEN
    SELECT mt.* INTO v_carrier_tx
    FROM public.deliveries d
    JOIN public.marketplace_transactions mt ON mt.delivery_request_id = d.delivery_request_id
    WHERE d.id = v_order.delivery_id;

    IF v_carrier_tx.id IS NOT NULL THEN
      v_carrier_gross := v_carrier_tx.gross_amount_lrd_cents;
      v_carrier_fee := v_carrier_tx.platform_fee_lrd_cents;
      v_carrier_amount := v_carrier_tx.provider_amount_lrd_cents;
    END IF;
  END IF;

  v_total_collected := v_order.subtotal_lrd_cents + v_carrier_gross;

  INSERT INTO public.commerce_financial_events (
    event_type, commerce_order_id, delivery_id, payment_id, idempotency_key, snapshot, created_by
  ) VALUES (
    'cod_collected', v_order.id, v_order.delivery_id,
    (SELECT id FROM public.payments WHERE delivery_id = v_order.delivery_id),
    v_key,
    jsonb_build_object(
      'vendor_gross_lrd_cents', v_order.subtotal_lrd_cents,
      'vendor_fee_rule_id', v_vendor_split.fee_rule_id,
      'vendor_platform_fee_lrd_cents', v_vendor_split.platform_fee_lrd_cents,
      'vendor_net_lrd_cents', v_vendor_split.vendor_amount_lrd_cents,
      'carrier_gross_lrd_cents', v_carrier_gross,
      'carrier_platform_fee_lrd_cents', v_carrier_fee,
      'carrier_net_lrd_cents', v_carrier_amount,
      'carrier_marketplace_transaction_id', v_carrier_tx.id,
      'total_collected_lrd_cents', v_total_collected
    ),
    auth.uid()
  )
  RETURNING * INTO v_event;

  INSERT INTO public.commerce_ledger_entries (financial_event_id, account_type, direction, company_id, amount_lrd_cents, description)
  VALUES (
    v_event.id, 'cod_clearing', 'debit',
    (SELECT company_id FROM public.deliveries WHERE id = v_order.delivery_id),
    v_total_collected, 'COD cash collected for order ' || v_order.order_number
  );

  IF v_vendor_split.vendor_amount_lrd_cents > 0 THEN
    INSERT INTO public.commerce_ledger_entries (financial_event_id, account_type, direction, company_id, amount_lrd_cents, description)
    VALUES (v_event.id, 'vendor_payable', 'credit', v_order.vendor_company_id, v_vendor_split.vendor_amount_lrd_cents, 'Vendor payable for order ' || v_order.order_number);
  END IF;

  IF v_carrier_amount > 0 THEN
    INSERT INTO public.commerce_ledger_entries (financial_event_id, account_type, direction, company_id, amount_lrd_cents, description)
    VALUES (v_event.id, 'carrier_payable', 'credit', (SELECT company_id FROM public.deliveries WHERE id = v_order.delivery_id), v_carrier_amount, 'Carrier payable for order ' || v_order.order_number);
  END IF;

  IF (v_vendor_split.platform_fee_lrd_cents + v_carrier_fee) > 0 THEN
    INSERT INTO public.commerce_ledger_entries (financial_event_id, account_type, direction, company_id, amount_lrd_cents, description)
    VALUES (v_event.id, 'platform_revenue', 'credit', NULL, v_vendor_split.platform_fee_lrd_cents + v_carrier_fee, 'Platform commission for order ' || v_order.order_number);
  END IF;

  RETURN jsonb_build_object('event_id', v_event.id, 'already_recognized', false, 'snapshot', v_event.snapshot);
END;
$$;

REVOKE ALL ON FUNCTION public.recognize_commerce_order_financials(UUID) FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- Reversal primitive: mirrors the original event's entries with debit/
-- credit swapped, net economic effect zero. Internal-only. Covers "vendor
-- rejects an already-paid order", "delivery fails after payment",
-- "settlement recorded incorrectly upstream", and gives Phase E2 a ready
-- seam for a future verified-refund event — never a fake MTN/Orange
-- refund API, purely the ledger-side primitive.
-- ---------------------------------------------------------------------------
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
  WHERE commerce_order_id = p_order_id AND event_type = 'cod_collected'
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
-- Wire the recognition seam into the existing COD chain. Same trigger
-- Phase D already fixed to fire on INSERT OR UPDATE; this adds exactly one
-- more internal call, guarded by the identical condition already used to
-- call mark_commerce_order_paid, so it fires at precisely the same moment
-- and only once (idempotency_key makes a second accidental call inert
-- regardless).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_sync_commerce_order_payment_from_cod()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_commerce_order_id UUID;
  v_order public.commerce_orders;
BEGIN
  IF NEW.status = 'collected' AND (OLD.status IS DISTINCT FROM NEW.status) THEN
    SELECT commerce_order_id INTO v_commerce_order_id
    FROM public.deliveries WHERE id = NEW.delivery_id;

    IF v_commerce_order_id IS NOT NULL THEN
      SELECT * INTO v_order FROM public.commerce_orders WHERE id = v_commerce_order_id;
      IF v_order.id IS NOT NULL
         AND v_order.payment_method = 'cod'
         AND v_order.payment_status = 'pending_payment' THEN
        PERFORM public.mark_commerce_order_paid(v_order.id);
        PERFORM public.recognize_commerce_order_financials(v_order.id);
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- Wire the reversal primitive into the two existing "was this order
-- already paid?" cancellation paths. Both branches are currently dormant
-- for COD (both require fulfillment_status = 'awaiting_vendor', which a
-- COD order can never be in once payment_status = 'paid', since COD is
-- only ever marked paid at delivery — far past awaiting_vendor). They
-- exist for the future: once MoMo pre-payment lands, an order can be
-- 'paid' while still 'awaiting_vendor', and these will correctly reverse
-- the recognized financials the moment that becomes reachable — no future
-- rewrite of these functions required.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vendor_reject_commerce_order(p_order_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS public.commerce_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.commerce_orders;
  v_item RECORD;
  v_was_paid BOOLEAN;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT * INTO v_order FROM public.commerce_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'order_not_found'; END IF;

  PERFORM public.assert_vendor_order_actor(v_order.vendor_company_id);

  IF v_order.fulfillment_status <> 'awaiting_vendor' THEN
    RAISE EXCEPTION 'invalid_fulfillment_state';
  END IF;

  v_was_paid := (v_order.payment_status = 'paid');

  FOR v_item IN
    SELECT oi.product_id, oi.quantity
    FROM public.commerce_order_items oi
    JOIN public.products p ON p.id = oi.product_id
    WHERE oi.order_id = v_order.id AND p.tracks_inventory = true
  LOOP
    UPDATE public.product_stock SET
      quantity_reserved = GREATEST(quantity_reserved - v_item.quantity, 0), updated_at = now()
    WHERE product_id = v_item.product_id;

    INSERT INTO public.product_stock_movements (
      product_id, company_id, quantity, movement_type, reference_type, reference_id, actor_user_id, notes
    ) VALUES (
      v_item.product_id, v_order.vendor_company_id, v_item.quantity, 'release', 'commerce_order', v_order.id, auth.uid(), 'vendor_rejected'
    );
  END LOOP;

  UPDATE public.commerce_orders SET
    fulfillment_status = 'vendor_rejected',
    payment_status = CASE WHEN payment_status = 'paid' THEN 'refund_pending' ELSE payment_status END,
    cancelled_at = now(),
    cancellation_reason = p_reason,
    updated_at = now()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  IF v_was_paid THEN
    PERFORM public.reverse_commerce_order_financials(v_order.id, 'vendor_rejected_after_payment');
  END IF;

  PERFORM public.log_audit_event(
    v_order.vendor_company_id, 'commerce_order_rejected', 'commerce_orders', v_order.id,
    jsonb_build_object('reason', p_reason)
  );

  RETURN v_order;
END;
$$;

CREATE OR REPLACE FUNCTION public.customer_cancel_commerce_order(p_order_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS public.commerce_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.commerce_orders;
  v_item RECORD;
  v_was_paid BOOLEAN;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT * INTO v_order FROM public.commerce_orders WHERE id = p_order_id AND customer_id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'order_not_found'; END IF;
  IF v_order.fulfillment_status <> 'awaiting_vendor' THEN
    RAISE EXCEPTION 'cannot_cancel';
  END IF;

  v_was_paid := (v_order.payment_status = 'paid');

  FOR v_item IN
    SELECT oi.product_id, oi.quantity, p.tracks_inventory
    FROM public.commerce_order_items oi
    JOIN public.products p ON p.id = oi.product_id
    WHERE oi.order_id = v_order.id AND p.tracks_inventory = true
  LOOP
    UPDATE public.product_stock SET
      quantity_reserved = GREATEST(quantity_reserved - v_item.quantity, 0), updated_at = now()
    WHERE product_id = v_item.product_id;

    INSERT INTO public.product_stock_movements (
      product_id, company_id, quantity, movement_type, reference_type, reference_id, actor_user_id
    ) VALUES (
      v_item.product_id, v_order.vendor_company_id, v_item.quantity, 'release', 'commerce_order', v_order.id, auth.uid()
    );
  END LOOP;

  UPDATE public.commerce_orders SET
    fulfillment_status = 'cancelled',
    payment_status = CASE WHEN payment_status = 'paid' THEN 'refund_pending' ELSE payment_status END,
    cancelled_at = now(),
    cancellation_reason = p_reason
  WHERE id = v_order.id
  RETURNING * INTO v_order;

  IF v_was_paid THEN
    PERFORM public.reverse_commerce_order_financials(v_order.id, 'customer_cancelled_after_payment');
  END IF;

  RETURN v_order;
END;
$$;

-- ---------------------------------------------------------------------------
-- Settlement RPCs — super-admin only. Manual/admin-confirmed by design:
-- no money is ever electronically transferred by any function here.
-- ---------------------------------------------------------------------------

-- Claims all currently-unsettled payable entries for one payee into a new
-- settlement, atomically. Row-locks the candidate entries before claiming
-- them, so two concurrent settlement-creation calls for the same payee
-- cannot both claim the same entry (the second call's FOR UPDATE SKIP
-- LOCKED simply sees fewer/no rows once the first has claimed them).
CREATE OR REPLACE FUNCTION public.admin_create_commerce_settlement(
  p_payee_type TEXT,
  p_payee_company_id UUID,
  p_notes TEXT DEFAULT NULL
)
RETURNS public.commerce_settlements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_account_type public.commerce_ledger_account_type;
  v_settlement public.commerce_settlements;
  v_entry RECORD;
  v_total INT := 0;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  IF p_payee_type NOT IN ('vendor', 'carrier') THEN RAISE EXCEPTION 'invalid_payee_type'; END IF;
  v_account_type := CASE p_payee_type WHEN 'vendor' THEN 'vendor_payable' ELSE 'carrier_payable' END;

  INSERT INTO public.commerce_settlements (payee_type, payee_company_id, status, notes, created_by)
  VALUES (p_payee_type::public.commerce_settlement_payee_type, p_payee_company_id, 'pending', p_notes, auth.uid())
  RETURNING * INTO v_settlement;

  FOR v_entry IN
    SELECT id, amount_lrd_cents FROM public.commerce_ledger_entries
    WHERE company_id = p_payee_company_id
      AND account_type = v_account_type
      AND direction = 'credit'
      AND settlement_id IS NULL
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE public.commerce_ledger_entries SET settlement_id = v_settlement.id WHERE id = v_entry.id;

    INSERT INTO public.commerce_settlement_items (settlement_id, ledger_entry_id, amount_lrd_cents)
    VALUES (v_settlement.id, v_entry.id, v_entry.amount_lrd_cents);

    v_total := v_total + v_entry.amount_lrd_cents;
  END LOOP;

  IF v_total = 0 THEN
    RAISE EXCEPTION 'no_unsettled_payables';
  END IF;

  UPDATE public.commerce_settlements SET total_amount_lrd_cents = v_total WHERE id = v_settlement.id
  RETURNING * INTO v_settlement;

  RETURN v_settlement;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_create_commerce_settlement(TEXT, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_create_commerce_settlement(TEXT, UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_mark_commerce_settlement_processing(p_settlement_id UUID)
RETURNS public.commerce_settlements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.commerce_settlements;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;
  SELECT * INTO v_row FROM public.commerce_settlements WHERE id = p_settlement_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'settlement_not_found'; END IF;
  IF v_row.status <> 'pending' THEN RAISE EXCEPTION 'invalid_settlement_state'; END IF;
  UPDATE public.commerce_settlements SET status = 'processing' WHERE id = p_settlement_id RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_mark_commerce_settlement_processing(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_mark_commerce_settlement_processing(UUID) TO authenticated;

-- Records that DeliveryOS staff manually/externally sent the money (bank
-- transfer, cash, manual MoMo send) — this RPC records the CLAIM that it
-- happened; it never moves money itself.
CREATE OR REPLACE FUNCTION public.admin_record_commerce_settlement_reference(
  p_settlement_id UUID,
  p_external_reference TEXT,
  p_notes TEXT DEFAULT NULL
)
RETURNS public.commerce_settlements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.commerce_settlements;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;
  SELECT * INTO v_row FROM public.commerce_settlements WHERE id = p_settlement_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'settlement_not_found'; END IF;
  IF v_row.status NOT IN ('pending', 'processing') THEN RAISE EXCEPTION 'invalid_settlement_state'; END IF;

  UPDATE public.commerce_settlements SET
    external_reference = p_external_reference,
    notes = COALESCE(p_notes, notes)
  WHERE id = p_settlement_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_record_commerce_settlement_reference(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_record_commerce_settlement_reference(UUID, TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_mark_commerce_settlement_completed(p_settlement_id UUID)
RETURNS public.commerce_settlements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.commerce_settlements;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;
  SELECT * INTO v_row FROM public.commerce_settlements WHERE id = p_settlement_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'settlement_not_found'; END IF;
  IF v_row.status NOT IN ('pending', 'processing') THEN RAISE EXCEPTION 'invalid_settlement_state'; END IF;

  UPDATE public.commerce_settlements SET
    status = 'settled', settled_at = now(), settled_by = auth.uid()
  WHERE id = p_settlement_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_mark_commerce_settlement_completed(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_mark_commerce_settlement_completed(UUID) TO authenticated;

-- Failure frees the claimed entries (nulls their settlement_id) so a new
-- settlement attempt can claim them; commerce_settlement_items keeps the
-- historical record of what this failed attempt included.
CREATE OR REPLACE FUNCTION public.admin_mark_commerce_settlement_failed(p_settlement_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS public.commerce_settlements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.commerce_settlements;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;
  SELECT * INTO v_row FROM public.commerce_settlements WHERE id = p_settlement_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'settlement_not_found'; END IF;
  IF v_row.status NOT IN ('pending', 'processing') THEN RAISE EXCEPTION 'invalid_settlement_state'; END IF;

  UPDATE public.commerce_ledger_entries SET settlement_id = NULL
  WHERE settlement_id = p_settlement_id;

  UPDATE public.commerce_settlements SET
    status = 'failed', notes = COALESCE(p_reason, notes), failed_at = now(), failed_by = auth.uid()
  WHERE id = p_settlement_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_mark_commerce_settlement_failed(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_mark_commerce_settlement_failed(UUID, TEXT) TO authenticated;

-- Reversing a SETTLED settlement retracts DeliveryOS's earlier attestation
-- that the payee was paid ("this settlement record was wrong / nothing was
-- actually sent") — it does NOT model clawing back money that genuinely
-- left the building. It frees the claimed ledger entries so the underlying
-- payable (still legitimately owed) can be correctly re-settled, and stamps
-- reversed_at/reversed_by so the retraction itself is auditable. It never
-- touches commerce_financial_events/commerce_ledger_entries amounts —
-- those are the immutable accounting truth and only a settlement's CLAIM on
-- them changes here; commerce_settlement_items for the reversed settlement
-- is left untouched as its permanent historical record. A true "money was
-- sent but must be clawed back" scenario is a distinct, not-yet-built
-- primitive (see migration header) and is out of scope for V1.
CREATE OR REPLACE FUNCTION public.admin_reverse_commerce_settlement(p_settlement_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS public.commerce_settlements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.commerce_settlements;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;
  SELECT * INTO v_row FROM public.commerce_settlements WHERE id = p_settlement_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'settlement_not_found'; END IF;
  IF v_row.status <> 'settled' THEN RAISE EXCEPTION 'invalid_settlement_state'; END IF;

  UPDATE public.commerce_ledger_entries SET settlement_id = NULL WHERE settlement_id = p_settlement_id;

  UPDATE public.commerce_settlements SET
    status = 'reversed', notes = COALESCE(p_reason, notes), reversed_at = now(), reversed_by = auth.uid()
  WHERE id = p_settlement_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_reverse_commerce_settlement(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_reverse_commerce_settlement(UUID, TEXT) TO authenticated;

-- ---------------------------------------------------------------------------
-- Read RPCs: vendor / carrier / admin finance views. Every aggregate is a
-- real SUM/COUNT over ledger_entries/financial_events — nothing fabricated.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_vendor_commerce_finance(p_vendor_company_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gross INT; v_fees INT; v_net INT; v_settled INT; v_pending INT;
  v_orders JSONB;
BEGIN
  PERFORM public.assert_vendor_order_actor(p_vendor_company_id);

  SELECT
    COALESCE(SUM((snapshot ->> 'vendor_gross_lrd_cents')::INT), 0),
    COALESCE(SUM((snapshot ->> 'vendor_platform_fee_lrd_cents')::INT), 0),
    COALESCE(SUM((snapshot ->> 'vendor_net_lrd_cents')::INT), 0)
  INTO v_gross, v_fees, v_net
  FROM public.commerce_financial_events e
  JOIN public.commerce_orders o ON o.id = e.commerce_order_id
  WHERE o.vendor_company_id = p_vendor_company_id AND e.event_type = 'cod_collected';

  SELECT COALESCE(SUM(amount_lrd_cents) FILTER (WHERE settlement_id IS NOT NULL), 0),
         COALESCE(SUM(amount_lrd_cents) FILTER (WHERE settlement_id IS NULL), 0)
  INTO v_settled, v_pending
  FROM public.commerce_ledger_entries
  WHERE company_id = p_vendor_company_id AND account_type = 'vendor_payable' AND direction = 'credit';

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'order_id', o.id, 'order_number', o.order_number,
    'vendor_gross_lrd_cents', (e.snapshot ->> 'vendor_gross_lrd_cents')::INT,
    'vendor_platform_fee_lrd_cents', (e.snapshot ->> 'vendor_platform_fee_lrd_cents')::INT,
    'vendor_net_lrd_cents', (e.snapshot ->> 'vendor_net_lrd_cents')::INT,
    'recognized_at', e.created_at
  ) ORDER BY e.created_at DESC), '[]'::JSONB)
  INTO v_orders
  FROM public.commerce_financial_events e
  JOIN public.commerce_orders o ON o.id = e.commerce_order_id
  WHERE o.vendor_company_id = p_vendor_company_id AND e.event_type = 'cod_collected'
  LIMIT 100;

  RETURN jsonb_build_object(
    'vendor_gross_lrd_cents', v_gross,
    'platform_fees_lrd_cents', v_fees,
    'net_earnings_lrd_cents', v_net,
    'settled_lrd_cents', v_settled,
    'pending_settlement_lrd_cents', v_pending,
    'orders', v_orders
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_vendor_commerce_finance(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_vendor_commerce_finance(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_carrier_commerce_finance(p_carrier_company_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gross INT; v_fees INT; v_net INT; v_settled INT; v_pending INT;
  v_deliveries JSONB;
BEGIN
  IF NOT public.has_company_role(p_carrier_company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[])
     AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT
    COALESCE(SUM((snapshot ->> 'carrier_gross_lrd_cents')::INT), 0),
    COALESCE(SUM((snapshot ->> 'carrier_platform_fee_lrd_cents')::INT), 0),
    COALESCE(SUM((snapshot ->> 'carrier_net_lrd_cents')::INT), 0)
  INTO v_gross, v_fees, v_net
  FROM public.commerce_financial_events e
  JOIN public.deliveries d ON d.id = e.delivery_id
  WHERE d.company_id = p_carrier_company_id AND e.event_type = 'cod_collected';

  SELECT COALESCE(SUM(amount_lrd_cents) FILTER (WHERE settlement_id IS NOT NULL), 0),
         COALESCE(SUM(amount_lrd_cents) FILTER (WHERE settlement_id IS NULL), 0)
  INTO v_settled, v_pending
  FROM public.commerce_ledger_entries
  WHERE company_id = p_carrier_company_id AND account_type = 'carrier_payable' AND direction = 'credit';

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'delivery_id', d.id, 'tracking_code', d.tracking_code,
    'carrier_gross_lrd_cents', (e.snapshot ->> 'carrier_gross_lrd_cents')::INT,
    'carrier_platform_fee_lrd_cents', (e.snapshot ->> 'carrier_platform_fee_lrd_cents')::INT,
    'carrier_net_lrd_cents', (e.snapshot ->> 'carrier_net_lrd_cents')::INT,
    'recognized_at', e.created_at
  ) ORDER BY e.created_at DESC), '[]'::JSONB)
  INTO v_deliveries
  FROM public.commerce_financial_events e
  JOIN public.deliveries d ON d.id = e.delivery_id
  WHERE d.company_id = p_carrier_company_id AND e.event_type = 'cod_collected'
  LIMIT 100;

  RETURN jsonb_build_object(
    'carrier_gross_lrd_cents', v_gross,
    'platform_fees_lrd_cents', v_fees,
    'net_earnings_lrd_cents', v_net,
    'settled_lrd_cents', v_settled,
    'pending_settlement_lrd_cents', v_pending,
    'deliveries', v_deliveries
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_carrier_commerce_finance(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_carrier_commerce_finance(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.list_commerce_settlements(
  p_payee_type TEXT DEFAULT NULL,
  p_payee_company_id UUID DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_limit INT DEFAULT 25,
  p_offset INT DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total INT;
  v_rows JSONB;
BEGIN
  IF p_payee_company_id IS NOT NULL THEN
    IF NOT public.has_company_role(p_payee_company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[])
       AND NOT public.is_super_admin() THEN
      RAISE EXCEPTION 'forbidden';
    END IF;
  ELSIF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT COUNT(*)::INT INTO v_total
  FROM public.commerce_settlements s
  WHERE (p_payee_type IS NULL OR s.payee_type::TEXT = p_payee_type)
    AND (p_payee_company_id IS NULL OR s.payee_company_id = p_payee_company_id)
    AND (p_status IS NULL OR s.status::TEXT = p_status);

  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::JSONB) INTO v_rows
  FROM (
    SELECT s.*, c.name AS payee_company_name
    FROM public.commerce_settlements s
    JOIN public.companies c ON c.id = s.payee_company_id
    WHERE (p_payee_type IS NULL OR s.payee_type::TEXT = p_payee_type)
      AND (p_payee_company_id IS NULL OR s.payee_company_id = p_payee_company_id)
      AND (p_status IS NULL OR s.status::TEXT = p_status)
    ORDER BY s.created_at DESC
    LIMIT LEAST(GREATEST(p_limit, 1), 100)
    OFFSET GREATEST(p_offset, 0)
  ) t;

  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END;
$$;

REVOKE ALL ON FUNCTION public.list_commerce_settlements(TEXT, UUID, TEXT, INT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_commerce_settlements(TEXT, UUID, TEXT, INT, INT) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_admin_commerce_finance_overview(
  p_from TIMESTAMPTZ DEFAULT NULL,
  p_to TIMESTAMPTZ DEFAULT NULL,
  p_vendor_company_id UUID DEFAULT NULL,
  p_carrier_company_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gmv INT; v_cod_collected INT; v_platform_revenue INT;
  v_vendor_unsettled INT; v_carrier_unsettled INT;
  v_settled_count INT; v_failed_count INT; v_reversal_count INT;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT COALESCE(SUM((e.snapshot ->> 'total_collected_lrd_cents')::INT), 0),
         COALESCE(SUM((e.snapshot ->> 'total_collected_lrd_cents')::INT), 0)
  INTO v_gmv, v_cod_collected
  FROM public.commerce_financial_events e
  JOIN public.commerce_orders o ON o.id = e.commerce_order_id
  WHERE e.event_type = 'cod_collected'
    AND (p_from IS NULL OR e.created_at >= p_from)
    AND (p_to IS NULL OR e.created_at < p_to)
    AND (p_vendor_company_id IS NULL OR o.vendor_company_id = p_vendor_company_id)
    AND (p_carrier_company_id IS NULL OR EXISTS (SELECT 1 FROM public.deliveries d WHERE d.id = e.delivery_id AND d.company_id = p_carrier_company_id));

  SELECT COALESCE(SUM(amount_lrd_cents), 0) INTO v_platform_revenue
  FROM public.commerce_ledger_entries le
  JOIN public.commerce_financial_events e ON e.id = le.financial_event_id
  WHERE le.account_type = 'platform_revenue' AND le.direction = 'credit'
    AND (p_from IS NULL OR le.created_at >= p_from)
    AND (p_to IS NULL OR le.created_at < p_to);

  SELECT COALESCE(SUM(amount_lrd_cents), 0) INTO v_vendor_unsettled
  FROM public.commerce_ledger_entries
  WHERE account_type = 'vendor_payable' AND direction = 'credit' AND settlement_id IS NULL
    AND (p_vendor_company_id IS NULL OR company_id = p_vendor_company_id);

  SELECT COALESCE(SUM(amount_lrd_cents), 0) INTO v_carrier_unsettled
  FROM public.commerce_ledger_entries
  WHERE account_type = 'carrier_payable' AND direction = 'credit' AND settlement_id IS NULL
    AND (p_carrier_company_id IS NULL OR company_id = p_carrier_company_id);

  SELECT COUNT(*) FILTER (WHERE status = 'settled'), COUNT(*) FILTER (WHERE status = 'failed')
  INTO v_settled_count, v_failed_count
  FROM public.commerce_settlements;

  SELECT COUNT(*) INTO v_reversal_count FROM public.commerce_financial_events WHERE event_type = 'reversal';

  RETURN jsonb_build_object(
    'commerce_gmv_lrd_cents', v_gmv,
    'cod_collected_lrd_cents', v_cod_collected,
    'platform_revenue_lrd_cents', v_platform_revenue,
    'vendor_unsettled_lrd_cents', v_vendor_unsettled,
    'carrier_unsettled_lrd_cents', v_carrier_unsettled,
    'settlements_completed', v_settled_count,
    'settlements_failed', v_failed_count,
    'reversals_count', v_reversal_count
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_admin_commerce_finance_overview(TIMESTAMPTZ, TIMESTAMPTZ, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_admin_commerce_finance_overview(TIMESTAMPTZ, TIMESTAMPTZ, UUID, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_list_commerce_financial_events(
  p_limit INT DEFAULT 25,
  p_offset INT DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total INT;
  v_rows JSONB;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT COUNT(*)::INT INTO v_total FROM public.commerce_financial_events;

  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::JSONB) INTO v_rows
  FROM (
    SELECT e.*, o.order_number, o.vendor_company_id
    FROM public.commerce_financial_events e
    JOIN public.commerce_orders o ON o.id = e.commerce_order_id
    ORDER BY e.created_at DESC
    LIMIT LEAST(GREATEST(p_limit, 1), 100)
    OFFSET GREATEST(p_offset, 0)
  ) t;

  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_commerce_financial_events(INT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_commerce_financial_events(INT, INT) TO authenticated;

-- ---------------------------------------------------------------------------
-- Zero-fee carrier hardening (requirement 14).
--
-- provider_matches_delivery_request and the pre-existing B2B
-- publish_delivery_request path NEVER read minimum_delivery_fee_lrd_cents
-- (confirmed by full-repo audit) — the merchant sets its own price on
-- delivery_requests.quoted_amount_lrd_cents and that exact price is
-- broadcast to every matching provider regardless of their configured
-- minimum. The ONLY consumer of minimum_delivery_fee_lrd_cents anywhere is
-- Commerce's own request_commerce_order_delivery (Phase D). Hardening it
-- is therefore fully isolated to Commerce and cannot affect B2B.
--
-- The gate is "never configured" vs "explicitly configured", not
-- "amount > 0" — a carrier must still be able to intentionally offer free
-- delivery. delivery_pricing_configured_at is NULL until a provider
-- explicitly saves their marketplace profile at least once (including via
-- create_company_with_owner's auto-created row, which never touches this
-- column); Commerce's offer fan-out now requires it to be set.
-- ---------------------------------------------------------------------------
ALTER TABLE public.provider_marketplace_profiles
  ADD COLUMN IF NOT EXISTS delivery_pricing_configured_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public.upsert_provider_marketplace_profile(p_payload JSONB)
RETURNS public.provider_marketplace_profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID := (p_payload ->> 'company_id')::UUID;
  v_row public.provider_marketplace_profiles;
BEGIN
  IF NOT public.has_company_role(v_company_id, ARRAY['company_owner']::public.company_role[])
     AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  INSERT INTO public.provider_marketplace_profiles (
    company_id, marketplace_enabled, service_description, service_phone, service_email,
    service_regions, accepting_jobs, minimum_delivery_fee_lrd_cents,
    maximum_service_distance_km, rating_visible, business_hours, delivery_pricing_configured_at
  ) VALUES (
    v_company_id,
    COALESCE((p_payload ->> 'marketplace_enabled')::BOOLEAN, false),
    p_payload ->> 'service_description',
    p_payload ->> 'service_phone',
    p_payload ->> 'service_email',
    COALESCE(p_payload -> 'service_regions', '[]'::JSONB),
    COALESCE((p_payload ->> 'accepting_jobs')::BOOLEAN, false),
    COALESCE((p_payload ->> 'minimum_delivery_fee_lrd_cents')::INT, 0),
    NULLIF(p_payload ->> 'maximum_service_distance_km', '')::NUMERIC,
    COALESCE((p_payload ->> 'rating_visible')::BOOLEAN, true),
    COALESCE(p_payload -> 'business_hours', '{}'::JSONB),
    now()
  )
  ON CONFLICT (company_id) DO UPDATE SET
    marketplace_enabled = COALESCE((p_payload ->> 'marketplace_enabled')::BOOLEAN, provider_marketplace_profiles.marketplace_enabled),
    service_description = COALESCE(p_payload ->> 'service_description', provider_marketplace_profiles.service_description),
    service_phone = COALESCE(p_payload ->> 'service_phone', provider_marketplace_profiles.service_phone),
    service_email = COALESCE(p_payload ->> 'service_email', provider_marketplace_profiles.service_email),
    service_regions = COALESCE(p_payload -> 'service_regions', provider_marketplace_profiles.service_regions),
    accepting_jobs = COALESCE((p_payload ->> 'accepting_jobs')::BOOLEAN, provider_marketplace_profiles.accepting_jobs),
    minimum_delivery_fee_lrd_cents = COALESCE((p_payload ->> 'minimum_delivery_fee_lrd_cents')::INT, provider_marketplace_profiles.minimum_delivery_fee_lrd_cents),
    maximum_service_distance_km = COALESCE(NULLIF(p_payload ->> 'maximum_service_distance_km', '')::NUMERIC, provider_marketplace_profiles.maximum_service_distance_km),
    rating_visible = COALESCE((p_payload ->> 'rating_visible')::BOOLEAN, provider_marketplace_profiles.rating_visible),
    business_hours = COALESCE(p_payload -> 'business_hours', provider_marketplace_profiles.business_hours),
    delivery_pricing_configured_at = now(),
    updated_at = now()
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_provider_marketplace_profile TO authenticated;

CREATE OR REPLACE FUNCTION public.request_commerce_order_delivery(p_order_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.commerce_orders;
  v_req public.delivery_requests;
  v_store public.store_profiles;
  v_branch public.company_branches;
  v_company public.companies;
  v_package_count INT;
  v_package_description TEXT;
  v_provider RECORD;
  v_offer_count INT := 0;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT * INTO v_order FROM public.commerce_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'order_not_found'; END IF;

  PERFORM public.assert_vendor_order_actor(v_order.vendor_company_id);

  IF v_order.delivery_request_id IS NOT NULL THEN
    SELECT * INTO v_req FROM public.delivery_requests WHERE id = v_order.delivery_request_id;
    RETURN jsonb_build_object(
      'delivery_request', to_jsonb(v_req),
      'offers_created', 0,
      'already_existed', true
    );
  END IF;

  IF v_order.fulfillment_status <> 'ready_for_pickup' THEN
    RAISE EXCEPTION 'invalid_fulfillment_state';
  END IF;

  PERFORM public.assert_merchant_marketplace(v_order.vendor_company_id);

  SELECT * INTO v_store FROM public.store_profiles WHERE company_id = v_order.vendor_company_id;
  SELECT * INTO v_company FROM public.companies WHERE id = v_order.vendor_company_id;

  SELECT * INTO v_branch FROM public.company_branches
  WHERE id = v_company.default_branch_id AND is_active = true;
  IF NOT FOUND THEN
    SELECT * INTO v_branch FROM public.company_branches
    WHERE company_id = v_order.vendor_company_id AND is_active = true
    ORDER BY created_at LIMIT 1;
  END IF;

  IF v_branch.id IS NULL AND v_company.address IS NULL THEN
    RAISE EXCEPTION 'pickup_location_not_configured';
  END IF;

  SELECT COALESCE(SUM(oi.quantity), 1)::INT INTO v_package_count
  FROM public.commerce_order_items oi WHERE oi.order_id = v_order.id;

  SELECT v_package_count || ' item(s) from ' || COALESCE(v_store.display_name, v_company.name)
  INTO v_package_description;

  INSERT INTO public.delivery_requests (
    merchant_company_id, pickup_branch_id,
    pickup_address, pickup_latitude, pickup_longitude, pickup_area_summary,
    destination_address, destination_latitude, destination_longitude, destination_area_summary,
    package_count, cod_amount_lrd_cents, delivery_notes,
    customer_name, customer_phone, package_description,
    status, created_by
  ) VALUES (
    v_order.vendor_company_id,
    v_branch.id,
    COALESCE(v_branch.address, v_company.address, v_store.display_name),
    v_branch.latitude,
    v_branch.longitude,
    COALESCE(v_branch.name, v_store.display_name),
    v_order.delivery_address,
    v_order.delivery_latitude,
    v_order.delivery_longitude,
    v_order.delivery_area_summary,
    v_package_count,
    v_order.subtotal_lrd_cents,
    v_order.delivery_instructions,
    v_order.customer_name,
    v_order.customer_phone,
    v_package_description,
    'open',
    auth.uid()
  )
  RETURNING * INTO v_req;

  UPDATE public.commerce_orders SET delivery_request_id = v_req.id, updated_at = now() WHERE id = p_order_id;

  -- Real, per-carrier fan-out — see header comment. Now also requires the
  -- provider to have explicitly configured (not merely defaulted)
  -- marketplace pricing at least once, closing the zero-fee-by-accident
  -- gap identified in Phase D.
  FOR v_provider IN
    SELECT c.id AS company_id, p.minimum_delivery_fee_lrd_cents
    FROM public.companies c
    JOIN public.provider_marketplace_profiles p ON p.company_id = c.id
    WHERE c.business_type IN ('logistics_provider', 'hybrid')
      AND p.delivery_pricing_configured_at IS NOT NULL
      AND public.provider_matches_delivery_request(c.id, v_req)
    LIMIT 50
  LOOP
    INSERT INTO public.delivery_offers (
      delivery_request_id, provider_company_id, quoted_amount_lrd_cents, expires_at
    ) VALUES (
      v_req.id, v_provider.company_id, GREATEST(v_provider.minimum_delivery_fee_lrd_cents, 0), now() + interval '24 hours'
    )
    ON CONFLICT (delivery_request_id, provider_company_id) DO NOTHING;

    IF FOUND THEN
      v_offer_count := v_offer_count + 1;
      PERFORM public.enqueue_webhook_event(
        v_provider.company_id, 'marketplace_job.available', v_req.id,
        jsonb_build_object(
          'delivery_request_id', v_req.id, 'pickup_area', v_req.pickup_area_summary,
          'destination_area', v_req.destination_area_summary,
          'quoted_amount_lrd_cents', GREATEST(v_provider.minimum_delivery_fee_lrd_cents, 0)
        )
      );
    END IF;
  END LOOP;

  IF v_offer_count > 0 THEN
    UPDATE public.delivery_requests SET status = 'offered' WHERE id = v_req.id RETURNING * INTO v_req;
  END IF;

  PERFORM public.enqueue_webhook_event(
    v_order.vendor_company_id, 'commerce_order.delivery_requested', v_order.id, to_jsonb(v_req)
  );

  RETURN jsonb_build_object(
    'delivery_request', to_jsonb(v_req),
    'offers_created', v_offer_count,
    'already_existed', false
  );
END;
$$;

REVOKE ALL ON FUNCTION public.request_commerce_order_delivery(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_commerce_order_delivery(UUID) TO authenticated;
