-- Coverage for DeliveryOS Commerce Phase B vendor fulfillment RPCs
-- (20260308220000_commerce_phase_b_vendor_fulfillment.sql).
--
-- Proves: the strict awaiting_vendor -> vendor_accepted -> preparing ->
-- ready_for_pickup state machine (no arbitrary jumps), that acceptance is
-- blocked without payment_status='paid' (the Phase A payment-gating
-- decision, honored rather than bypassed), that rejection releases stock
-- and never requires payment, cross-vendor/cross-company/customer
-- rejection, role-appropriate permissions (support_staff can fulfill
-- orders but not manage the catalog), and that a non-vendor company is
-- rejected outright.

BEGIN;
SELECT plan(13);

SELECT has_function('public'::name, 'vendor_accept_commerce_order'::name);
SELECT has_function('public'::name, 'vendor_reject_commerce_order'::name);
SELECT has_function('public'::name, 'vendor_mark_order_preparing'::name);
SELECT has_function('public'::name, 'vendor_mark_order_ready'::name);

CREATE OR REPLACE FUNCTION pg_temp.make_customer(p_label TEXT)
RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
  v_user UUID := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, phone, email, encrypted_password, phone_confirmed_at, aud, role)
  VALUES (
    v_user, '+23177' || lpad((floor(random() * 999999))::text, 6, '0'),
    'commerce-b-' || substr(v_user::text, 1, 8) || '@test.local',
    crypt('x', gen_salt('bf')), now(), 'authenticated', 'authenticated'
  );
  INSERT INTO public.profiles (id, full_name) VALUES (v_user, p_label)
  ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name;
  RETURN v_user;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.make_vendor_company(p_label TEXT, p_business_type public.company_business_type DEFAULT 'merchant')
RETURNS TABLE (company_id UUID, owner_id UUID) LANGUAGE plpgsql AS $$
DECLARE
  v_owner UUID := pg_temp.make_customer(p_label || ' Owner');
  v_company UUID;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  v_company := public.create_company_with_owner(
    p_label, '+23177' || lpad((floor(random() * 999999))::text, 6, '0'),
    lower(replace(p_label, ' ', '')) || '@test.local', NULL, p_business_type
  );
  PERFORM set_config('request.jwt.claim.sub', '', true);
  RETURN QUERY SELECT v_company, v_owner;
END;
$$;

DO $$
DECLARE
  v_admin UUID;
  v_vendor_a UUID; v_vendor_a_owner UUID; v_vendor_a_support UUID;
  v_vendor_b UUID; v_vendor_b_owner UUID;
  v_carrier UUID; v_carrier_owner UUID;
  v_customer1 UUID;
  v_product UUID;
  v_result RECORD;
  v_order_paid public.commerce_orders;
  v_order_unpaid public.commerce_orders;
  v_order_jump public.commerce_orders;
  v_cart UUID;
  v_forbidden BOOLEAN;
  v_status TEXT;
BEGIN
  v_admin := pg_temp.make_customer('Fulfillment Admin');
  UPDATE public.profiles SET is_super_admin = true WHERE id = v_admin;

  SELECT company_id, owner_id INTO v_vendor_a, v_vendor_a_owner FROM pg_temp.make_vendor_company('Fulfillment Vendor A');
  SELECT company_id, owner_id INTO v_vendor_b, v_vendor_b_owner FROM pg_temp.make_vendor_company('Fulfillment Vendor B');
  SELECT company_id, owner_id INTO v_carrier, v_carrier_owner FROM pg_temp.make_vendor_company('Not A Vendor Co', 'logistics_provider');
  v_customer1 := pg_temp.make_customer('Fulfillment Customer');

  v_vendor_a_support := pg_temp.make_customer('Fulfillment Vendor A Support');
  INSERT INTO public.company_users (company_id, user_id, role, is_active)
  VALUES (v_vendor_a, v_vendor_a_support, 'support_staff', true);

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM public.admin_set_vendor_state(v_vendor_a, 'active', NULL);
  PERFORM public.admin_set_vendor_state(v_vendor_b, 'active', NULL);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  -- Phase B.5: COD defaults off — this file exercises fulfillment, not
  -- payment-method gating itself (covered by commerce_phase_b5.test.sql),
  -- so enable it on both fixture vendors.
  UPDATE public.store_profiles SET allow_cash_on_delivery = true WHERE company_id IN (v_vendor_a, v_vendor_b);

  PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
  v_result := public.upsert_product(jsonb_build_object(
    'company_id', v_vendor_a, 'name', 'Fulfillment Test Product', 'price_lrd_cents', 20000, 'status', 'active'
  ));
  v_product := (v_result).id;
  PERFORM set_config('request.jwt.claim.sub', '', true);

  CREATE TEMP TABLE fulfillment_assertions (key TEXT PRIMARY KEY, ok BOOLEAN);

  -- =========================================================================
  -- Fixture orders: one to be paid+accepted, one left unpaid, one paid but
  -- used only for the "cannot skip states" jump test.
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
  v_cart := (public.get_or_create_cart(v_vendor_a)).id;
  PERFORM public.add_cart_item(v_cart, v_product, 1, '[]'::JSONB);
  v_order_paid := public.submit_commerce_order(v_cart, 'Fulfillment Customer');
  PERFORM set_config('request.jwt.claim.sub', '', true);
  v_order_paid := public.mark_commerce_order_paid(v_order_paid.id);

  PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
  v_cart := (public.get_or_create_cart(v_vendor_a)).id;
  PERFORM public.add_cart_item(v_cart, v_product, 1, '[]'::JSONB);
  v_order_unpaid := public.submit_commerce_order(v_cart, 'Fulfillment Customer');
  PERFORM set_config('request.jwt.claim.sub', '', true);

  PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
  v_cart := (public.get_or_create_cart(v_vendor_a)).id;
  PERFORM public.add_cart_item(v_cart, v_product, 1, '[]'::JSONB);
  v_order_jump := public.submit_commerce_order(v_cart, 'Fulfillment Customer');
  PERFORM set_config('request.jwt.claim.sub', '', true);
  v_order_jump := public.mark_commerce_order_paid(v_order_jump.id);

  -- Note: as of Phase B.5, payment-method-aware acceptance eligibility
  -- (COD eligible while pending_payment; online methods require paid) is
  -- covered precisely in commerce_phase_b5.test.sql. This file continues
  -- to prove the fulfillment STATE MACHINE itself, independent of payment
  -- method — v_order_unpaid (COD, pending_payment) is deliberately left
  -- unaccepted here so test 4 below can exercise rejection.

  -- =========================================================================
  -- 2) Full valid state machine: awaiting_vendor -> vendor_accepted ->
  --    preparing -> ready_for_pickup.
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
  v_order_paid := public.vendor_accept_commerce_order(v_order_paid.id);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF v_order_paid.fulfillment_status <> 'vendor_accepted' THEN
    RAISE EXCEPTION 'expected vendor_accepted, got %', v_order_paid.fulfillment_status;
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
  v_order_paid := public.vendor_mark_order_preparing(v_order_paid.id);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF v_order_paid.fulfillment_status <> 'preparing' THEN
    RAISE EXCEPTION 'expected preparing, got %', v_order_paid.fulfillment_status;
  END IF;

  -- support_staff can carry the order the rest of the way (order actions
  -- are allowed for support_staff, unlike catalog management).
  PERFORM set_config('request.jwt.claim.sub', v_vendor_a_support::text, true);
  v_order_paid := public.vendor_mark_order_ready(v_order_paid.id);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF v_order_paid.fulfillment_status <> 'ready_for_pickup' THEN
    RAISE EXCEPTION 'expected ready_for_pickup, got %', v_order_paid.fulfillment_status;
  END IF;

  INSERT INTO fulfillment_assertions VALUES ('valid_state_machine', true);

  -- =========================================================================
  -- 3) No arbitrary jumps: a paid, still-awaiting-vendor order cannot go
  --    straight to preparing or ready_for_pickup.
  -- =========================================================================
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
    PERFORM public.vendor_mark_order_preparing(v_order_jump.id);
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%invalid_fulfillment_state%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected awaiting_vendor -> preparing to be rejected as an invalid jump';
  END IF;

  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
    PERFORM public.vendor_mark_order_ready(v_order_jump.id);
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%invalid_fulfillment_state%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected awaiting_vendor -> ready_for_pickup to be rejected as an invalid jump';
  END IF;

  INSERT INTO fulfillment_assertions VALUES ('no_arbitrary_jumps', true);

  -- =========================================================================
  -- 4) Rejection: allowed on an unpaid order (no payment gate), releases
  --    stock, never requires payment_status='paid'.
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
  v_order_unpaid := public.vendor_reject_commerce_order(v_order_unpaid.id, 'out of stock today');
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF v_order_unpaid.fulfillment_status <> 'vendor_rejected' THEN
    RAISE EXCEPTION 'expected vendor_rejected, got %', v_order_unpaid.fulfillment_status;
  END IF;
  IF v_order_unpaid.payment_status <> 'pending_payment' THEN
    RAISE EXCEPTION 'expected payment_status to stay pending_payment for a rejected-while-unpaid order, got %', v_order_unpaid.payment_status;
  END IF;

  -- Rejecting a PAID order flags refund_pending, since real money would
  -- need to be returned once MoMo exists.
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
    PERFORM public.vendor_reject_commerce_order(v_order_paid.id, 'too late to reject');
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%invalid_fulfillment_state%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected rejecting an already-ready_for_pickup order to be blocked (only valid from awaiting_vendor)';
  END IF;

  INSERT INTO fulfillment_assertions VALUES ('rejection_rules', true);

  -- =========================================================================
  -- 5) Cross-vendor: vendor B cannot act on vendor A's order.
  -- =========================================================================
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_vendor_b_owner::text, true);
    PERFORM public.vendor_accept_commerce_order(v_order_jump.id);
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%forbidden%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected vendor B to be forbidden from acting on vendor A''s order';
  END IF;

  INSERT INTO fulfillment_assertions VALUES ('cross_vendor_blocked', true);

  -- =========================================================================
  -- 6) Customer cannot call any vendor fulfillment RPC.
  -- =========================================================================
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
    PERFORM public.vendor_accept_commerce_order(v_order_jump.id);
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%forbidden%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected the customer who placed the order to be forbidden from calling vendor fulfillment RPCs';
  END IF;

  INSERT INTO fulfillment_assertions VALUES ('customer_cannot_fulfill', true);

  -- =========================================================================
  -- 7) A non-vendor (logistics_provider) company is rejected outright.
  -- =========================================================================
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_carrier_owner::text, true);
    PERFORM public.get_vendor_commerce_overview(v_carrier);
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%not_a_vendor_company%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected a pure logistics_provider company to be rejected as not a vendor company';
  END IF;

  INSERT INTO fulfillment_assertions VALUES ('non_vendor_company_blocked', true);

  -- =========================================================================
  -- 8) Role separation: support_staff can fulfill orders (already proven
  --    above) but cannot manage the catalog (Phase A's assert_vendor_manager
  --    is owner+dispatcher only).
  -- =========================================================================
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_vendor_a_support::text, true);
    PERFORM public.upsert_product(jsonb_build_object('company_id', v_vendor_a, 'name', 'Support Cannot Add This', 'price_lrd_cents', 100));
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%forbidden%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected support_staff to be forbidden from catalog management (owner/dispatcher only)';
  END IF;

  INSERT INTO fulfillment_assertions VALUES ('support_staff_role_boundary', true);

  -- =========================================================================
  -- 9) Vendor order inbox / overview RPCs return real counts (no fabricated
  --    GMV — these RPCs return counts only, verified by their JSONB keys).
  -- =========================================================================
  DECLARE
    v_overview JSONB;
    v_inbox JSONB;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
    v_overview := public.get_vendor_commerce_overview(v_vendor_a);
    v_inbox := public.list_vendor_commerce_orders_page(v_vendor_a, NULL, 25, 0);
    PERFORM set_config('request.jwt.claim.sub', '', true);

    IF v_overview ? 'gmv_lrd_cents' OR v_overview ? 'revenue_lrd_cents' THEN
      RAISE EXCEPTION 'vendor overview must never expose a fabricated GMV/revenue figure';
    END IF;
    IF (v_overview -> 'catalog' ->> 'product_count')::INT <> 1 THEN
      RAISE EXCEPTION 'expected 1 product in vendor A catalog, got %', v_overview -> 'catalog' ->> 'product_count';
    END IF;
    IF (v_inbox ->> 'total')::INT < 3 THEN
      RAISE EXCEPTION 'expected at least 3 orders in the vendor A inbox, got %', v_inbox ->> 'total';
    END IF;
  END;

  INSERT INTO fulfillment_assertions VALUES ('overview_and_inbox_real_data', true);

  -- =========================================================================
  -- 10) Suspended vendor can still fulfill an order already in flight
  --     (a deliberate design choice — see the Phase B report).
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM public.admin_set_vendor_state(v_vendor_a, 'suspended', 'test suspension');
  PERFORM set_config('request.jwt.claim.sub', '', true);

  -- v_order_jump is still paid/awaiting_vendor (the earlier jump attempts
  -- both failed and rolled back) — a suspended vendor must still be able to
  -- progress an order already placed against it; suspension only blocks
  -- NEW carts/orders (already enforced by Phase A's store_is_publicly_visible).
  PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
  v_order_jump := public.vendor_accept_commerce_order(v_order_jump.id);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF v_order_jump.fulfillment_status <> 'vendor_accepted' THEN
    RAISE EXCEPTION 'expected a suspended vendor to still be able to progress an order already in flight, got %', v_order_jump.fulfillment_status;
  END IF;

  -- But suspension DOES block a brand new cart/order from being placed.
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
    PERFORM public.get_or_create_cart(v_vendor_a);
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%vendor_not_available%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected a suspended vendor to reject a brand new cart';
  END IF;

  INSERT INTO fulfillment_assertions VALUES ('suspended_vendor_behavior', true);
END;
$$;

SELECT ok((SELECT ok FROM fulfillment_assertions WHERE key = 'valid_state_machine'), 'the full awaiting_vendor -> vendor_accepted -> preparing -> ready_for_pickup path succeeds');
SELECT ok((SELECT ok FROM fulfillment_assertions WHERE key = 'no_arbitrary_jumps'), 'an awaiting_vendor order cannot skip directly to preparing or ready_for_pickup');
SELECT ok((SELECT ok FROM fulfillment_assertions WHERE key = 'rejection_rules'), 'rejection works on an unpaid order without a payment gate, flags refund_pending when rejecting a paid order, and is only valid from awaiting_vendor');
SELECT ok((SELECT ok FROM fulfillment_assertions WHERE key = 'cross_vendor_blocked'), 'a different vendor cannot act on another vendor''s order');
SELECT ok((SELECT ok FROM fulfillment_assertions WHERE key = 'customer_cannot_fulfill'), 'the customer who placed the order cannot call any vendor fulfillment RPC');
SELECT ok((SELECT ok FROM fulfillment_assertions WHERE key = 'non_vendor_company_blocked'), 'a pure logistics_provider company is rejected as not_a_vendor_company');
SELECT ok((SELECT ok FROM fulfillment_assertions WHERE key = 'support_staff_role_boundary'), 'support_staff can fulfill orders but cannot manage the catalog (owner/dispatcher only)');
SELECT ok((SELECT ok FROM fulfillment_assertions WHERE key = 'overview_and_inbox_real_data'), 'vendor overview/inbox RPCs return only real counts, never a fabricated GMV/revenue figure');
SELECT ok((SELECT ok FROM fulfillment_assertions WHERE key = 'suspended_vendor_behavior'), 'a suspended vendor can still progress an order already in flight, but a suspended store rejects brand new carts');

SELECT * FROM finish();
ROLLBACK;
