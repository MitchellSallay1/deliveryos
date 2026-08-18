-- Coverage for DeliveryOS Commerce Phase E2 — MTN MoMo payment engine
-- (20260311000000_commerce_phase_e2_mtn_momo_payments.sql), covering BOTH
-- correction passes: the production-flow correction (payment after carrier
-- selection, carrier-leg ledger recognition, offer/price lock) AND the
-- real-money-invariants correction (payment certainty vs. economic anomaly,
-- the offer/price financial lock superseding the bounded reservation
-- window, and the frozen payable snapshot).
--
-- PRODUCTION FINANCIAL SYSTEM. Proves, among other things:
--   - the real production flow (vendor accepts unpaid -> carrier selected
--     -> MTN payment -> carrier acceptance gated on payment -> rider ->
--     delivered -> completed) produces exactly one financial recognition;
--   - a definitively successful MTN collection is ALWAYS 'successful',
--     never reclassified as 'unknown' merely because the provider fee
--     exceeds platform commission — that is recorded as a margin_anomaly
--     accounting flag instead, with the fee posted in full to a dedicated
--     payment_processing_expense account and vendor/carrier/platform
--     amounts left exactly as the fee rules produced them;
--   - malformed/inconsistent provider evidence (or a gross that doesn't
--     match what DeliveryOS authoritatively intended to collect) still
--     fails closed into 'unknown' — genuine uncertainty is the only thing
--     that ever does that;
--   - the selected carrier offer and its price are financially LOCKED the
--     moment a payment attempt exists (any state but 'failed'), immune to
--     the routine offer-expiry sweep, and cannot be swapped for a
--     different, differently-priced carrier — not while unresolved, not
--     after success;
--   - payment_attempts freezes the exact subtotal/delivery-fee/gross the
--     customer authorized, independent of any later mutation to the live
--     order/offer rows;
--   - COD is completely unaffected by any of the above.

BEGIN;
SELECT plan(61);

SELECT has_table('public'::name, 'payment_attempts'::name);
SELECT has_column('public'::name, 'payment_attempts'::name, 'selected_offer_id'::name, 'payment_attempts.selected_offer_id should exist');
SELECT has_column('public'::name, 'payment_attempts'::name, 'subtotal_snapshot_lrd_cents'::name, 'payment_attempts.subtotal_snapshot_lrd_cents should exist');
SELECT has_column('public'::name, 'payment_attempts'::name, 'delivery_fee_snapshot_lrd_cents'::name, 'payment_attempts.delivery_fee_snapshot_lrd_cents should exist');
SELECT has_column('public'::name, 'payment_attempts'::name, 'margin_anomaly'::name, 'payment_attempts.margin_anomaly should exist');
SELECT has_enum('public'::name, 'payment_attempt_state'::name);
SELECT has_function('public'::name, 'initiate_commerce_order_mtn_payment'::name);
SELECT has_function('public'::name, 'mark_payment_attempt_requesting'::name);
SELECT has_function('public'::name, 'record_payment_attempt_result'::name);
SELECT has_function('public'::name, 'sweep_stuck_payment_attempts'::name);
SELECT has_function('public'::name, 'admin_reconcile_payment_attempt'::name);
SELECT has_function('public'::name, 'recognize_commerce_order_mtn_financials'::name);
SELECT has_function('public'::name, 'estimate_commerce_mtn_platform_commission_cents'::name);

SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.payment_attempts'::regclass),
  'payment_attempts has RLS enabled'
);

-- ---------------------------------------------------------------------------
-- Shared fixtures — same shape as commerce_phase_d.test.sql / commerce_phase_f.test.sql
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.make_user(p_label TEXT)
RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
  v_user UUID := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, phone, email, encrypted_password, phone_confirmed_at, aud, role)
  VALUES (v_user, '+2317' || lpad((floor(random() * 9999999))::text, 7, '0'), 'e2-' || substr(v_user::text, 1, 8) || '@test.local', crypt('x', gen_salt('bf')), now(), 'authenticated', 'authenticated');
  INSERT INTO public.profiles (id, full_name) VALUES (v_user, p_label) ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name;
  RETURN v_user;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.make_company(p_label TEXT, p_business_type public.company_business_type, p_admin UUID)
RETURNS TABLE (company_id UUID, owner_id UUID) LANGUAGE plpgsql AS $$
DECLARE
  v_owner UUID := pg_temp.make_user(p_label || ' Owner');
  v_company UUID;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  v_company := public.create_company_with_owner(p_label, '+2317' || lpad((floor(random() * 9999999))::text, 7, '0'), lower(replace(p_label, ' ', '')) || '@test.local', NULL, p_business_type);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  UPDATE public.company_subscriptions SET plan_id = (SELECT id FROM public.subscriptions WHERE slug = 'business')
  WHERE company_subscriptions.company_id = v_company;
  IF p_business_type = 'merchant' THEN
    PERFORM set_config('request.jwt.claim.sub', p_admin::text, true);
    PERFORM public.admin_set_vendor_state(v_company, 'active', NULL);
    PERFORM set_config('request.jwt.claim.sub', '', true);
  END IF;
  RETURN QUERY SELECT v_company, v_owner;
END;
$$;

-- Full setup helper: admin + vendor + two carriers (A cheaper, B pricier) +
-- customer + one product + a submitted mtn_momo order taken through vendor
-- accept/prepare/ready/request-delivery, with two real offers created.
-- Returns everything a scenario needs to keep going. Kept as one reusable
-- helper since every block below starts from this same setup.
CREATE OR REPLACE FUNCTION pg_temp.setup_mtn_order(
  p_label TEXT, p_product_price INT, p_offer_a_fee INT, p_offer_b_fee INT
)
RETURNS TABLE (
  admin_id UUID, vendor_id UUID, vendor_owner UUID,
  carrier_a UUID, carrier_a_owner UUID, carrier_b UUID, carrier_b_owner UUID,
  customer_id UUID, order_id UUID, offer_a_id UUID, offer_b_id UUID
) LANGUAGE plpgsql AS $$
DECLARE
  v_admin UUID; v_vendor UUID; v_vendor_owner UUID;
  v_carrier_a UUID; v_carrier_a_owner UUID; v_carrier_b UUID; v_carrier_b_owner UUID;
  v_customer UUID; v_product UUID; v_result RECORD; v_cart UUID;
  v_order public.commerce_orders; v_offer_a_id UUID; v_offer_b_id UUID;
BEGIN
  v_admin := pg_temp.make_user(p_label || ' Admin');
  UPDATE public.profiles SET is_super_admin = true WHERE id = v_admin;

  -- This file tests the MTN payment engine's own invariants, not the
  -- activation control (see mtn_momo_activation_control.test.sql for that)
  -- — so every scenario here needs MTN collection actually enabled, since
  -- it now defaults to disabled (production activation-control audit).
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM public.admin_set_platform_setting('mtn_momo_collections_enabled', 'true');
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT company_id, owner_id INTO v_vendor, v_vendor_owner FROM pg_temp.make_company(p_label || ' Vendor', 'merchant', v_admin);
  SELECT company_id, owner_id INTO v_carrier_a, v_carrier_a_owner FROM pg_temp.make_company(p_label || ' Carrier A', 'logistics_provider', v_admin);
  SELECT company_id, owner_id INTO v_carrier_b, v_carrier_b_owner FROM pg_temp.make_company(p_label || ' Carrier B', 'logistics_provider', v_admin);
  v_customer := pg_temp.make_user(p_label || ' Customer');

  UPDATE public.companies SET address = '1 Test Street, Monrovia' WHERE id = v_vendor;

  PERFORM set_config('request.jwt.claim.sub', v_vendor_owner::text, true);
  PERFORM public.upsert_store_profile(jsonb_build_object('company_id', v_vendor, 'slug', lower(replace(p_label, ' ', '')) || '-vendor', 'display_name', p_label || ' Vendor', 'allow_cash_on_delivery', true));
  v_result := public.upsert_product(jsonb_build_object('company_id', v_vendor, 'name', p_label || ' Product', 'price_lrd_cents', p_product_price, 'status', 'active'));
  v_product := (v_result).id;
  PERFORM set_config('request.jwt.claim.sub', '', true);

  PERFORM set_config('request.jwt.claim.sub', v_carrier_a_owner::text, true);
  PERFORM public.upsert_provider_marketplace_profile(jsonb_build_object('company_id', v_carrier_a, 'marketplace_enabled', true, 'accepting_jobs', true, 'minimum_delivery_fee_lrd_cents', p_offer_a_fee));
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.sub', v_carrier_b_owner::text, true);
  PERFORM public.upsert_provider_marketplace_profile(jsonb_build_object('company_id', v_carrier_b, 'marketplace_enabled', true, 'accepting_jobs', true, 'minimum_delivery_fee_lrd_cents', p_offer_b_fee));
  PERFORM set_config('request.jwt.claim.sub', '', true);

  PERFORM set_config('request.jwt.claim.sub', v_customer::text, true);
  v_cart := (public.get_or_create_cart(v_vendor)).id;
  PERFORM public.add_cart_item(v_cart, v_product, 1, '[]'::JSONB);
  v_order := public.submit_commerce_order(v_cart, p_label || ' Customer', 'Test address', 'Test area', NULL, NULL, NULL, 'mtn_momo');
  PERFORM set_config('request.jwt.claim.sub', '', true);

  PERFORM set_config('request.jwt.claim.sub', v_vendor_owner::text, true);
  PERFORM public.vendor_accept_commerce_order(v_order.id);
  PERFORM public.vendor_mark_order_preparing(v_order.id);
  v_order := public.vendor_mark_order_ready(v_order.id);
  PERFORM public.request_commerce_order_delivery(v_order.id);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  SELECT * INTO v_order FROM public.commerce_orders WHERE id = v_order.id;

  SELECT o.id INTO v_offer_a_id FROM public.delivery_offers o WHERE o.delivery_request_id = v_order.delivery_request_id AND o.provider_company_id = v_carrier_a;
  SELECT o.id INTO v_offer_b_id FROM public.delivery_offers o WHERE o.delivery_request_id = v_order.delivery_request_id AND o.provider_company_id = v_carrier_b;

  RETURN QUERY SELECT v_admin, v_vendor, v_vendor_owner, v_carrier_a, v_carrier_a_owner, v_carrier_b, v_carrier_b_owner, v_customer, v_order.id, v_offer_a_id, v_offer_b_id;
END;
$$;

-- =============================================================================
-- BLOCK 1 — Happy path: production flow, offer/price lock, margin-healthy fee.
-- =============================================================================
DO $$
DECLARE
  v_admin UUID; v_vendor UUID; v_vendor_owner UUID;
  v_carrier_a UUID; v_carrier_a_owner UUID; v_carrier_b UUID; v_carrier_b_owner UUID;
  v_customer UUID; v_order public.commerce_orders; v_order_id UUID; v_offer_a_id UUID; v_offer_b_id UUID;
  v_attempt public.payment_attempts;
  v_forbidden BOOLEAN;
  v_delivery public.deliveries;
  v_rider UUID;
  v_ledger RECORD;
  v_events_count INT;
  v_offer_expires TIMESTAMPTZ;
  v_snapshot JSONB;
BEGIN
  SELECT * INTO v_admin, v_vendor, v_vendor_owner, v_carrier_a, v_carrier_a_owner, v_carrier_b, v_carrier_b_owner, v_customer, v_order_id, v_offer_a_id, v_offer_b_id
  FROM pg_temp.setup_mtn_order('E2B', 20000, 1500, 2000);
  SELECT * INTO v_order FROM public.commerce_orders WHERE id = v_order_id;

  -- Healthy commission: a vendor-specific override (10%) on top of
  -- marketplace_fee_rules' 10% platform default on the carrier leg, so
  -- available commission comfortably exceeds the provider fee used below.
  INSERT INTO public.commerce_fee_rules (name, fee_model, percentage_bps, is_active, applies_to_vendor_company_id)
  VALUES ('E2B test vendor commission', 'percentage', 1000, true, v_vendor);

  CREATE TEMP TABLE e2b_assertions (key TEXT PRIMARY KEY, ok BOOLEAN);

  -- setup_mtn_order already ran vendor_accept_commerce_order -> preparing ->
  -- ready -> request_commerce_order_delivery for this mtn_momo order without
  -- raising — if commerce_order_payment_eligible_for_acceptance still
  -- required payment_status = 'paid' before acceptance (the pre-fix
  -- behavior), vendor_accept_commerce_order would have raised and aborted
  -- this entire test file well before reaching here. Reaching this point
  -- with the order still honestly unpaid IS the proof.
  INSERT INTO e2b_assertions VALUES (
    'vendor_can_accept_unpaid_mtn_order',
    v_order.delivery_request_id IS NOT NULL AND v_order.payment_status = 'pending_payment'
  );
  INSERT INTO e2b_assertions VALUES ('two_real_offers_created', v_offer_a_id IS NOT NULL AND v_offer_b_id IS NOT NULL);

  -- Payment cannot start before a carrier is selected.
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_customer::text, true);
    PERFORM public.initiate_commerce_order_mtn_payment(v_order.id, '0770229690');
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%no_carrier_selected%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  INSERT INTO e2b_assertions VALUES ('payment_blocked_before_carrier_selected', v_forbidden);

  -- Customer selects carrier A -> reservation extended.
  UPDATE public.delivery_offers SET expires_at = now() + interval '2 minutes' WHERE id = v_offer_a_id;
  PERFORM set_config('request.jwt.claim.sub', v_customer::text, true);
  PERFORM public.select_commerce_delivery_offer(v_order.id, v_offer_a_id);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT expires_at INTO v_offer_expires FROM public.delivery_offers WHERE id = v_offer_a_id;
  INSERT INTO e2b_assertions VALUES (
    'offer_reservation_extended_for_mtn_pending_order',
    v_offer_expires >= now() + interval '14 minutes'
  );

  PERFORM set_config('request.jwt.claim.sub', v_customer::text, true);
  v_attempt := public.initiate_commerce_order_mtn_payment(v_order.id, '0770229690');
  PERFORM set_config('request.jwt.claim.sub', '', true);
  INSERT INTO e2b_assertions VALUES (
    'final_total_includes_selected_carrier_fee',
    v_attempt.gross_amount_cents = 20000 + 1500 AND v_attempt.selected_offer_id = v_offer_a_id
  );
  INSERT INTO e2b_assertions VALUES (
    'snapshot_freezes_subtotal_and_delivery_fee',
    v_attempt.subtotal_snapshot_lrd_cents = 20000 AND v_attempt.delivery_fee_snapshot_lrd_cents = 1500
  );

  -- Double-charge guard still holds.
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_customer::text, true);
    PERFORM public.initiate_commerce_order_mtn_payment(v_order.id, '0770229690');
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%payment_already_in_progress%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  INSERT INTO e2b_assertions VALUES ('double_charge_guard_still_enforced', v_forbidden);

  -- Financial lock: a DIFFERENT carrier cannot be selected while payment is
  -- unresolved (attempt still 'created').
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_customer::text, true);
    PERFORM public.select_commerce_delivery_offer(v_order.id, v_offer_b_id);
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%offer_locked_by_active_payment%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  INSERT INTO e2b_assertions VALUES ('second_carrier_selection_blocked_during_unresolved_payment', v_forbidden);

  -- Carrier acceptance is blocked until payment clears.
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_carrier_a_owner::text, true);
    PERFORM public.accept_marketplace_offer(v_offer_a_id, v_carrier_a);
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%payment_not_confirmed%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  INSERT INTO e2b_assertions VALUES ('carrier_acceptance_blocked_before_payment', v_forbidden);

  -- MTN succeeds: healthy margin (fee 800 <= commission 2150) -> successful,
  -- margin_anomaly = false, order paid.
  v_attempt := public.mark_payment_attempt_requesting(v_attempt.id);
  v_attempt := public.record_payment_attempt_result(
    v_attempt.id, 'successful', 'SUCCESSFUL', 200, 'ref-1', 'fin-1', 21500, 800, 20700, NULL, NULL
  );
  SELECT * INTO v_order FROM public.commerce_orders WHERE id = v_order.id;
  INSERT INTO e2b_assertions VALUES ('mtn_success_marks_order_paid', v_attempt.state = 'successful' AND v_order.payment_status = 'paid');
  INSERT INTO e2b_assertions VALUES ('healthy_margin_no_anomaly_flag', v_attempt.margin_anomaly = false);

  -- Financial lock persists permanently after success, BEFORE carrier
  -- acceptance (delivery_id still NULL here) — this is the window the lock
  -- specifically protects; a live re-read of a "still pending" offer must
  -- never be swappable once money has moved.
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_customer::text, true);
    PERFORM public.select_commerce_delivery_offer(v_order.id, v_offer_b_id);
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%offer_locked_by_active_payment%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  INSERT INTO e2b_assertions VALUES ('second_carrier_selection_blocked_after_successful_payment', v_forbidden);

  -- Duplicate finalization is a safe no-op (order marked paid exactly once,
  -- no second financial event).
  PERFORM public.finalize_successful_payment_attempt(v_attempt.id);
  SELECT COUNT(*)::INT INTO v_events_count FROM public.commerce_financial_events WHERE commerce_order_id = v_order.id AND event_type = 'mtn_momo_collected';
  INSERT INTO e2b_assertions VALUES ('order_marked_paid_exactly_once', v_events_count = 1);

  PERFORM set_config('request.jwt.claim.sub', v_carrier_a_owner::text, true);
  PERFORM public.accept_marketplace_offer(v_offer_a_id, v_carrier_a);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT * INTO v_order FROM public.commerce_orders WHERE id = v_order.id;
  SELECT * INTO v_delivery FROM public.deliveries WHERE id = v_order.delivery_id;
  INSERT INTO e2b_assertions VALUES ('carrier_accepts_after_payment', v_delivery.id IS NOT NULL);
  INSERT INTO e2b_assertions VALUES ('amount_to_collect_zero_for_prepaid_order', v_delivery.amount_to_collect_lrd_cents = 0);
  INSERT INTO e2b_assertions VALUES (
    'carrier_acceptance_uses_frozen_delivery_fee',
    v_delivery.delivery_fee_lrd_cents = 1500 AND v_order.delivery_fee_lrd_cents = 1500 AND v_order.total_lrd_cents = 21500
  );

  SELECT
    SUM(amount_lrd_cents) FILTER (WHERE account_type = 'vendor_payable' AND direction = 'credit') AS vendor_payable,
    SUM(amount_lrd_cents) FILTER (WHERE account_type = 'carrier_payable' AND direction = 'credit') AS carrier_payable,
    COALESCE(SUM(amount_lrd_cents) FILTER (WHERE account_type = 'platform_revenue' AND direction = 'credit'), 0)
      - COALESCE(SUM(amount_lrd_cents) FILTER (WHERE account_type = 'platform_revenue' AND direction = 'debit'), 0) AS platform_revenue_net,
    SUM(amount_lrd_cents) FILTER (WHERE account_type = 'payment_processing_expense' AND direction = 'debit') AS processing_expense,
    SUM(amount_lrd_cents) FILTER (WHERE account_type = 'provider_clearing' AND direction = 'debit')
      - SUM(amount_lrd_cents) FILTER (WHERE account_type = 'provider_clearing' AND direction = 'credit') AS provider_clearing_net,
    SUM(amount_lrd_cents) FILTER (WHERE direction = 'debit') AS debits,
    SUM(amount_lrd_cents) FILTER (WHERE direction = 'credit') AS credits
  INTO v_ledger
  FROM public.commerce_ledger_entries e JOIN public.commerce_financial_events ev ON ev.id = e.financial_event_id
  WHERE ev.commerce_order_id = v_order.id;

  INSERT INTO e2b_assertions VALUES ('ledger_balances', v_ledger.debits = v_ledger.credits);
  INSERT INTO e2b_assertions VALUES ('provider_clearing_net_is_gross_minus_fee', v_ledger.provider_clearing_net = 21500 - 800);
  INSERT INTO e2b_assertions VALUES ('vendor_payable_present_and_carrier_payable_present', v_ledger.vendor_payable > 0 AND v_ledger.carrier_payable > 0);
  INSERT INTO e2b_assertions VALUES ('platform_revenue_is_full_commission_untouched_by_fee', v_ledger.platform_revenue_net = 2000 + 150);
  INSERT INTO e2b_assertions VALUES ('processing_expense_equals_full_provider_fee', v_ledger.processing_expense = 800);

  SELECT COUNT(*)::INT INTO v_events_count FROM public.commerce_financial_events WHERE commerce_order_id = v_order.id AND event_type = 'mtn_momo_collected';
  INSERT INTO e2b_assertions VALUES ('exactly_one_recognition_event_after_acceptance', v_events_count = 1);

  -- Full lifecycle to delivered/completed -> STILL exactly one recognition event.
  INSERT INTO public.riders (company_id, rider_code, full_name, phone, status)
  VALUES (v_carrier_a, 'E2B-' || substr(gen_random_uuid()::text, 1, 8), 'E2B Rider', '+231884' || lpad((floor(random()*999999))::text,6,'0'), 'available')
  RETURNING id INTO v_rider;

  PERFORM set_config('request.jwt.claim.sub', v_carrier_a_owner::text, true);
  PERFORM public.assign_delivery_rider(v_order.delivery_id, v_rider);
  PERFORM public.transition_delivery_status(v_order.delivery_id, 'accepted', NULL);
  PERFORM public.transition_delivery_status(v_order.delivery_id, 'picked_up', NULL);
  PERFORM public.transition_delivery_status(v_order.delivery_id, 'in_transit', NULL);
  PERFORM public.transition_delivery_status(v_order.delivery_id, 'delivered', NULL);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT * INTO v_order FROM public.commerce_orders WHERE id = v_order.id;
  SELECT COUNT(*)::INT INTO v_events_count FROM public.commerce_financial_events WHERE commerce_order_id = v_order.id AND event_type = 'mtn_momo_collected';
  INSERT INTO e2b_assertions VALUES ('order_completed_after_full_lifecycle', v_order.fulfillment_status = 'completed');
  INSERT INTO e2b_assertions VALUES ('still_exactly_one_recognition_event_after_full_lifecycle', v_events_count = 1);
END;
$$;

SELECT ok((SELECT ok FROM e2b_assertions WHERE key = 'vendor_can_accept_unpaid_mtn_order'), 'STATE-MACHINE FIX: vendor can accept an mtn_momo order while genuinely still pending_payment, same as COD');
SELECT ok((SELECT ok FROM e2b_assertions WHERE key = 'two_real_offers_created'), 'two real, differently-priced carrier offers are created on delivery request');
SELECT ok((SELECT ok FROM e2b_assertions WHERE key = 'payment_blocked_before_carrier_selected'), 'MTN payment cannot start before a carrier offer has been selected (no final total exists yet)');
SELECT ok((SELECT ok FROM e2b_assertions WHERE key = 'offer_reservation_extended_for_mtn_pending_order'), 'selecting an offer for an unpaid mtn_momo order extends its reservation window past the routine 5-minute expiry sweep');
SELECT ok((SELECT ok FROM e2b_assertions WHERE key = 'final_total_includes_selected_carrier_fee'), 'the charged amount is subtotal + the selected offer''s own quoted fee, server-computed and tied to that exact offer');
SELECT ok((SELECT ok FROM e2b_assertions WHERE key = 'snapshot_freezes_subtotal_and_delivery_fee'), 'SNAPSHOT: payment_attempts freezes the subtotal and delivery-fee components separately at initiation time');
SELECT ok((SELECT ok FROM e2b_assertions WHERE key = 'double_charge_guard_still_enforced'), 'the double-charge guard still blocks a second concurrent initiate at this new trigger point');
SELECT ok((SELECT ok FROM e2b_assertions WHERE key = 'second_carrier_selection_blocked_during_unresolved_payment'), 'LOCK: a different carrier offer cannot be selected while an MTN payment attempt is unresolved');
SELECT ok((SELECT ok FROM e2b_assertions WHERE key = 'carrier_acceptance_blocked_before_payment'), 'accept_marketplace_offer is blocked with payment_not_confirmed until the mtn_momo order is paid');
SELECT ok((SELECT ok FROM e2b_assertions WHERE key = 'mtn_success_marks_order_paid'), 'a successful MTN result marks the order paid');
SELECT ok((SELECT ok FROM e2b_assertions WHERE key = 'healthy_margin_no_anomaly_flag'), 'a provider fee within available commission does not set margin_anomaly');
SELECT ok((SELECT ok FROM e2b_assertions WHERE key = 'second_carrier_selection_blocked_after_successful_payment'), 'LOCK: a different carrier offer cannot be selected after a successful payment, even before carrier acceptance');
SELECT ok((SELECT ok FROM e2b_assertions WHERE key = 'order_marked_paid_exactly_once'), 'a duplicate finalize_successful_payment_attempt call is a safe no-op — order marked paid exactly once');
SELECT ok((SELECT ok FROM e2b_assertions WHERE key = 'carrier_accepts_after_payment'), 'the carrier can accept and a real delivery is created once payment is confirmed');
SELECT ok((SELECT ok FROM e2b_assertions WHERE key = 'amount_to_collect_zero_for_prepaid_order'), 'BUG FIX: amount_to_collect_lrd_cents is 0 for a prepaid MTN order — a rider is never told to collect cash again for money already charged electronically');
SELECT ok((SELECT ok FROM e2b_assertions WHERE key = 'carrier_acceptance_uses_frozen_delivery_fee'), 'carrier acceptance after successful payment consumes exactly the frozen delivery fee used in the charge');
SELECT ok((SELECT ok FROM e2b_assertions WHERE key = 'ledger_balances'), 'the recognized ledger event balances (debits = credits)');
SELECT ok((SELECT ok FROM e2b_assertions WHERE key = 'provider_clearing_net_is_gross_minus_fee'), 'provider_clearing nets to gross minus the provider fee, matching what WinAggregator actually credited');
SELECT ok((SELECT ok FROM e2b_assertions WHERE key = 'vendor_payable_present_and_carrier_payable_present'), 'both the vendor and the carrier legs are recognized in the same event');
SELECT ok((SELECT ok FROM e2b_assertions WHERE key = 'platform_revenue_is_full_commission_untouched_by_fee'), 'platform_revenue equals exactly the fee-rules commission, never reduced by the provider fee');
SELECT ok((SELECT ok FROM e2b_assertions WHERE key = 'processing_expense_equals_full_provider_fee'), 'payment_processing_expense records the FULL provider fee as a dedicated cost, not capped and not blended into platform_revenue');
SELECT ok((SELECT ok FROM e2b_assertions WHERE key = 'exactly_one_recognition_event_after_acceptance'), 'exactly one mtn_momo_collected financial event exists after carrier acceptance — no duplicate recognition');
SELECT ok((SELECT ok FROM e2b_assertions WHERE key = 'order_completed_after_full_lifecycle'), 'the order reaches fulfillment_status completed after the full rider lifecycle');
SELECT ok((SELECT ok FROM e2b_assertions WHERE key = 'still_exactly_one_recognition_event_after_full_lifecycle'), 'DUPLICATION PROOF: still exactly one mtn_momo_collected event after carrier selection -> MTN success -> carrier acceptance -> rider -> delivered -> completed');

-- =============================================================================
-- BLOCK 2 — High provider fee: accounting anomaly, NEVER payment uncertainty.
-- =============================================================================
DO $$
DECLARE
  v_admin UUID; v_vendor UUID; v_vendor_owner UUID;
  v_carrier_a UUID; v_carrier_a_owner UUID; v_carrier_b UUID; v_carrier_b_owner UUID;
  v_customer UUID; v_order public.commerce_orders; v_order_id UUID; v_offer_a_id UUID; v_offer_b_id UUID;
  v_attempt public.payment_attempts;
  v_ledger RECORD;
  v_snapshot JSONB;
  v_admin_row RECORD;
BEGIN
  -- No vendor-specific commerce_fee_rules override here: the vendor leg
  -- uses the platform-wide zero_commission default (0), and the carrier
  -- leg uses marketplace_fee_rules' 10% platform default on a 100-cent
  -- offer (10) — so available commission is only 10. A provider fee of 50,
  -- while internally consistent and definitively evidence of a real
  -- successful collection, comfortably exceeds it.
  SELECT * INTO v_admin, v_vendor, v_vendor_owner, v_carrier_a, v_carrier_a_owner, v_carrier_b, v_carrier_b_owner, v_customer, v_order_id, v_offer_a_id, v_offer_b_id
  FROM pg_temp.setup_mtn_order('E2C', 100, 100, 100);
  SELECT * INTO v_order FROM public.commerce_orders WHERE id = v_order_id;

  PERFORM set_config('request.jwt.claim.sub', v_customer::text, true);
  PERFORM public.select_commerce_delivery_offer(v_order.id, v_offer_a_id);
  v_attempt := public.initiate_commerce_order_mtn_payment(v_order.id, '0770229690');
  PERFORM set_config('request.jwt.claim.sub', '', true);

  v_attempt := public.mark_payment_attempt_requesting(v_attempt.id);
  -- gross=200 matches attempt.gross_amount_cents exactly; fee=50, net=150
  -- (200-50=150, internally consistent, all non-negative).
  v_attempt := public.record_payment_attempt_result(
    v_attempt.id, 'successful', 'SUCCESSFUL', 200, 'ref-1', 'fin-1', 200, 50, 150, NULL, NULL
  );

  CREATE TEMP TABLE e2c_assertions (key TEXT PRIMARY KEY, ok BOOLEAN);

  INSERT INTO e2c_assertions VALUES (
    'high_fee_still_marks_successful',
    v_attempt.state = 'successful'
  );
  INSERT INTO e2c_assertions VALUES ('high_fee_sets_margin_anomaly', v_attempt.margin_anomaly = true);

  SELECT * INTO v_order FROM public.commerce_orders WHERE id = v_order.id;
  INSERT INTO e2c_assertions VALUES ('order_paid_despite_high_fee', v_order.payment_status = 'paid');

  SELECT
    SUM(amount_lrd_cents) FILTER (WHERE account_type = 'vendor_payable' AND direction = 'credit') AS vendor_payable,
    SUM(amount_lrd_cents) FILTER (WHERE account_type = 'carrier_payable' AND direction = 'credit') AS carrier_payable,
    COALESCE(SUM(amount_lrd_cents) FILTER (WHERE account_type = 'platform_revenue' AND direction = 'credit'), 0)
      - COALESCE(SUM(amount_lrd_cents) FILTER (WHERE account_type = 'platform_revenue' AND direction = 'debit'), 0) AS platform_revenue_net,
    SUM(amount_lrd_cents) FILTER (WHERE account_type = 'payment_processing_expense' AND direction = 'debit') AS processing_expense,
    SUM(amount_lrd_cents) FILTER (WHERE direction = 'debit') AS debits,
    SUM(amount_lrd_cents) FILTER (WHERE direction = 'credit') AS credits
  INTO v_ledger
  FROM public.commerce_ledger_entries e JOIN public.commerce_financial_events ev ON ev.id = e.financial_event_id
  WHERE ev.commerce_order_id = v_order.id;

  INSERT INTO e2c_assertions VALUES ('high_fee_ledger_still_balances', v_ledger.debits = v_ledger.credits);
  -- Vendor split at 0% commission: vendor_payable = full 100 subtotal.
  INSERT INTO e2c_assertions VALUES ('vendor_payable_unchanged_by_fee', v_ledger.vendor_payable = 100);
  -- Carrier split at 10% commission on a 100-cent offer: carrier_payable = 90.
  INSERT INTO e2c_assertions VALUES ('carrier_payable_unchanged_by_fee', v_ledger.carrier_payable = 90);
  -- Platform commission is exactly what the fee rules produced (0 + 10),
  -- never reduced to absorb the fee.
  INSERT INTO e2c_assertions VALUES ('platform_revenue_unreduced_by_high_fee', v_ledger.platform_revenue_net = 10);
  -- The FULL fee (50) is recorded as an expense, not capped at the 10 of
  -- available commission.
  INSERT INTO e2c_assertions VALUES ('full_provider_fee_recorded_as_expense', v_ledger.processing_expense = 50);

  SELECT snapshot INTO v_snapshot FROM public.commerce_financial_events WHERE commerce_order_id = v_order.id AND event_type = 'mtn_momo_collected';
  INSERT INTO e2c_assertions VALUES (
    'negative_margin_represented_honestly',
    (v_snapshot ->> 'transaction_margin_lrd_cents')::INT = 10 - 50
    AND (v_snapshot ->> 'margin_anomaly')::BOOLEAN = true
  );

  -- Super admin can isolate this transaction via the margin-anomaly filter.
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  SELECT * INTO v_admin_row FROM public.admin_list_payment_attempts_page(NULL, NULL, 50, 0, true) WHERE id = v_attempt.id;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  INSERT INTO e2c_assertions VALUES ('admin_can_isolate_margin_anomalies', v_admin_row.id = v_attempt.id AND v_admin_row.margin_anomaly = true);
END;
$$;

SELECT ok((SELECT ok FROM e2c_assertions WHERE key = 'high_fee_still_marks_successful'), 'PAYMENT CERTAINTY: a definitively successful collection stays successful even when the provider fee exceeds platform commission');
SELECT ok((SELECT ok FROM e2c_assertions WHERE key = 'high_fee_sets_margin_anomaly'), 'the economic anomaly is recorded as margin_anomaly = true, not as payment uncertainty');
SELECT ok((SELECT ok FROM e2c_assertions WHERE key = 'order_paid_despite_high_fee'), 'the order is marked paid despite the unfavorable fee');
SELECT ok((SELECT ok FROM e2c_assertions WHERE key = 'high_fee_ledger_still_balances'), 'the ledger event still balances (debits = credits) even with a fee exceeding commission');
SELECT ok((SELECT ok FROM e2c_assertions WHERE key = 'vendor_payable_unchanged_by_fee'), 'vendor payable remains contractually correct regardless of the provider fee');
SELECT ok((SELECT ok FROM e2c_assertions WHERE key = 'carrier_payable_unchanged_by_fee'), 'carrier payable remains contractually correct regardless of the provider fee');
SELECT ok((SELECT ok FROM e2c_assertions WHERE key = 'platform_revenue_unreduced_by_high_fee'), 'platform revenue remains exactly what the Commerce fee rules produced, never silently reduced');
SELECT ok((SELECT ok FROM e2c_assertions WHERE key = 'full_provider_fee_recorded_as_expense'), 'the full provider fee is recorded as a payment_processing_expense, never capped at available commission');
SELECT ok((SELECT ok FROM e2c_assertions WHERE key = 'negative_margin_represented_honestly'), 'the resulting negative transaction margin is recorded honestly, never fabricated into a positive figure');
SELECT ok((SELECT ok FROM e2c_assertions WHERE key = 'admin_can_isolate_margin_anomalies'), 'a super admin can identify margin-anomaly transactions via admin_list_payment_attempts_page');

-- =============================================================================
-- BLOCK 3 — Malformed/inconsistent provider data still fails closed.
-- =============================================================================
DO $$
DECLARE
  v_admin UUID; v_vendor UUID; v_vendor_owner UUID;
  v_carrier_a UUID; v_carrier_a_owner UUID; v_carrier_b UUID; v_carrier_b_owner UUID;
  v_customer UUID; v_order public.commerce_orders; v_order_id UUID; v_offer_a_id UUID; v_offer_b_id UUID;
  v_attempt_1 public.payment_attempts;
  v_attempt_2 public.payment_attempts;
  v_order_2 public.commerce_orders; v_order_id_2 UUID;
BEGIN
  SELECT * INTO v_admin, v_vendor, v_vendor_owner, v_carrier_a, v_carrier_a_owner, v_carrier_b, v_carrier_b_owner, v_customer, v_order_id, v_offer_a_id, v_offer_b_id
  FROM pg_temp.setup_mtn_order('E2G', 20000, 1500, 2000);
  SELECT * INTO v_order FROM public.commerce_orders WHERE id = v_order_id;

  CREATE TEMP TABLE e2g_assertions (key TEXT PRIMARY KEY, ok BOOLEAN);

  -- Sub-case A: internally inconsistent gross/fee/net (200 - 50 <> 100).
  PERFORM set_config('request.jwt.claim.sub', v_customer::text, true);
  PERFORM public.select_commerce_delivery_offer(v_order.id, v_offer_a_id);
  v_attempt_1 := public.initiate_commerce_order_mtn_payment(v_order.id, '0770229690');
  PERFORM set_config('request.jwt.claim.sub', '', true);
  v_attempt_1 := public.mark_payment_attempt_requesting(v_attempt_1.id);
  v_attempt_1 := public.record_payment_attempt_result(
    v_attempt_1.id, 'successful', 'SUCCESSFUL', 200, 'ref-1', 'fin-1', 21500, 800, 5000, NULL, NULL
  );
  INSERT INTO e2g_assertions VALUES (
    'inconsistent_figures_fail_closed',
    v_attempt_1.state = 'unknown' AND v_attempt_1.failure_category = 'inconsistent_provider_figures'
  );
  SELECT * INTO v_order FROM public.commerce_orders WHERE id = v_order.id;
  INSERT INTO e2g_assertions VALUES ('inconsistent_figures_order_not_paid', v_order.payment_status = 'pending_payment');

  -- Sub-case B: gross doesn't match what DeliveryOS authoritatively
  -- intended to collect — internally consistent (25000-800=24200) but the
  -- wrong amount entirely, so it cannot be trusted as evidence for THIS
  -- charge. A second order/offer/attempt, since sub-case A's order is now
  -- stuck 'unknown' (correctly — no second attempt permitted while locked).
  SELECT * INTO v_admin, v_vendor, v_vendor_owner, v_carrier_a, v_carrier_a_owner, v_carrier_b, v_carrier_b_owner, v_customer, v_order_id_2, v_offer_a_id, v_offer_b_id
  FROM pg_temp.setup_mtn_order('E2H', 20000, 1500, 2000);
  SELECT * INTO v_order_2 FROM public.commerce_orders WHERE id = v_order_id_2;

  PERFORM set_config('request.jwt.claim.sub', v_customer::text, true);
  PERFORM public.select_commerce_delivery_offer(v_order_2.id, v_offer_a_id);
  v_attempt_2 := public.initiate_commerce_order_mtn_payment(v_order_2.id, '0770229690');
  PERFORM set_config('request.jwt.claim.sub', '', true);
  v_attempt_2 := public.mark_payment_attempt_requesting(v_attempt_2.id);
  v_attempt_2 := public.record_payment_attempt_result(
    v_attempt_2.id, 'successful', 'SUCCESSFUL', 200, 'ref-1', 'fin-1', 25000, 800, 24200, NULL, NULL
  );
  INSERT INTO e2g_assertions VALUES (
    'gross_mismatch_fails_closed',
    v_attempt_2.state = 'unknown' AND v_attempt_2.failure_category = 'inconsistent_provider_figures'
  );
  SELECT * INTO v_order_2 FROM public.commerce_orders WHERE id = v_order_2.id;
  INSERT INTO e2g_assertions VALUES ('gross_mismatch_order_not_paid', v_order_2.payment_status = 'pending_payment');
END;
$$;

SELECT ok((SELECT ok FROM e2g_assertions WHERE key = 'inconsistent_figures_fail_closed'), 'internally inconsistent provider gross/fee/net fails closed to unknown, not successful');
SELECT ok((SELECT ok FROM e2g_assertions WHERE key = 'inconsistent_figures_order_not_paid'), 'the order is not marked paid when provider figures are inconsistent');
SELECT ok((SELECT ok FROM e2g_assertions WHERE key = 'gross_mismatch_fails_closed'), 'a provider-reported gross that does not match the authoritative amount DeliveryOS intended to collect fails closed to unknown');
SELECT ok((SELECT ok FROM e2g_assertions WHERE key = 'gross_mismatch_order_not_paid'), 'the order is not marked paid when the provider gross does not match what was charged');

-- =============================================================================
-- BLOCK 4 — Offer-expiry sweep respects the payment lock.
-- =============================================================================
DO $$
DECLARE
  v_admin UUID; v_vendor UUID; v_vendor_owner UUID;
  v_carrier_a UUID; v_carrier_a_owner UUID; v_carrier_b UUID; v_carrier_b_owner UUID;
  v_customer UUID; v_order public.commerce_orders; v_order_id UUID; v_offer_a_id UUID; v_offer_b_id UUID;
  v_attempt public.payment_attempts;
  v_offer_status public.delivery_offer_status;
BEGIN
  CREATE TEMP TABLE e2i_assertions (key TEXT PRIMARY KEY, ok BOOLEAN);

  -- Sub-case A: 'pending' attempt survives the sweep.
  SELECT * INTO v_admin, v_vendor, v_vendor_owner, v_carrier_a, v_carrier_a_owner, v_carrier_b, v_carrier_b_owner, v_customer, v_order_id, v_offer_a_id, v_offer_b_id
  FROM pg_temp.setup_mtn_order('E2I1', 20000, 1500, 2000);
  SELECT * INTO v_order FROM public.commerce_orders WHERE id = v_order_id;
  PERFORM set_config('request.jwt.claim.sub', v_customer::text, true);
  PERFORM public.select_commerce_delivery_offer(v_order.id, v_offer_a_id);
  v_attempt := public.initiate_commerce_order_mtn_payment(v_order.id, '0770229690');
  PERFORM set_config('request.jwt.claim.sub', '', true);
  v_attempt := public.mark_payment_attempt_requesting(v_attempt.id);
  v_attempt := public.record_payment_attempt_result(v_attempt.id, 'pending', 'PENDING', 202, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
  -- Force the offer's deadline into the past — without the lock this would
  -- be swept.
  UPDATE public.delivery_offers SET expires_at = now() - interval '1 hour' WHERE id = v_offer_a_id;
  PERFORM public.run_scheduled_maintenance_jobs();
  SELECT status INTO v_offer_status FROM public.delivery_offers WHERE id = v_offer_a_id;
  INSERT INTO e2i_assertions VALUES ('pending_payment_offer_survives_sweep', v_offer_status = 'pending');

  -- Sub-case B: 'unknown' attempt survives the sweep.
  SELECT * INTO v_admin, v_vendor, v_vendor_owner, v_carrier_a, v_carrier_a_owner, v_carrier_b, v_carrier_b_owner, v_customer, v_order_id, v_offer_a_id, v_offer_b_id
  FROM pg_temp.setup_mtn_order('E2I2', 20000, 1500, 2000);
  SELECT * INTO v_order FROM public.commerce_orders WHERE id = v_order_id;
  PERFORM set_config('request.jwt.claim.sub', v_customer::text, true);
  PERFORM public.select_commerce_delivery_offer(v_order.id, v_offer_a_id);
  v_attempt := public.initiate_commerce_order_mtn_payment(v_order.id, '0770229690');
  PERFORM set_config('request.jwt.claim.sub', '', true);
  v_attempt := public.mark_payment_attempt_requesting(v_attempt.id);
  -- Backdate requested_at so the sweep's stuck-threshold actually fires —
  -- sweep_stuck_payment_attempts floors its threshold at 1 minute, so a
  -- freshly-created 'requesting' row would never qualify otherwise.
  UPDATE public.payment_attempts SET requested_at = now() - interval '10 minutes' WHERE id = v_attempt.id;
  PERFORM public.sweep_stuck_payment_attempts(3);
  UPDATE public.delivery_offers SET expires_at = now() - interval '1 hour' WHERE id = v_offer_a_id;
  PERFORM public.run_scheduled_maintenance_jobs();
  SELECT status INTO v_offer_status FROM public.delivery_offers WHERE id = v_offer_a_id;
  INSERT INTO e2i_assertions VALUES ('unknown_payment_offer_survives_sweep', v_offer_status = 'pending');

  -- Control: no payment attempt at all -> the sweep DOES expire a stale offer normally.
  SELECT * INTO v_admin, v_vendor, v_vendor_owner, v_carrier_a, v_carrier_a_owner, v_carrier_b, v_carrier_b_owner, v_customer, v_order_id, v_offer_a_id, v_offer_b_id
  FROM pg_temp.setup_mtn_order('E2I3', 20000, 1500, 2000);
  UPDATE public.delivery_offers SET expires_at = now() - interval '1 hour' WHERE id = v_offer_a_id;
  PERFORM public.run_scheduled_maintenance_jobs();
  SELECT status INTO v_offer_status FROM public.delivery_offers WHERE id = v_offer_a_id;
  INSERT INTO e2i_assertions VALUES ('unlocked_stale_offer_still_expires_normally', v_offer_status = 'expired');
END;
$$;

SELECT ok((SELECT ok FROM e2i_assertions WHERE key = 'pending_payment_offer_survives_sweep'), 'an offer locked by a PENDING payment attempt survives the routine expiry sweep no matter how stale expires_at is');
SELECT ok((SELECT ok FROM e2i_assertions WHERE key = 'unknown_payment_offer_survives_sweep'), 'an offer locked by an UNKNOWN payment attempt survives the routine expiry sweep');
SELECT ok((SELECT ok FROM e2i_assertions WHERE key = 'unlocked_stale_offer_still_expires_normally'), 'control: a stale offer with no active payment attempt still expires normally — the lock is specific, not a general sweep regression');

-- =============================================================================
-- BLOCK 5 — Definitively failed payment releases the financial lock.
-- =============================================================================
DO $$
DECLARE
  v_admin UUID; v_vendor UUID; v_vendor_owner UUID;
  v_carrier_a UUID; v_carrier_a_owner UUID; v_carrier_b UUID; v_carrier_b_owner UUID;
  v_customer UUID; v_order public.commerce_orders; v_order_id UUID; v_offer_a_id UUID; v_offer_b_id UUID;
  v_attempt public.payment_attempts;
  v_reselected JSONB;
BEGIN
  SELECT * INTO v_admin, v_vendor, v_vendor_owner, v_carrier_a, v_carrier_a_owner, v_carrier_b, v_carrier_b_owner, v_customer, v_order_id, v_offer_a_id, v_offer_b_id
  FROM pg_temp.setup_mtn_order('E2J', 20000, 1500, 2000);
  SELECT * INTO v_order FROM public.commerce_orders WHERE id = v_order_id;

  PERFORM set_config('request.jwt.claim.sub', v_customer::text, true);
  PERFORM public.select_commerce_delivery_offer(v_order.id, v_offer_a_id);
  v_attempt := public.initiate_commerce_order_mtn_payment(v_order.id, '0770229690');
  PERFORM set_config('request.jwt.claim.sub', '', true);
  v_attempt := public.mark_payment_attempt_requesting(v_attempt.id);
  v_attempt := public.record_payment_attempt_result(
    v_attempt.id, 'failed', 'DECLINED', 400, 'ref-1', NULL, NULL, NULL, NULL, 'declined', 'Insufficient funds'
  );

  CREATE TEMP TABLE e2j_assertions (key TEXT PRIMARY KEY, ok BOOLEAN);
  INSERT INTO e2j_assertions VALUES ('failed_attempt_recorded', v_attempt.state = 'failed');

  -- The lock releases: the customer can now select a DIFFERENT carrier.
  PERFORM set_config('request.jwt.claim.sub', v_customer::text, true);
  v_reselected := public.select_commerce_delivery_offer(v_order.id, v_offer_b_id);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  INSERT INTO e2j_assertions VALUES ('failed_payment_releases_lock_for_reselection', (v_reselected ->> 'id')::UUID = v_offer_b_id);

  -- And a fresh payment attempt (new externalID) can be created for it.
  PERFORM set_config('request.jwt.claim.sub', v_customer::text, true);
  v_attempt := public.initiate_commerce_order_mtn_payment(v_order.id, '0770229690');
  PERFORM set_config('request.jwt.claim.sub', '', true);
  INSERT INTO e2j_assertions VALUES ('new_attempt_after_failure_uses_new_offer', v_attempt.selected_offer_id = v_offer_b_id AND v_attempt.gross_amount_cents = 20000 + 2000);
END;
$$;

SELECT ok((SELECT ok FROM e2j_assertions WHERE key = 'failed_attempt_recorded'), 'a definitively failed payment attempt is recorded as failed');
SELECT ok((SELECT ok FROM e2j_assertions WHERE key = 'failed_payment_releases_lock_for_reselection'), 'a failed payment releases the financial lock, allowing the customer to select a different carrier');
SELECT ok((SELECT ok FROM e2j_assertions WHERE key = 'new_attempt_after_failure_uses_new_offer'), 'a fresh payment attempt after a failure correctly prices the newly selected carrier');

-- =============================================================================
-- BLOCK 6 — COD regression: completely unaffected by any of the above.
-- =============================================================================
DO $$
DECLARE
  v_admin UUID; v_vendor UUID; v_vendor_owner UUID;
  v_carrier UUID; v_carrier_owner UUID;
  v_customer UUID; v_product UUID; v_result RECORD; v_cart UUID;
  v_order public.commerce_orders; v_offer_id UUID; v_delivery public.deliveries;
  v_offer_expires_before TIMESTAMPTZ; v_offer_expires_after TIMESTAMPTZ;
BEGIN
  v_admin := pg_temp.make_user('E2D Admin');
  UPDATE public.profiles SET is_super_admin = true WHERE id = v_admin;
  SELECT company_id, owner_id INTO v_vendor, v_vendor_owner FROM pg_temp.make_company('E2D Vendor', 'merchant', v_admin);
  SELECT company_id, owner_id INTO v_carrier, v_carrier_owner FROM pg_temp.make_company('E2D Carrier', 'logistics_provider', v_admin);
  v_customer := pg_temp.make_user('E2D Customer');
  UPDATE public.companies SET address = '1 Test Street, Monrovia' WHERE id = v_vendor;

  PERFORM set_config('request.jwt.claim.sub', v_vendor_owner::text, true);
  PERFORM public.upsert_store_profile(jsonb_build_object('company_id', v_vendor, 'slug', 'e2d-vendor', 'display_name', 'E2D Vendor', 'allow_cash_on_delivery', true));
  v_result := public.upsert_product(jsonb_build_object('company_id', v_vendor, 'name', 'E2D Product', 'price_lrd_cents', 30000, 'status', 'active'));
  v_product := (v_result).id;
  PERFORM set_config('request.jwt.claim.sub', '', true);

  PERFORM set_config('request.jwt.claim.sub', v_carrier_owner::text, true);
  PERFORM public.upsert_provider_marketplace_profile(jsonb_build_object('company_id', v_carrier, 'marketplace_enabled', true, 'accepting_jobs', true, 'minimum_delivery_fee_lrd_cents', 1800));
  PERFORM set_config('request.jwt.claim.sub', '', true);

  PERFORM set_config('request.jwt.claim.sub', v_customer::text, true);
  v_cart := (public.get_or_create_cart(v_vendor)).id;
  PERFORM public.add_cart_item(v_cart, v_product, 1, '[]'::JSONB);
  v_order := public.submit_commerce_order(v_cart, 'E2D Customer', 'Addr', 'Area', NULL, NULL, NULL, 'cod');
  PERFORM set_config('request.jwt.claim.sub', '', true);

  PERFORM set_config('request.jwt.claim.sub', v_vendor_owner::text, true);
  PERFORM public.vendor_accept_commerce_order(v_order.id);
  PERFORM public.vendor_mark_order_preparing(v_order.id);
  v_order := public.vendor_mark_order_ready(v_order.id);
  PERFORM public.request_commerce_order_delivery(v_order.id);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  SELECT * INTO v_order FROM public.commerce_orders WHERE id = v_order.id;

  SELECT o.id INTO v_offer_id FROM public.delivery_offers o WHERE o.delivery_request_id = v_order.delivery_request_id AND o.provider_company_id = v_carrier;
  UPDATE public.delivery_offers SET expires_at = now() + interval '2 minutes' WHERE id = v_offer_id;
  SELECT expires_at INTO v_offer_expires_before FROM public.delivery_offers WHERE id = v_offer_id;

  PERFORM set_config('request.jwt.claim.sub', v_customer::text, true);
  PERFORM public.select_commerce_delivery_offer(v_order.id, v_offer_id);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT expires_at INTO v_offer_expires_after FROM public.delivery_offers WHERE id = v_offer_id;

  -- No payment gate, no financial lock (COD never creates payment_attempts)
  -- for COD's own carrier acceptance — unchanged.
  PERFORM set_config('request.jwt.claim.sub', v_carrier_owner::text, true);
  PERFORM public.accept_marketplace_offer(v_offer_id, v_carrier);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT * INTO v_order FROM public.commerce_orders WHERE id = v_order.id;
  SELECT * INTO v_delivery FROM public.deliveries WHERE id = v_order.delivery_id;

  CREATE TEMP TABLE e2d_assertions (key TEXT PRIMARY KEY, ok BOOLEAN);
  INSERT INTO e2d_assertions VALUES ('cod_offer_reservation_not_extended', v_offer_expires_after = v_offer_expires_before);
  INSERT INTO e2d_assertions VALUES ('cod_carrier_accepts_without_payment_gate', v_delivery.id IS NOT NULL AND v_order.payment_status = 'pending_payment');
  INSERT INTO e2d_assertions VALUES ('cod_amount_to_collect_is_full_amount_unchanged', v_delivery.amount_to_collect_lrd_cents = 30000 + 1800);
END;
$$;

SELECT ok((SELECT ok FROM e2d_assertions WHERE key = 'cod_offer_reservation_not_extended'), 'COD regression: an offer selected for a COD order does NOT get the mtn_momo reservation extension');
SELECT ok((SELECT ok FROM e2d_assertions WHERE key = 'cod_carrier_accepts_without_payment_gate'), 'COD regression: carrier acceptance still requires no payment gate, order genuinely stays pending_payment through acceptance');
SELECT ok((SELECT ok FROM e2d_assertions WHERE key = 'cod_amount_to_collect_is_full_amount_unchanged'), 'COD regression: amount_to_collect_lrd_cents is still the full subtotal + delivery fee, unaffected by the MTN-specific zeroing fix');

SELECT * FROM finish();
ROLLBACK;
