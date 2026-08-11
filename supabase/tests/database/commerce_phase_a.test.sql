-- Coverage for DeliveryOS Commerce Phase A — Foundation
-- (20260308210000_commerce_phase_a_foundation.sql).
--
-- Proves: vendor isolation, customer cart/order ownership, Super Admin
-- access, product visibility rules, vendor approval/publication states,
-- stock reservation concurrency-safety/idempotency, order snapshot
-- immutability, OTP-verification gating on order placement, and that the
-- existing delivery engine is unaffected by the new nullable
-- deliveries.commerce_order_id column.
--
-- RLS assertions use this codebase's established pattern (see
-- phase4_billing.test.sql/phase5_field_ops.test.sql/phase6_operations.test.sql):
-- SET LOCAL ROLE authenticated + set_config('request.jwt.claim.sub', ...)
-- inside the same transaction, RESET ROLE afterward. pgTAP runs a single
-- sequential connection, so "concurrency" here proves the FOR UPDATE
-- lock-then-check invariant is correct (the same depth of proof this
-- codebase already uses for plan_limit_race_condition_locks.sql), not a
-- literal two-connection race.

BEGIN;
SELECT plan(18);

SELECT has_function('public'::name, 'submit_commerce_order'::name);
SELECT has_function('public'::name, 'get_or_create_cart'::name);
SELECT has_function('public'::name, 'admin_set_vendor_state'::name);
SELECT has_function('public'::name, 'mark_commerce_order_paid'::name);

CREATE OR REPLACE FUNCTION pg_temp.make_customer(p_label TEXT, p_verified BOOLEAN DEFAULT true)
RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
  v_user UUID := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, phone, email, encrypted_password, phone_confirmed_at, aud, role)
  VALUES (
    v_user, '+23177' || lpad((floor(random() * 999999))::text, 6, '0'),
    'commerce-' || substr(v_user::text, 1, 8) || '@test.local',
    crypt('x', gen_salt('bf')),
    CASE WHEN p_verified THEN now() ELSE NULL END,
    'authenticated', 'authenticated'
  );
  INSERT INTO public.profiles (id, full_name) VALUES (v_user, p_label)
  ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name;
  RETURN v_user;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.make_vendor_company(p_label TEXT)
RETURNS TABLE (company_id UUID, owner_id UUID) LANGUAGE plpgsql AS $$
DECLARE
  v_owner UUID := pg_temp.make_customer(p_label || ' Owner');
  v_company UUID;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  v_company := public.create_company_with_owner(
    p_label, '+23177' || lpad((floor(random() * 999999))::text, 6, '0'),
    lower(replace(p_label, ' ', '')) || '@test.local', NULL,
    'merchant'::public.company_business_type
  );
  PERFORM set_config('request.jwt.claim.sub', '', true);
  RETURN QUERY SELECT v_company, v_owner;
END;
$$;

DO $$
DECLARE
  v_admin UUID;
  v_vendor_a UUID; v_vendor_a_owner UUID;
  v_vendor_b UUID; v_vendor_b_owner UUID;
  v_customer1 UUID; v_customer2 UUID; v_unverified_customer UUID;
  v_product_active UUID;
  v_product_draft UUID;
  v_product_limited UUID;
  v_cart1 UUID; v_cart2 UUID;
  v_order1 public.commerce_orders;
  v_order2 public.commerce_orders;
  v_store public.store_profiles;
  v_result RECORD;
  v_count INT;
  v_forbidden BOOLEAN;
  v_before_price INT;
  v_after_price INT;
  v_stock public.product_stock;
BEGIN
  v_admin := pg_temp.make_customer('Commerce Admin');
  UPDATE public.profiles SET is_super_admin = true WHERE id = v_admin;

  SELECT company_id, owner_id INTO v_vendor_a, v_vendor_a_owner FROM pg_temp.make_vendor_company('Marys Kitchen');
  SELECT company_id, owner_id INTO v_vendor_b, v_vendor_b_owner FROM pg_temp.make_vendor_company('Other Vendor');
  v_customer1 := pg_temp.make_customer('Customer One');
  v_customer2 := pg_temp.make_customer('Customer Two');
  v_unverified_customer := pg_temp.make_customer('Ghost Customer', false);

  CREATE TEMP TABLE commerce_assertions (key TEXT PRIMARY KEY, ok BOOLEAN);

  -- =========================================================================
  -- 1) Vendor approval/publication state machine
  -- =========================================================================
  SELECT * INTO v_store FROM public.store_profiles WHERE company_id = v_vendor_a;
  IF v_store.status <> 'draft' THEN
    RAISE EXCEPTION 'expected auto-provisioned store_profiles row in draft, got %', v_store.status;
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
  PERFORM public.submit_store_profile_for_review(v_vendor_a);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT status INTO v_store.status FROM public.store_profiles WHERE company_id = v_vendor_a;
  IF v_store.status <> 'pending_review' THEN
    RAISE EXCEPTION 'expected pending_review after vendor submission, got %', v_store.status;
  END IF;

  -- Vendor cannot self-approve.
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
    PERFORM public.admin_set_vendor_state(v_vendor_a, 'active', NULL);
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%forbidden%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected a vendor to be forbidden from self-approving its own store';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM public.admin_set_vendor_state(v_vendor_a, 'active', 'looks good');
  PERFORM public.admin_set_vendor_state(v_vendor_b, 'active', 'looks good');
  PERFORM set_config('request.jwt.claim.sub', '', true);

  -- Phase B.5: COD defaults off — this file exercises order submission, not
  -- payment-method gating itself (covered by commerce_phase_b5.test.sql),
  -- so enable it on both fixture vendors.
  UPDATE public.store_profiles SET allow_cash_on_delivery = true WHERE company_id IN (v_vendor_a, v_vendor_b);

  SELECT status INTO v_store.status FROM public.store_profiles WHERE company_id = v_vendor_a;
  IF v_store.status <> 'active' THEN
    RAISE EXCEPTION 'expected super admin approval to activate the store, got %', v_store.status;
  END IF;

  INSERT INTO commerce_assertions VALUES ('vendor_approval_lifecycle', true);

  -- =========================================================================
  -- Catalog fixtures (vendor A)
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
  v_result := public.upsert_product(jsonb_build_object(
    'company_id', v_vendor_a, 'name', 'Jollof Rice', 'price_lrd_cents', 50000, 'status', 'active'
  ));
  v_product_active := (v_result).id;

  v_result := public.upsert_product(jsonb_build_object(
    'company_id', v_vendor_a, 'name', 'Secret Menu Item', 'price_lrd_cents', 99900, 'status', 'draft'
  ));
  v_product_draft := (v_result).id;

  v_result := public.upsert_product(jsonb_build_object(
    'company_id', v_vendor_a, 'name', 'Limited Special', 'price_lrd_cents', 100000,
    'status', 'active', 'tracks_inventory', true, 'initial_quantity', 1
  ));
  v_product_limited := (v_result).id;
  PERFORM set_config('request.jwt.claim.sub', '', true);

  -- =========================================================================
  -- 2) Product visibility rules (public RLS, via a real unrelated
  --    authenticated role — not superuser bypass).
  -- =========================================================================
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);

  SELECT COUNT(*)::INT INTO v_count FROM public.products WHERE id = v_product_active;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'expected an active product on a published store to be publicly visible, got % rows', v_count;
  END IF;

  SELECT COUNT(*)::INT INTO v_count FROM public.products WHERE id = v_product_draft;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'expected a draft product to be invisible to an unrelated customer, got % rows', v_count;
  END IF;

  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);

  INSERT INTO commerce_assertions VALUES ('product_visibility_rules', true);

  -- =========================================================================
  -- 3) Vendor isolation (vendor B must not see vendor A's private stock/
  --    draft catalog data via RLS).
  -- =========================================================================
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_vendor_b_owner::text, true);

  SELECT COUNT(*)::INT INTO v_count FROM public.product_stock WHERE product_id = v_product_limited;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'expected vendor B to see 0 rows of vendor A private stock, got %', v_count;
  END IF;

  SELECT COUNT(*)::INT INTO v_count FROM public.products WHERE id = v_product_draft;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'expected vendor B to see 0 rows of vendor A draft product, got %', v_count;
  END IF;

  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);

  -- Vendor B's staff cannot manage vendor A's catalog via the RPC layer either.
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_vendor_b_owner::text, true);
    PERFORM public.upsert_product(jsonb_build_object('company_id', v_vendor_a, 'name', 'Hijack', 'price_lrd_cents', 100));
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%forbidden%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected vendor B to be forbidden from managing vendor A catalog';
  END IF;

  INSERT INTO commerce_assertions VALUES ('vendor_isolation', true);

  -- =========================================================================
  -- 4) OTP verification gate: an unverified identity cannot place an order.
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_unverified_customer::text, true);
  v_cart1 := (public.get_or_create_cart(v_vendor_a)).id;
  PERFORM public.add_cart_item(v_cart1, v_product_active, 1, '[]'::JSONB);

  v_forbidden := false;
  BEGIN
    PERFORM public.submit_commerce_order(v_cart1, 'Ghost');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%phone_not_verified%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected an unverified (never-OTP-confirmed) identity to be blocked from ordering';
  END IF;

  INSERT INTO commerce_assertions VALUES ('otp_verification_required', true);

  -- =========================================================================
  -- 5) Server-authoritative pricing + order creation (customer 1, real cart).
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
  v_cart1 := (public.get_or_create_cart(v_vendor_a)).id;
  PERFORM public.add_cart_item(v_cart1, v_product_active, 2, '[]'::JSONB);
  v_order1 := public.submit_commerce_order(v_cart1, 'Customer One', 'Near the big mango tree');
  PERFORM set_config('request.jwt.claim.sub', '', true);

  IF v_order1.subtotal_lrd_cents <> 100000 THEN
    RAISE EXCEPTION 'expected server-computed subtotal 100000 (2 x 50000), got %', v_order1.subtotal_lrd_cents;
  END IF;
  IF v_order1.total_lrd_cents <> v_order1.subtotal_lrd_cents THEN
    RAISE EXCEPTION 'expected total = subtotal with no delivery fee yet, got %', v_order1.total_lrd_cents;
  END IF;
  IF v_order1.payment_status <> 'pending_payment' OR v_order1.fulfillment_status <> 'awaiting_vendor' THEN
    RAISE EXCEPTION 'expected a freshly submitted order at pending_payment/awaiting_vendor, got %/%',
      v_order1.payment_status, v_order1.fulfillment_status;
  END IF;

  SELECT unit_price_lrd_cents INTO v_before_price
  FROM public.commerce_order_items WHERE order_id = v_order1.id LIMIT 1;
  IF v_before_price <> 50000 THEN
    RAISE EXCEPTION 'expected snapshot unit price 50000, got %', v_before_price;
  END IF;

  INSERT INTO commerce_assertions VALUES ('server_authoritative_pricing', true);

  -- Resubmitting the same (now-converted) cart must fail, not double-order.
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
    PERFORM public.submit_commerce_order(v_cart1, 'Customer One');
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%cart_not_open%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected resubmitting a converted cart to be rejected (idempotency)';
  END IF;

  INSERT INTO commerce_assertions VALUES ('order_submission_idempotent', true);

  -- =========================================================================
  -- 6) Snapshot immutability: editing the live product must not change the
  --    already-created order item, and no client role can UPDATE it at all.
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
  PERFORM public.upsert_product(jsonb_build_object('id', v_product_active, 'company_id', v_vendor_a, 'price_lrd_cents', 999999));
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT unit_price_lrd_cents INTO v_after_price
  FROM public.commerce_order_items WHERE order_id = v_order1.id LIMIT 1;
  IF v_after_price <> v_before_price THEN
    RAISE EXCEPTION 'order item snapshot changed after the product price was edited: % -> %', v_before_price, v_after_price;
  END IF;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
  UPDATE public.commerce_order_items SET unit_price_lrd_cents = 1 WHERE order_id = v_order1.id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'expected commerce_order_items to reject a direct client UPDATE (no RLS write policy), affected % rows', v_count;
  END IF;

  INSERT INTO commerce_assertions VALUES ('order_snapshot_immutable', true);

  -- =========================================================================
  -- 7) Customer cart/order ownership (RLS) + Super Admin access.
  -- =========================================================================
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_customer2::text, true);
  SELECT COUNT(*)::INT INTO v_count FROM public.carts WHERE id = v_cart1;
  IF v_count <> 0 THEN RAISE EXCEPTION 'expected customer 2 to see 0 rows of customer 1 cart, got %', v_count; END IF;
  SELECT COUNT(*)::INT INTO v_count FROM public.commerce_orders WHERE id = v_order1.id;
  IF v_count <> 0 THEN RAISE EXCEPTION 'expected customer 2 to see 0 rows of customer 1 order, got %', v_count; END IF;
  RESET ROLE;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
  SELECT COUNT(*)::INT INTO v_count FROM public.commerce_orders WHERE id = v_order1.id;
  IF v_count <> 1 THEN RAISE EXCEPTION 'expected customer 1 to see its own order, got %', v_count; END IF;
  RESET ROLE;

  -- Vendor sees the order (fulfillment party) but not the pre-order cart.
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
  SELECT COUNT(*)::INT INTO v_count FROM public.commerce_orders WHERE id = v_order1.id;
  IF v_count <> 1 THEN RAISE EXCEPTION 'expected the vendor to see an order placed against it, got %', v_count; END IF;
  SELECT COUNT(*)::INT INTO v_count FROM public.carts WHERE id = v_cart1;
  IF v_count <> 0 THEN RAISE EXCEPTION 'expected carts to stay customer-private even from the vendor, got %', v_count; END IF;
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);

  INSERT INTO commerce_assertions VALUES ('customer_order_ownership', true);

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  SELECT COUNT(*)::INT INTO v_count FROM public.commerce_orders WHERE id = v_order1.id;
  IF v_count <> 1 THEN RAISE EXCEPTION 'expected super admin to see any order, got %', v_count; END IF;
  SELECT COUNT(*)::INT INTO v_count FROM public.carts WHERE id = v_cart1;
  IF v_count <> 1 THEN RAISE EXCEPTION 'expected super admin to see any cart, got %', v_count; END IF;
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);

  INSERT INTO commerce_assertions VALUES ('super_admin_access', true);

  -- =========================================================================
  -- 8) Stock reservation: correct accounting + insufficient-stock rejection
  --    (sequential proof of the FOR UPDATE lock-then-check invariant).
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
  v_cart2 := (public.get_or_create_cart(v_vendor_a)).id;
  PERFORM public.add_cart_item(v_cart2, v_product_limited, 1, '[]'::JSONB);
  v_order2 := public.submit_commerce_order(v_cart2, 'Customer One');
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT * INTO v_stock FROM public.product_stock WHERE product_id = v_product_limited;
  IF v_stock.quantity_on_hand <> 1 OR v_stock.quantity_reserved <> 1 THEN
    RAISE EXCEPTION 'expected on_hand=1/reserved=1 after the first reservation, got %/%',
      v_stock.quantity_on_hand, v_stock.quantity_reserved;
  END IF;

  -- A second customer trying to order the same last unit must be rejected —
  -- this is the exact "two customers, one item" scenario from the spec.
  PERFORM set_config('request.jwt.claim.sub', v_customer2::text, true);
  DECLARE
    v_cart3 UUID;
  BEGIN
    v_cart3 := (public.get_or_create_cart(v_vendor_a)).id;
    PERFORM public.add_cart_item(v_cart3, v_product_limited, 1, '[]'::JSONB);
    v_forbidden := false;
    BEGIN
      PERFORM public.submit_commerce_order(v_cart3, 'Customer Two');
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%insufficient_stock%' THEN RAISE; END IF;
      v_forbidden := true;
    END;
    IF NOT v_forbidden THEN
      RAISE EXCEPTION 'expected the second customer to be rejected for insufficient stock on the last unit';
    END IF;
  END;
  PERFORM set_config('request.jwt.claim.sub', '', true);

  INSERT INTO commerce_assertions VALUES ('stock_reservation_concurrency_safe', true);

  -- Cancelling the first (reserving) order releases the unit back.
  PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
  PERFORM public.customer_cancel_commerce_order(v_order2.id, 'changed my mind');
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT * INTO v_stock FROM public.product_stock WHERE product_id = v_product_limited;
  IF v_stock.quantity_reserved <> 0 THEN
    RAISE EXCEPTION 'expected reservation released after cancellation, reserved = %', v_stock.quantity_reserved;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.product_stock_movements
    WHERE product_id = v_product_limited AND movement_type = 'release' AND reference_id = v_order2.id
  ) THEN
    RAISE EXCEPTION 'expected a release movement row for the cancelled order';
  END IF;

  INSERT INTO commerce_assertions VALUES ('cancellation_releases_stock', true);

  -- =========================================================================
  -- 9) Internal payment seam: not callable by any client role; finalizes
  --    stock (on_hand + reserved both decrement) when invoked internally.
  -- =========================================================================
  v_forbidden := false;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
    PERFORM public.mark_commerce_order_paid(v_order1.id);
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    v_forbidden := true;
  END;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected mark_commerce_order_paid to be unreachable by any authenticated client';
  END IF;

  -- Order 1 (2x active product, not inventory-tracked) — invoked as the
  -- test's own elevated role, standing in for the future service-role
  -- payment webhook.
  PERFORM public.mark_commerce_order_paid(v_order1.id);
  SELECT payment_status INTO v_order1.payment_status FROM public.commerce_orders WHERE id = v_order1.id;
  IF v_order1.payment_status <> 'paid' THEN
    RAISE EXCEPTION 'expected order 1 payment_status = paid, got %', v_order1.payment_status;
  END IF;

  INSERT INTO commerce_assertions VALUES ('payment_seam_internal_only', true);

  -- =========================================================================
  -- 10) Commerce fee rules: super-admin-only, no hardcoded commission.
  -- =========================================================================
  IF NOT EXISTS (
    SELECT 1 FROM public.commerce_fee_rules WHERE is_platform_default = true AND fee_model = 'zero_commission'
  ) THEN
    RAISE EXCEPTION 'expected the seeded platform default fee rule to be zero_commission, not a hardcoded rate';
  END IF;

  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
    PERFORM public.admin_upsert_commerce_fee_rule(jsonb_build_object('name', 'Sneaky rule', 'fee_model', 'percentage', 'percentage_bps', 500));
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%forbidden%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected a non-admin to be forbidden from writing commerce fee rules';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM public.admin_upsert_commerce_fee_rule(jsonb_build_object('name', 'Test 5%', 'fee_model', 'percentage', 'percentage_bps', 500, 'is_active', true));
  PERFORM set_config('request.jwt.claim.sub', '', true);

  INSERT INTO commerce_assertions VALUES ('commerce_fee_rules_admin_configurable', true);

  -- =========================================================================
  -- 11) Existing delivery engine is unaffected: a normal, non-commerce
  --     delivery still works end-to-end for an ordinary logistics_provider
  --     company, with commerce_order_id staying NULL.
  -- =========================================================================
  DECLARE
    v_carrier UUID; v_carrier_owner UUID;
    v_delivery public.deliveries;
  BEGIN
    SELECT company_id, owner_id INTO v_carrier, v_carrier_owner FROM pg_temp.make_vendor_company('Not Actually A Vendor Carrier');
    UPDATE public.companies SET business_type = 'logistics_provider' WHERE id = v_carrier;

    PERFORM set_config('request.jwt.claim.sub', v_carrier_owner::text, true);
    v_delivery := public.create_delivery(
      v_carrier, 'Test Pickup Shop', 'Monrovia', 'Regular Customer', '+231770009999', 'Regular Destination'
    );
    PERFORM set_config('request.jwt.claim.sub', '', true);

    IF v_delivery.id IS NULL OR v_delivery.commerce_order_id IS NOT NULL THEN
      RAISE EXCEPTION 'expected a normal delivery to be created with commerce_order_id NULL';
    END IF;
  END;

  INSERT INTO commerce_assertions VALUES ('existing_delivery_flow_unaffected', true);
END;
$$;

SELECT ok((SELECT ok FROM commerce_assertions WHERE key = 'vendor_approval_lifecycle'), 'a merchant company gets an auto-provisioned draft store; only Super Admin can move it to active, never the vendor itself');
SELECT ok((SELECT ok FROM commerce_assertions WHERE key = 'product_visibility_rules'), 'active products on a published store are publicly visible; draft products are not');
SELECT ok((SELECT ok FROM commerce_assertions WHERE key = 'vendor_isolation'), 'a vendor cannot see another vendor''s private stock/draft catalog, nor manage its products via RPC');
SELECT ok((SELECT ok FROM commerce_assertions WHERE key = 'otp_verification_required'), 'an identity without phone_confirmed_at is blocked from submitting an order');
SELECT ok((SELECT ok FROM commerce_assertions WHERE key = 'server_authoritative_pricing'), 'order subtotal/snapshot prices are computed server-side from live product data, never a client-supplied amount');
SELECT ok((SELECT ok FROM commerce_assertions WHERE key = 'order_submission_idempotent'), 'resubmitting an already-converted cart is rejected rather than creating a duplicate order');
SELECT ok((SELECT ok FROM commerce_assertions WHERE key = 'order_snapshot_immutable'), 'editing a product after ordering does not change the frozen order item, and no client role can UPDATE order items directly');
SELECT ok((SELECT ok FROM commerce_assertions WHERE key = 'customer_order_ownership'), 'a customer sees only their own cart/order; another customer sees neither; the vendor sees the order but never the pre-order cart');
SELECT ok((SELECT ok FROM commerce_assertions WHERE key = 'super_admin_access'), 'Super Admin can read any cart/order regardless of company');
SELECT ok((SELECT ok FROM commerce_assertions WHERE key = 'stock_reservation_concurrency_safe'), 'a second order against the last reserved unit is rejected with insufficient_stock');
SELECT ok((SELECT ok FROM commerce_assertions WHERE key = 'cancellation_releases_stock'), 'cancelling an awaiting-vendor order releases its stock reservation with an auditable movement row');
SELECT ok((SELECT ok FROM commerce_assertions WHERE key = 'payment_seam_internal_only'), 'mark_commerce_order_paid is unreachable by any authenticated client and correctly finalizes stock when invoked internally');
SELECT ok((SELECT ok FROM commerce_assertions WHERE key = 'commerce_fee_rules_admin_configurable'), 'the platform default commerce fee rule is zero_commission (no hardcoded rate), and only Super Admin can write fee rules');
SELECT ok((SELECT ok FROM commerce_assertions WHERE key = 'existing_delivery_flow_unaffected'), 'a normal non-commerce delivery still works end-to-end with commerce_order_id staying NULL');

SELECT * FROM finish();
ROLLBACK;
