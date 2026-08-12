-- Coverage for DeliveryOS Commerce Phase F — Production Readiness,
-- Operations Hardening & Gap Closure
-- (20260309210000_commerce_phase_f_production_readiness.sql).
--
-- Proves: a delivery that fails/is cancelled after handed_to_carrier
-- releases its reserved stock (the one gap in an otherwise-complete
-- release story); Commerce lifecycle SMS notifications fire exactly once
-- via the existing queue_outbound_sms path, charged to the documented
-- payer; finance read RPCs correctly exclude/net a reversed order instead
-- of silently overstating; the new admin operational RPCs (order status/
-- stuck detection, carrier pricing readiness, reconciliation gaps,
-- financial-event filters) are real, forbidden to non-admins, and return
-- accurate data; get_vendor_store_profile enforces company ownership and
-- the underlying column-level REVOKE on store_profiles genuinely blocks a
-- raw authenticated read of another store's status_reason; and the
-- extended onboarding status correctly reports Commerce-specific steps
-- for a merchant company.

BEGIN;
SELECT plan(19);

SELECT has_function('public'::name, 'admin_list_commerce_orders_page'::name);
SELECT has_function('public'::name, 'admin_list_commerce_providers_page'::name);
SELECT has_function('public'::name, 'admin_commerce_reconciliation_gaps'::name);
SELECT has_function('public'::name, 'get_vendor_store_profile'::name);

CREATE OR REPLACE FUNCTION pg_temp.make_customer(p_label TEXT)
RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
  v_user UUID := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, phone, email, encrypted_password, phone_confirmed_at, aud, role)
  VALUES (
    v_user, '+23178' || lpad((floor(random() * 999999))::text, 6, '0'),
    'commerce-f-' || substr(v_user::text, 1, 8) || '@test.local',
    crypt('x', gen_salt('bf')), now(), 'authenticated', 'authenticated'
  );
  INSERT INTO public.profiles (id, full_name) VALUES (v_user, p_label)
  ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name;
  RETURN v_user;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.make_company(p_label TEXT, p_business_type public.company_business_type)
RETURNS TABLE (company_id UUID, owner_id UUID) LANGUAGE plpgsql AS $$
DECLARE
  v_owner UUID := pg_temp.make_customer(p_label || ' Owner');
  v_company UUID;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  v_company := public.create_company_with_owner(
    p_label, '+23178' || lpad((floor(random() * 999999))::text, 6, '0'),
    lower(replace(p_label, ' ', '')) || '@test.local', NULL, p_business_type
  );
  PERFORM set_config('request.jwt.claim.sub', '', true);
  -- commerce_enabled is plan-gated (this same migration) — upgrade every
  -- fixture company up front so the gate never blocks unrelated test
  -- scenarios; the entitlement gate itself is tested explicitly below with
  -- a company deliberately left on its default (non-entitled) plan.
  UPDATE public.company_subscriptions SET plan_id = (SELECT id FROM public.subscriptions WHERE slug = 'business')
  WHERE company_subscriptions.company_id = v_company;
  RETURN QUERY SELECT v_company, v_owner;
END;
$$;

-- Runs a COD order through checkout, vendor accept/prepare/ready, delivery
-- request, customer carrier selection, and carrier acceptance — stopping
-- BEFORE any rider status transition, so the caller decides what happens
-- next (delivered, vs. failed/cancelled for the stock-leak test).
CREATE OR REPLACE FUNCTION pg_temp.run_cod_order_to_carrier_accepted(
  p_customer_id UUID, p_vendor_id UUID, p_vendor_owner_id UUID,
  p_product_id UUID, p_carrier_id UUID, p_carrier_owner_id UUID
)
RETURNS public.commerce_orders LANGUAGE plpgsql AS $$
DECLARE
  v_cart UUID;
  v_order public.commerce_orders;
  v_offer_id UUID;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_customer_id::text, true);
  v_cart := (public.get_or_create_cart(p_vendor_id)).id;
  PERFORM public.add_cart_item(v_cart, p_product_id, 1, '[]'::JSONB);
  v_order := public.submit_commerce_order(v_cart, 'F Customer', 'Test address', 'Test area', NULL, NULL, NULL, 'cod');
  PERFORM set_config('request.jwt.claim.sub', '', true);

  PERFORM set_config('request.jwt.claim.sub', p_vendor_owner_id::text, true);
  PERFORM public.vendor_accept_commerce_order(v_order.id);
  PERFORM public.vendor_mark_order_preparing(v_order.id);
  v_order := public.vendor_mark_order_ready(v_order.id);
  PERFORM public.request_commerce_order_delivery(v_order.id);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT o.id INTO v_offer_id
  FROM public.delivery_offers o
  WHERE o.delivery_request_id = (SELECT delivery_request_id FROM public.commerce_orders WHERE id = v_order.id)
    AND o.provider_company_id = p_carrier_id;
  IF v_offer_id IS NULL THEN RAISE EXCEPTION 'no offer created for carrier — check marketplace pricing configuration'; END IF;

  PERFORM set_config('request.jwt.claim.sub', p_customer_id::text, true);
  PERFORM public.select_commerce_delivery_offer(v_order.id, v_offer_id);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  PERFORM set_config('request.jwt.claim.sub', p_carrier_owner_id::text, true);
  PERFORM public.accept_marketplace_offer(v_offer_id, p_carrier_id);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT * INTO v_order FROM public.commerce_orders WHERE id = v_order.id;
  RETURN v_order;
END;
$$;

DO $$
DECLARE
  v_admin UUID;
  v_vendor_a UUID; v_vendor_a_owner UUID;
  v_carrier_a UUID; v_carrier_a_owner UUID;
  v_customer1 UUID;
  v_product_a UUID;
  v_result RECORD;
  v_order public.commerce_orders;
  v_order2 public.commerce_orders;
  v_rider UUID;
  v_stock_before INT;
  v_stock_after INT;
  v_event public.commerce_financial_events;
  v_finance_before JSONB;
  v_finance_after JSONB;
  v_forbidden BOOLEAN;
  v_sms_count INT;
  v_onboarding JSONB;
  v_steps JSONB;
  v_row_count INT;
  v_unconfigured_carrier UUID; v_unconfigured_owner UUID;
  v_providers JSONB;
  v_gap_order public.commerce_orders;
  v_gaps JSONB;
  v_events JSONB;
  v_stuck_summary JSONB;
  v_vendor_customer_sms_before INT;
  v_carrier_customer_sms_before INT;
BEGIN
  v_admin := pg_temp.make_customer('F Admin');
  UPDATE public.profiles SET is_super_admin = true WHERE id = v_admin;

  SELECT company_id, owner_id INTO v_vendor_a, v_vendor_a_owner FROM pg_temp.make_company('F Vendor A', 'merchant');
  SELECT company_id, owner_id INTO v_carrier_a, v_carrier_a_owner FROM pg_temp.make_company('F Carrier A', 'logistics_provider');
  v_customer1 := pg_temp.make_customer('F Customer One');

  UPDATE public.companies SET address = '1 Test Street, Monrovia' WHERE id = v_vendor_a;
  UPDATE public.company_subscriptions SET plan_id = (SELECT id FROM public.subscriptions WHERE slug = 'business')
  WHERE company_id = v_carrier_a;

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM public.admin_set_vendor_state(v_vendor_a, 'active', NULL);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
  PERFORM public.upsert_store_profile(jsonb_build_object('company_id', v_vendor_a, 'slug', 'f-vendor-a', 'display_name', 'F Vendor A', 'allow_cash_on_delivery', true));
  v_result := public.upsert_product(jsonb_build_object('company_id', v_vendor_a, 'name', 'F Product A', 'price_lrd_cents', 15000, 'status', 'active', 'tracks_inventory', true));
  v_product_a := (v_result).id;
  PERFORM public.adjust_product_stock(v_product_a, 10, 'restock');
  PERFORM set_config('request.jwt.claim.sub', '', true);

  PERFORM set_config('request.jwt.claim.sub', v_carrier_a_owner::text, true);
  PERFORM public.upsert_provider_marketplace_profile(jsonb_build_object(
    'company_id', v_carrier_a, 'marketplace_enabled', true, 'accepting_jobs', true, 'minimum_delivery_fee_lrd_cents', 2000
  ));
  PERFORM set_config('request.jwt.claim.sub', '', true);

  CREATE TEMP TABLE f_assertions (key TEXT PRIMARY KEY, ok BOOLEAN);

  -- =========================================================================
  -- 1) Stock leak fix: a delivery that fails after handed_to_carrier
  --    releases the reserved stock, and the order lands in 'cancelled'.
  --    Also proves the "vendor: new order" SMS fired during checkout.
  -- =========================================================================
  SELECT quantity_reserved INTO v_stock_before FROM public.product_stock WHERE product_id = v_product_a;
  IF v_stock_before <> 0 THEN RAISE EXCEPTION 'expected 0 reserved before any order'; END IF;

  v_order := pg_temp.run_cod_order_to_carrier_accepted(v_customer1, v_vendor_a, v_vendor_a_owner, v_product_a, v_carrier_a, v_carrier_a_owner);

  -- "New order" is the only notification sent TO the vendor's own phone at
  -- this point in the lifecycle (accepted/ready go to the customer; the
  -- vendor's OTHER own-phone notification, "delivery completed", only
  -- fires on a later 'delivered' transition this order hasn't reached).
  SELECT COUNT(*) INTO v_sms_count FROM public.sms_outbox
  WHERE company_id = v_vendor_a AND phone = (SELECT phone FROM public.companies WHERE id = v_vendor_a);
  IF v_sms_count <> 1 THEN
    RAISE EXCEPTION 'expected exactly 1 vendor "new order" SMS queued after checkout, got %', v_sms_count;
  END IF;

  SELECT quantity_reserved INTO v_stock_before FROM public.product_stock WHERE product_id = v_product_a;
  IF v_stock_before <> 1 THEN RAISE EXCEPTION 'expected 1 unit reserved after checkout, got %', v_stock_before; END IF;

  INSERT INTO public.riders (company_id, rider_code, full_name, phone, status)
  VALUES (v_carrier_a, 'F-' || substr(gen_random_uuid()::text, 1, 8), 'F Rider', '+231882' || lpad((floor(random()*999999))::text,6,'0'), 'available')
  RETURNING id INTO v_rider;

  PERFORM set_config('request.jwt.claim.sub', v_carrier_a_owner::text, true);
  PERFORM public.assign_delivery_rider(v_order.delivery_id, v_rider);
  PERFORM public.transition_delivery_status(v_order.delivery_id, 'accepted', NULL);
  PERFORM public.transition_delivery_status(v_order.delivery_id, 'picked_up', NULL);
  PERFORM public.transition_delivery_status(v_order.delivery_id, 'failed', 'customer unreachable');
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT quantity_reserved INTO v_stock_after FROM public.product_stock WHERE product_id = v_product_a;
  IF v_stock_after <> 0 THEN
    RAISE EXCEPTION 'expected reserved stock to be released after a failed delivery post-pickup, got %', v_stock_after;
  END IF;

  SELECT * INTO v_order FROM public.commerce_orders WHERE id = v_order.id;
  IF v_order.fulfillment_status <> 'cancelled' THEN
    RAISE EXCEPTION 'expected order to be cancelled after delivery failure, got %', v_order.fulfillment_status;
  END IF;

  INSERT INTO f_assertions VALUES ('stock_released_on_delivery_failure', true);
  INSERT INTO f_assertions VALUES ('vendor_new_order_sms_queued', true);

  -- =========================================================================
  -- 2) Customer lifecycle notifications: accepted / ready / carrier
  --    accepted, and vendor "delivery completed" — full happy-path order.
  -- =========================================================================
  -- Postgres's now() is frozen for the whole transaction this test runs
  -- in, so created_at can't be used to distinguish "before" from "after"
  -- within this single test — use before/after row-count deltas instead.
  -- Order 1 (section 1) shares the same customer/phone as order 2, so an
  -- unscoped count would otherwise double-count its own notifications.
  SELECT COUNT(*) INTO v_vendor_customer_sms_before FROM public.sms_outbox
  WHERE company_id = v_vendor_a AND phone = v_order.customer_phone;
  SELECT COUNT(*) INTO v_carrier_customer_sms_before FROM public.sms_outbox
  WHERE company_id = v_carrier_a AND phone = v_order.customer_phone;

  PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
  PERFORM public.adjust_product_stock(v_product_a, 10, 'restock');
  PERFORM set_config('request.jwt.claim.sub', '', true);
  v_order2 := pg_temp.run_cod_order_to_carrier_accepted(v_customer1, v_vendor_a, v_vendor_a_owner, v_product_a, v_carrier_a, v_carrier_a_owner);

  SELECT COUNT(*) INTO v_sms_count FROM public.sms_outbox
  WHERE company_id = v_vendor_a AND phone = v_order2.customer_phone;
  IF v_sms_count - v_vendor_customer_sms_before < 2 THEN
    RAISE EXCEPTION 'expected at least 2 new customer SMS (accepted, ready) charged to the vendor, got %', v_sms_count - v_vendor_customer_sms_before;
  END IF;

  SELECT COUNT(*) INTO v_sms_count FROM public.sms_outbox
  WHERE company_id = v_carrier_a AND phone = v_order2.customer_phone;
  IF v_sms_count - v_carrier_customer_sms_before <> 1 THEN
    RAISE EXCEPTION 'expected exactly 1 new "carrier accepted" customer SMS charged to the carrier, got %', v_sms_count - v_carrier_customer_sms_before;
  END IF;

  INSERT INTO public.riders (company_id, rider_code, full_name, phone, status)
  VALUES (v_carrier_a, 'F2-' || substr(gen_random_uuid()::text, 1, 8), 'F Rider 2', '+231883' || lpad((floor(random()*999999))::text,6,'0'), 'available')
  RETURNING id INTO v_rider;

  PERFORM set_config('request.jwt.claim.sub', v_carrier_a_owner::text, true);
  PERFORM public.assign_delivery_rider(v_order2.delivery_id, v_rider);
  PERFORM public.transition_delivery_status(v_order2.delivery_id, 'accepted', NULL);
  PERFORM public.transition_delivery_status(v_order2.delivery_id, 'picked_up', NULL);
  PERFORM public.transition_delivery_status(v_order2.delivery_id, 'in_transit', NULL);
  PERFORM public.transition_delivery_status(v_order2.delivery_id, 'delivered', NULL);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT COUNT(*) INTO v_sms_count FROM public.sms_outbox
  WHERE company_id = v_vendor_a AND body ILIKE '%has been delivered%';
  IF v_sms_count <> 1 THEN
    RAISE EXCEPTION 'expected exactly 1 "delivery completed" SMS charged to the vendor, got %', v_sms_count;
  END IF;

  SELECT * INTO v_order2 FROM public.commerce_orders WHERE id = v_order2.id;
  IF v_order2.payment_status <> 'paid' OR v_order2.fulfillment_status <> 'completed' THEN
    RAISE EXCEPTION 'expected order 2 to reach paid/completed, got % / %', v_order2.payment_status, v_order2.fulfillment_status;
  END IF;

  SELECT * INTO v_event FROM public.commerce_financial_events
  WHERE commerce_order_id = v_order2.id AND event_type = 'cod_collected';
  IF v_event.id IS NULL THEN RAISE EXCEPTION 'expected a cod_collected event for order 2'; END IF;

  INSERT INTO f_assertions VALUES ('customer_and_vendor_lifecycle_sms_queued', true);

  -- =========================================================================
  -- 3) Finance netting: reversing order 2's financials (direct call, same
  --    idiom the E1 test suite already uses to reach this dormant-until-
  --    MoMo path) removes it from vendor gross/net and nets its payable
  --    out of pending_settlement, instead of leaving it silently counted.
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
  v_finance_before := public.get_vendor_commerce_finance(v_vendor_a);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  PERFORM public.reverse_commerce_order_financials(v_order2.id, 'f test reversal');

  PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
  v_finance_after := public.get_vendor_commerce_finance(v_vendor_a);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  IF (v_finance_after ->> 'net_earnings_lrd_cents')::INT <>
     (v_finance_before ->> 'net_earnings_lrd_cents')::INT - (v_event.snapshot ->> 'vendor_net_lrd_cents')::INT THEN
    RAISE EXCEPTION 'expected net_earnings to drop by exactly the reversed order''s vendor_net, before=% after=% order_net=%',
      v_finance_before ->> 'net_earnings_lrd_cents', v_finance_after ->> 'net_earnings_lrd_cents', v_event.snapshot ->> 'vendor_net_lrd_cents';
  END IF;

  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_finance_after -> 'orders') o
    WHERE (o ->> 'order_id')::UUID = v_order2.id
  ) THEN
    RAISE EXCEPTION 'expected the reversed order to be excluded from the vendor''s order breakdown';
  END IF;

  IF (v_finance_after ->> 'pending_settlement_lrd_cents')::INT <>
     (v_finance_before ->> 'pending_settlement_lrd_cents')::INT - (v_event.snapshot ->> 'vendor_net_lrd_cents')::INT THEN
    RAISE EXCEPTION 'expected pending_settlement to net out the reversed payable exactly, before=% after=%',
      v_finance_before ->> 'pending_settlement_lrd_cents', v_finance_after ->> 'pending_settlement_lrd_cents';
  END IF;

  INSERT INTO f_assertions VALUES ('finance_read_rpcs_net_reversal', true);

  -- =========================================================================
  -- 4) admin_list_commerce_financial_events filters: event_type and
  --    vendor_company_id scoping both work.
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  v_events := public.admin_list_commerce_financial_events(25, 0, NULL, NULL, v_vendor_a, 'reversal');
  PERFORM set_config('request.jwt.claim.sub', '', true);

  IF (v_events ->> 'total')::INT <> 1 THEN
    RAISE EXCEPTION 'expected exactly 1 reversal event for Vendor A, got %', v_events ->> 'total';
  END IF;

  INSERT INTO f_assertions VALUES ('financial_events_filters_work', true);

  -- =========================================================================
  -- 5) Non-admin forbidden from every new admin RPC.
  -- =========================================================================
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
    PERFORM public.admin_list_commerce_orders_page(NULL, false, 24, NULL, 25, 0);
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN RAISE EXCEPTION 'expected a vendor to be forbidden from admin_list_commerce_orders_page'; END IF;

  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
    PERFORM public.admin_commerce_reconciliation_gaps(50);
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN RAISE EXCEPTION 'expected a vendor to be forbidden from admin_commerce_reconciliation_gaps'; END IF;

  INSERT INTO f_assertions VALUES ('new_admin_rpcs_forbidden_for_non_admin', true);

  -- =========================================================================
  -- 6) Stuck-order detection: with a 0-hour threshold, an in-flight order
  --    is immediately flagged; admin_list_commerce_orders_page and
  --    admin_get_commerce_orders_summary agree.
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
  PERFORM public.adjust_product_stock(v_product_a, 10, 'restock');
  PERFORM set_config('request.jwt.claim.sub', '', true);
  DECLARE
    v_stuck_order public.commerce_orders;
    v_stuck_cart UUID;
    v_stuck_rows JSONB;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
    v_stuck_cart := (public.get_or_create_cart(v_vendor_a)).id;
    PERFORM public.add_cart_item(v_stuck_cart, v_product_a, 1, '[]'::JSONB);
    v_stuck_order := public.submit_commerce_order(v_stuck_cart, 'F Stuck Customer', 'Addr', 'Area', NULL, NULL, NULL, 'cod');
    PERFORM set_config('request.jwt.claim.sub', '', true);

    -- Postgres's now() is frozen for this whole test's transaction, so a
    -- freshly-inserted row's updated_at (also now()-defaulted, and reset
    -- to now() again by the commerce_orders_updated_at trigger on every
    -- UPDATE) can never compare as "earlier than now()" no matter how
    -- small the threshold — disable the trigger just long enough to
    -- backdate it explicitly, the same way a real clock would after real
    -- time passes in production.
    ALTER TABLE public.commerce_orders DISABLE TRIGGER commerce_orders_updated_at;
    UPDATE public.commerce_orders SET updated_at = now() - INTERVAL '1 hour' WHERE id = v_stuck_order.id;
    ALTER TABLE public.commerce_orders ENABLE TRIGGER commerce_orders_updated_at;

    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    v_stuck_summary := public.admin_get_commerce_orders_summary(0);
    v_stuck_rows := public.admin_list_commerce_orders_page(ARRAY['awaiting_vendor'], true, 0, NULL, 25, 0);
    PERFORM set_config('request.jwt.claim.sub', '', true);

    IF (v_stuck_summary ->> 'stuck_count')::INT < 1 THEN
      RAISE EXCEPTION 'expected stuck_count >= 1 with a 0-hour threshold, got %', v_stuck_summary ->> 'stuck_count';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_stuck_rows -> 'rows') r WHERE (r ->> 'id')::UUID = v_stuck_order.id
    ) THEN
      RAISE EXCEPTION 'expected the freshly-submitted order to appear in the stuck-only listing at a 0-hour threshold';
    END IF;
  END;

  INSERT INTO f_assertions VALUES ('stuck_order_detection_works', true);

  -- =========================================================================
  -- 7) Carrier pricing readiness listing distinguishes "never configured"
  --    from "explicitly configured".
  -- =========================================================================
  SELECT company_id, owner_id INTO v_unconfigured_carrier, v_unconfigured_owner FROM pg_temp.make_company('F Unconfigured Carrier', 'logistics_provider');

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  v_providers := public.admin_list_commerce_providers_page(NULL, 100, 0);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  IF NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_providers -> 'rows') r
    WHERE (r ->> 'company_id')::UUID = v_unconfigured_carrier AND r ->> 'delivery_pricing_configured_at' IS NULL
  ) THEN
    RAISE EXCEPTION 'expected the unconfigured carrier to show delivery_pricing_configured_at = null';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_providers -> 'rows') r
    WHERE (r ->> 'company_id')::UUID = v_carrier_a AND r ->> 'delivery_pricing_configured_at' IS NOT NULL
      AND (r ->> 'minimum_delivery_fee_lrd_cents')::INT = 2000
  ) THEN
    RAISE EXCEPTION 'expected the configured carrier to show its real minimum fee';
  END IF;

  INSERT INTO f_assertions VALUES ('provider_pricing_readiness_listing_accurate', true);

  -- =========================================================================
  -- 8) Reconciliation gap detection: an order manually marked paid without
  --    ever going through recognize_commerce_order_financials is surfaced;
  --    a genuinely-recognized order is not.
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
  PERFORM public.adjust_product_stock(v_product_a, 10, 'restock');
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
  DECLARE v_gap_cart UUID;
  BEGIN
    v_gap_cart := (public.get_or_create_cart(v_vendor_a)).id;
    PERFORM public.add_cart_item(v_gap_cart, v_product_a, 1, '[]'::JSONB);
    v_gap_order := public.submit_commerce_order(v_gap_cart, 'F Gap Customer', 'Addr', 'Area', NULL, NULL, NULL, 'cod');
  END;
  PERFORM set_config('request.jwt.claim.sub', '', true);

  -- Simulate the seam failing to fire: mark paid via a raw UPDATE, bypassing
  -- the trigger-driven recognition seam entirely (never possible for a real
  -- client, only reachable here to prove the check surfaces exactly this).
  UPDATE public.commerce_orders SET payment_status = 'paid' WHERE id = v_gap_order.id;

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  v_gaps := public.admin_commerce_reconciliation_gaps(200);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_gaps -> 'rows') r WHERE (r ->> 'id')::UUID = v_gap_order.id) THEN
    RAISE EXCEPTION 'expected the manually-paid, never-recognized order to appear as a reconciliation gap';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_gaps -> 'rows') r WHERE (r ->> 'id')::UUID = v_order2.id) THEN
    RAISE EXCEPTION 'expected the genuinely-recognized order 2 to NOT appear as a reconciliation gap';
  END IF;

  INSERT INTO f_assertions VALUES ('reconciliation_gap_detection_accurate', true);

  -- =========================================================================
  -- 9) get_vendor_store_profile: owner reads their own status_reason; a
  --    different vendor is forbidden; and the underlying column-level
  --    REVOKE genuinely blocks a raw authenticated SELECT of another
  --    store's status_reason (not just the RPC's own check).
  -- =========================================================================
  DECLARE v_own_profile public.store_profiles; v_vendor_b UUID; v_vendor_b_owner UUID;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
    v_own_profile := public.get_vendor_store_profile(v_vendor_a);
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF v_own_profile.company_id IS DISTINCT FROM v_vendor_a THEN
      RAISE EXCEPTION 'expected the vendor to read their own store profile via the RPC';
    END IF;

    SELECT company_id, owner_id INTO v_vendor_b, v_vendor_b_owner FROM pg_temp.make_company('F Vendor B', 'merchant');

    v_forbidden := false;
    BEGIN
      PERFORM set_config('request.jwt.claim.sub', v_vendor_b_owner::text, true);
      PERFORM public.get_vendor_store_profile(v_vendor_a);
      PERFORM set_config('request.jwt.claim.sub', '', true);
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('request.jwt.claim.sub', '', true);
      v_forbidden := true;
    END;
    IF NOT v_forbidden THEN RAISE EXCEPTION 'expected a different vendor to be forbidden from reading Vendor A''s store profile'; END IF;

    -- Vendor A's store is active (admin-approved earlier), so RLS alone
    -- would let another authenticated session read the ROW — the fix is
    -- specifically that the COLUMN is no longer readable for authenticated.
    v_forbidden := false;
    BEGIN
      SET LOCAL ROLE authenticated;
      PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
      PERFORM status_reason FROM public.store_profiles WHERE company_id = v_vendor_a;
      RESET ROLE;
    EXCEPTION WHEN OTHERS THEN
      RESET ROLE;
      v_forbidden := true;
    END;
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF NOT v_forbidden THEN
      RAISE EXCEPTION 'expected a raw authenticated SELECT of store_profiles.status_reason to be rejected by the column-level REVOKE';
    END IF;
  END;

  INSERT INTO f_assertions VALUES ('vendor_store_profile_rpc_and_column_revoke_enforced', true);

  -- =========================================================================
  -- 10) Onboarding status: a merchant company now sees Commerce-specific
  --     steps, correctly marked done once a store profile/product exist.
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
  v_onboarding := public.get_company_onboarding_status(v_vendor_a);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  v_steps := v_onboarding -> 'steps';
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_steps) s WHERE s ->> 'key' = 'commerce_store_profile' AND (s ->> 'done')::BOOLEAN = true) THEN
    RAISE EXCEPTION 'expected commerce_store_profile step to be present and done for Vendor A, got %', v_steps;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_steps) s WHERE s ->> 'key' = 'commerce_product' AND (s ->> 'done')::BOOLEAN = true) THEN
    RAISE EXCEPTION 'expected commerce_product step to be present and done for Vendor A, got %', v_steps;
  END IF;

  INSERT INTO f_assertions VALUES ('onboarding_status_has_commerce_steps', true);

  -- =========================================================================
  -- 11) commerce_enabled entitlement enforcement. The plan catalog
  --     (Super-Admin-controlled subscriptions.commerce_enabled) is the
  --     source of truth via can_use_feature — nothing here hardcodes a
  --     plan slug. Uses a FRESH vendor deliberately downgraded off the
  --     'business' plan the shared helper otherwise assigns, so this test
  --     is self-contained and doesn't disturb Vendor A's fixtures used
  --     everywhere else in this file.
  -- =========================================================================
  DECLARE
    v_ent_vendor UUID; v_ent_owner UUID;
    v_ent_product UUID;
    v_ent_cart UUID;
    v_ent_result RECORD;
    v_ent_forbidden BOOLEAN;
  BEGIN
    SELECT company_id, owner_id INTO v_ent_vendor, v_ent_owner FROM pg_temp.make_company('F Entitlement Vendor', 'merchant');
    UPDATE public.companies SET address = '1 Test Street, Monrovia' WHERE id = v_ent_vendor;

    -- Set up while still entitled (the shared helper defaults every fixture
    -- to 'business') so there's a real product/store to exercise below.
    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    PERFORM public.admin_set_vendor_state(v_ent_vendor, 'active', NULL);
    PERFORM set_config('request.jwt.claim.sub', '', true);

    PERFORM set_config('request.jwt.claim.sub', v_ent_owner::text, true);
    PERFORM public.upsert_store_profile(jsonb_build_object('company_id', v_ent_vendor, 'slug', 'f-entitlement-vendor', 'display_name', 'F Entitlement Vendor', 'allow_cash_on_delivery', true));
    v_ent_result := public.upsert_product(jsonb_build_object('company_id', v_ent_vendor, 'name', 'F Entitlement Product', 'price_lrd_cents', 5000, 'status', 'active'));
    v_ent_product := (v_ent_result).id;
    PERFORM set_config('request.jwt.claim.sub', '', true);

    -- Now downgrade off the entitled plan — the ONLY thing that changes.
    UPDATE public.company_subscriptions SET plan_id = (SELECT id FROM public.subscriptions WHERE slug = 'starter')
    WHERE company_id = v_ent_vendor;
    IF public.can_use_feature(v_ent_vendor, 'commerce_enabled') THEN
      RAISE EXCEPTION 'test setup invalid — vendor should be on a non-entitled plan now';
    END IF;

    -- (a) Direct RPC write calls are blocked, not just UI-hidden actions.
    v_ent_forbidden := false;
    BEGIN
      PERFORM set_config('request.jwt.claim.sub', v_ent_owner::text, true);
      PERFORM public.upsert_product(jsonb_build_object('company_id', v_ent_vendor, 'name', 'Should Fail', 'price_lrd_cents', 1000, 'status', 'active'));
      PERFORM set_config('request.jwt.claim.sub', '', true);
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('request.jwt.claim.sub', '', true);
      IF SQLERRM NOT LIKE '%commerce_not_enabled%' THEN RAISE; END IF;
      v_ent_forbidden := true;
    END;
    IF NOT v_ent_forbidden THEN RAISE EXCEPTION 'expected upsert_product to be blocked for a non-entitled vendor plan'; END IF;

    -- (b) The actual customer-facing purchase boundary is blocked too —
    -- not just vendor-side writes.
    v_ent_forbidden := false;
    BEGIN
      PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
      v_ent_cart := (public.get_or_create_cart(v_ent_vendor)).id;
      PERFORM public.add_cart_item(v_ent_cart, v_ent_product, 1, '[]'::JSONB);
      PERFORM public.submit_commerce_order(v_ent_cart, 'F Entitlement Customer', 'Addr', 'Area', NULL, NULL, NULL, 'cod');
      PERFORM set_config('request.jwt.claim.sub', '', true);
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('request.jwt.claim.sub', '', true);
      IF SQLERRM NOT LIKE '%commerce_not_enabled%' THEN RAISE; END IF;
      v_ent_forbidden := true;
    END;
    IF NOT v_ent_forbidden THEN RAISE EXCEPTION 'expected submit_commerce_order to be blocked for a non-entitled vendor plan'; END IF;

    INSERT INTO f_assertions VALUES ('commerce_disabled_plan_blocks_writes_and_checkout', true);

    -- (c) Reads are NOT blocked — a vendor whose plan lapses can still see
    -- their own existing orders/overview/finance (no precedent anywhere
    -- else in this codebase for locking a tenant out of their own history
    -- on a plan gate).
    PERFORM set_config('request.jwt.claim.sub', v_ent_owner::text, true);
    PERFORM public.list_vendor_commerce_orders_page(v_ent_vendor);
    PERFORM public.get_vendor_commerce_overview(v_ent_vendor);
    PERFORM public.get_vendor_commerce_finance(v_ent_vendor);
    PERFORM set_config('request.jwt.claim.sub', '', true);

    INSERT INTO f_assertions VALUES ('commerce_disabled_plan_still_allows_vendor_reads', true);

    -- (d) Super Admin operational access is not broken by a vendor's own
    -- plan: admin can still write on behalf of this exact non-entitled
    -- vendor, and admin's own operational RPCs are entirely unaffected.
    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    PERFORM public.upsert_product(jsonb_build_object('company_id', v_ent_vendor, 'name', 'Admin Added Product', 'price_lrd_cents', 2000, 'status', 'active'));
    PERFORM public.admin_set_vendor_state(v_ent_vendor, 'active', 'admin note');
    PERFORM public.admin_list_commerce_orders_page(NULL, false, 24, NULL, 25, 0);
    PERFORM public.admin_commerce_reconciliation_gaps(50);
    PERFORM set_config('request.jwt.claim.sub', '', true);

    INSERT INTO f_assertions VALUES ('commerce_super_admin_exempt_and_operational', true);

    -- (e) The plan catalog is the live source of truth — flipping the
    -- SAME company back to an entitled plan immediately restores write
    -- access, with zero other change.
    UPDATE public.company_subscriptions SET plan_id = (SELECT id FROM public.subscriptions WHERE slug = 'business')
    WHERE company_id = v_ent_vendor;

    PERFORM set_config('request.jwt.claim.sub', v_ent_owner::text, true);
    v_ent_result := public.upsert_product(jsonb_build_object('company_id', v_ent_vendor, 'name', 'Now Allowed', 'price_lrd_cents', 3000, 'status', 'active'));
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF (v_ent_result).id IS NULL THEN
      RAISE EXCEPTION 'expected upsert_product to succeed immediately after the plan catalog re-grants commerce_enabled';
    END IF;

    INSERT INTO f_assertions VALUES ('commerce_entitlement_tracks_live_catalog_change', true);
  END;
END;
$$;

SELECT ok((SELECT ok FROM f_assertions WHERE key = 'stock_released_on_delivery_failure'), 'a delivery that fails after handed_to_carrier releases its reserved stock and cancels the order');
SELECT ok((SELECT ok FROM f_assertions WHERE key = 'vendor_new_order_sms_queued'), 'submit_commerce_order queues exactly one "new order" SMS charged to the vendor');
SELECT ok((SELECT ok FROM f_assertions WHERE key = 'customer_and_vendor_lifecycle_sms_queued'), 'accepted/ready/carrier-accepted/delivered notifications fire exactly once each, charged to the documented payer');
SELECT ok((SELECT ok FROM f_assertions WHERE key = 'finance_read_rpcs_net_reversal'), 'get_vendor_commerce_finance excludes a reversed order from gross/net and nets its payable out of pending settlement');
SELECT ok((SELECT ok FROM f_assertions WHERE key = 'financial_events_filters_work'), 'admin_list_commerce_financial_events filters by event_type and vendor_company_id');
SELECT ok((SELECT ok FROM f_assertions WHERE key = 'new_admin_rpcs_forbidden_for_non_admin'), 'a vendor cannot call the new admin operational RPCs');
SELECT ok((SELECT ok FROM f_assertions WHERE key = 'stuck_order_detection_works'), 'admin_get_commerce_orders_summary and admin_list_commerce_orders_page agree on stuck orders at a given threshold');
SELECT ok((SELECT ok FROM f_assertions WHERE key = 'provider_pricing_readiness_listing_accurate'), 'admin_list_commerce_providers_page distinguishes never-configured from explicitly-configured carrier pricing');
SELECT ok((SELECT ok FROM f_assertions WHERE key = 'reconciliation_gap_detection_accurate'), 'admin_commerce_reconciliation_gaps surfaces a paid-but-unrecognized order and excludes a genuinely-recognized one');
SELECT ok((SELECT ok FROM f_assertions WHERE key = 'vendor_store_profile_rpc_and_column_revoke_enforced'), 'get_vendor_store_profile enforces company ownership and the column-level REVOKE blocks a raw authenticated read of another store''s status_reason');
SELECT ok((SELECT ok FROM f_assertions WHERE key = 'onboarding_status_has_commerce_steps'), 'get_company_onboarding_status reports Commerce-specific steps for a merchant company');
SELECT ok((SELECT ok FROM f_assertions WHERE key = 'commerce_disabled_plan_blocks_writes_and_checkout'), 'a vendor on a non-entitled plan cannot upsert_product, and a customer cannot submit_commerce_order to that vendor, via direct RPC calls');
SELECT ok((SELECT ok FROM f_assertions WHERE key = 'commerce_disabled_plan_still_allows_vendor_reads'), 'a vendor on a non-entitled plan can still read their own order list/overview/finance');
SELECT ok((SELECT ok FROM f_assertions WHERE key = 'commerce_super_admin_exempt_and_operational'), 'Super Admin can still write on behalf of a non-entitled vendor and every admin operational RPC remains unaffected');
SELECT ok((SELECT ok FROM f_assertions WHERE key = 'commerce_entitlement_tracks_live_catalog_change'), 'upgrading the plan catalog immediately restores write access with no other change');

SELECT * FROM finish();
ROLLBACK;
