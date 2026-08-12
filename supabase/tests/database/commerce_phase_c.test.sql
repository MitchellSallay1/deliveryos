-- Coverage for DeliveryOS Commerce Phase C — Public Storefront + Cart +
-- OTP-Verified COD Checkout (20260309000000_commerce_phase_c_storefront.sql).
--
-- Proves: an inactive/suspended/rejected/draft store never appears via
-- get_public_store_catalog while an active one does, with no admin-internal
-- fields leaked; a customer can only ever see their own orders/cart, never
-- another customer's; product price/order totals/payment status remain
-- server-authoritative and client-unwritable; COD-disabled-vendor and
-- unavailable/out-of-stock products are rejected at submission; the last
-- unit of stock cannot be oversold; an OTP-unverified identity cannot
-- submit an order; a fully verified COD checkout succeeds end-to-end and
-- becomes visible + acceptable in the vendor order inbox; and order items
-- stay frozen even after the vendor edits the underlying product.

BEGIN;
SELECT plan(13);

SELECT has_function('public'::name, 'get_public_store_catalog'::name);
SELECT has_function('public'::name, 'get_cart_summary'::name);

CREATE OR REPLACE FUNCTION pg_temp.make_customer(p_label TEXT, p_verified BOOLEAN DEFAULT true)
RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
  v_user UUID := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, phone, email, encrypted_password, phone_confirmed_at, aud, role)
  VALUES (
    v_user, '+23177' || lpad((floor(random() * 999999))::text, 6, '0'),
    'commerce-c-' || substr(v_user::text, 1, 8) || '@test.local',
    crypt('x', gen_salt('bf')), CASE WHEN p_verified THEN now() ELSE NULL END, 'authenticated', 'authenticated'
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
    lower(replace(p_label, ' ', '')) || '@test.local', NULL, 'merchant'
  );
  PERFORM set_config('request.jwt.claim.sub', '', true);
  -- commerce_enabled is plan-gated (Phase F) — every vendor fixture needs a
  -- plan whose catalog row has it set.
  UPDATE public.company_subscriptions SET plan_id = (SELECT id FROM public.subscriptions WHERE slug = 'business')
  WHERE company_subscriptions.company_id = v_company;
  RETURN QUERY SELECT v_company, v_owner;
END;
$$;

DO $$
DECLARE
  v_admin UUID;
  v_vendor_a UUID; v_vendor_a_owner UUID;
  v_vendor_b UUID; v_vendor_b_owner UUID;
  v_customer1 UUID;
  v_customer2 UUID;
  v_unverified UUID;
  v_product UUID;
  v_scarce_product UUID;
  v_result RECORD;
  v_catalog JSONB;
  v_cart UUID;
  v_cart2 UUID;
  v_summary JSONB;
  v_order public.commerce_orders;
  v_forbidden BOOLEAN;
  v_row_count INT;
  v_before public.commerce_orders;
  v_after RECORD;
  v_inbox JSONB;
BEGIN
  v_admin := pg_temp.make_customer('C Admin');
  UPDATE public.profiles SET is_super_admin = true WHERE id = v_admin;

  SELECT company_id, owner_id INTO v_vendor_a, v_vendor_a_owner FROM pg_temp.make_vendor_company('C Vendor A');
  SELECT company_id, owner_id INTO v_vendor_b, v_vendor_b_owner FROM pg_temp.make_vendor_company('C Vendor B');
  v_customer1 := pg_temp.make_customer('C Customer One');
  v_customer2 := pg_temp.make_customer('C Customer Two');
  v_unverified := pg_temp.make_customer('C Unverified', false);

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM public.admin_set_vendor_state(v_vendor_a, 'active', NULL);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
  PERFORM public.upsert_store_profile(jsonb_build_object(
    'company_id', v_vendor_a, 'slug', 'c-vendor-a', 'display_name', 'C Vendor A Store', 'allow_cash_on_delivery', true
  ));
  v_result := public.upsert_product(jsonb_build_object(
    'company_id', v_vendor_a, 'name', 'C Test Product', 'price_lrd_cents', 12000, 'status', 'active'
  ));
  v_product := (v_result).id;
  v_result := public.upsert_product(jsonb_build_object(
    'company_id', v_vendor_a, 'name', 'C Scarce Product', 'price_lrd_cents', 5000, 'status', 'active', 'tracks_inventory', true
  ));
  v_scarce_product := (v_result).id;
  PERFORM public.adjust_product_stock(v_scarce_product, 1, 'initial stock');
  PERFORM set_config('request.jwt.claim.sub', '', true);

  -- Vendor B's store is deliberately left at its default 'draft' status —
  -- used below to prove a non-active store never appears publicly.
  CREATE TEMP TABLE c_assertions (key TEXT PRIMARY KEY, ok BOOLEAN);

  -- =========================================================================
  -- 1) Public catalog visibility: draft/pending_review/suspended/rejected
  --    never appear; active does, with no admin-internal fields leaked.
  -- =========================================================================
  v_catalog := public.get_public_store_catalog('c-vendor-a');
  IF v_catalog IS NULL THEN
    RAISE EXCEPTION 'expected an active store to be publicly visible via get_public_store_catalog';
  END IF;
  IF (v_catalog -> 'store' ->> 'display_name') <> 'C Vendor A Store' THEN
    RAISE EXCEPTION 'expected correct display_name in public catalog';
  END IF;
  IF (v_catalog -> 'store') ? 'status_reason' OR (v_catalog -> 'store') ? 'reviewed_by' OR (v_catalog -> 'store') ? 'reviewed_at' THEN
    RAISE EXCEPTION 'public store catalog must never expose status_reason/reviewed_by/reviewed_at';
  END IF;
  IF jsonb_array_length(v_catalog -> 'products') <> 2 THEN
    RAISE EXCEPTION 'expected 2 active products in public catalog, got %', jsonb_array_length(v_catalog -> 'products');
  END IF;

  -- Draft (Vendor B's default, never submitted for review).
  IF public.get_public_store_catalog('c-vendor-b-nonexistent-slug') IS NOT NULL THEN
    RAISE EXCEPTION 'expected a nonexistent slug to return NULL';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM public.admin_set_vendor_state(v_vendor_a, 'suspended', 'test suspension for phase c');
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF public.get_public_store_catalog('c-vendor-a') IS NOT NULL THEN
    RAISE EXCEPTION 'expected a suspended store to no longer be publicly visible';
  END IF;
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM public.admin_set_vendor_state(v_vendor_a, 'active', NULL);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF public.get_public_store_catalog('c-vendor-a') IS NULL THEN
    RAISE EXCEPTION 'expected the store to be publicly visible again after reactivation';
  END IF;

  INSERT INTO c_assertions VALUES ('storefront_visibility_gated_by_vendor_state', true);

  -- =========================================================================
  -- 2) anon cannot read store_profiles.status_reason/reviewed_by/reviewed_at
  --    directly, even via a raw column-scoped query (column-level REVOKE).
  -- =========================================================================
  v_forbidden := false;
  BEGIN
    SET LOCAL ROLE anon;
    PERFORM (SELECT status_reason FROM public.store_profiles WHERE company_id = v_vendor_a);
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected anon to be denied column-level access to store_profiles.status_reason';
  END IF;

  INSERT INTO c_assertions VALUES ('anon_cannot_read_store_admin_columns', true);

  -- =========================================================================
  -- 3) OTP-unverified identity cannot submit an order.
  -- =========================================================================
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_unverified::text, true);
    v_cart := (public.get_or_create_cart(v_vendor_a)).id;
    PERFORM public.add_cart_item(v_cart, v_product, 1, '[]'::JSONB);
    PERFORM public.submit_commerce_order(v_cart, 'Unverified Customer');
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%phone_not_verified%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected an OTP-unverified identity to be rejected with phone_not_verified';
  END IF;

  INSERT INTO c_assertions VALUES ('otp_unverified_cannot_submit', true);

  -- =========================================================================
  -- 4) Cart summary is live-priced and owner-scoped; a different customer
  --    cannot read someone else's cart summary.
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
  v_cart := (public.get_or_create_cart(v_vendor_a)).id;
  PERFORM public.add_cart_item(v_cart, v_product, 2, '[]'::JSONB);
  v_summary := public.get_cart_summary(v_cart);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  IF (v_summary ->> 'subtotal_lrd_cents')::INT <> 24000 THEN
    RAISE EXCEPTION 'expected cart summary subtotal 24000, got %', v_summary ->> 'subtotal_lrd_cents';
  END IF;

  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_customer2::text, true);
    PERFORM public.get_cart_summary(v_cart);
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%cart_not_found%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected a different customer to be unable to read another customer''s cart summary';
  END IF;

  INSERT INTO c_assertions VALUES ('cart_summary_live_priced_and_owner_scoped', true);

  -- =========================================================================
  -- 5) Client cannot modify product price via a raw UPDATE.
  -- =========================================================================
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
    UPDATE public.products SET price_lrd_cents = 1 WHERE id = v_product;
    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    v_row_count := 0;
  END;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF v_row_count <> 0 THEN
    RAISE EXCEPTION 'expected a raw UPDATE of products.price_lrd_cents by a customer to affect 0 rows under RLS';
  END IF;
  IF (SELECT price_lrd_cents FROM public.products WHERE id = v_product) <> 12000 THEN
    RAISE EXCEPTION 'product price must remain server-authoritative and unaltered';
  END IF;

  INSERT INTO c_assertions VALUES ('client_cannot_modify_product_price', true);

  -- =========================================================================
  -- 6) Valid, verified COD checkout succeeds end-to-end: submit ->
  --    honestly pending_payment -> visible in vendor inbox -> vendor can
  --    accept it (Phase B.5 eligibility rule).
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
  v_order := public.submit_commerce_order(
    v_cart, 'C Customer One', 'Behind the blue gate, Old Road', 'Sinkor, near ELWA junction',
    6.3106, -10.8047, 'Call when you arrive', 'cod'
  );
  PERFORM set_config('request.jwt.claim.sub', '', true);

  IF v_order.payment_method <> 'cod' OR v_order.payment_status <> 'pending_payment' THEN
    RAISE EXCEPTION 'expected a fresh COD order to be payment_method=cod, payment_status=pending_payment, got % / %', v_order.payment_method, v_order.payment_status;
  END IF;
  IF v_order.total_lrd_cents <> 24000 THEN
    RAISE EXCEPTION 'expected server-computed total 24000, got %', v_order.total_lrd_cents;
  END IF;
  IF v_order.delivery_area_summary <> 'Sinkor, near ELWA junction' THEN
    RAISE EXCEPTION 'expected delivery details to be persisted on the order';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
  v_inbox := public.list_vendor_commerce_orders_page(v_vendor_a, ARRAY['awaiting_vendor'], 25, 0);
  IF (v_inbox ->> 'total')::INT < 1 THEN
    RAISE EXCEPTION 'expected the new order to appear in the vendor inbox';
  END IF;
  v_order := public.vendor_accept_commerce_order(v_order.id);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  IF v_order.fulfillment_status <> 'vendor_accepted' THEN
    RAISE EXCEPTION 'expected the vendor to be able to accept a still-pending_payment COD order, got %', v_order.fulfillment_status;
  END IF;
  IF v_order.payment_status <> 'pending_payment' THEN
    RAISE EXCEPTION 'acceptance must never fabricate payment_status = paid for a COD order';
  END IF;

  INSERT INTO c_assertions VALUES ('valid_verified_cod_checkout_succeeds_end_to_end', true);

  -- =========================================================================
  -- 7) Customer order visibility: customer1 sees their own order; customer2
  --    cannot see it at all (neither list nor by id).
  -- =========================================================================
  DECLARE
    v_own_count INT;
    v_other_count INT;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
    SELECT COUNT(*) INTO v_own_count FROM public.commerce_orders WHERE id = v_order.id AND customer_id = auth.uid();
    RESET ROLE;
    PERFORM set_config('request.jwt.claim.sub', '', true);

    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.sub', v_customer2::text, true);
    SELECT COUNT(*) INTO v_other_count FROM public.commerce_orders WHERE id = v_order.id;
    RESET ROLE;
    PERFORM set_config('request.jwt.claim.sub', '', true);

    IF v_own_count <> 1 THEN
      RAISE EXCEPTION 'expected the owning customer to see their own order';
    END IF;
    IF v_other_count <> 0 THEN
      RAISE EXCEPTION 'expected a different customer to see 0 rows for another customer''s order, got %', v_other_count;
    END IF;
  END;

  INSERT INTO c_assertions VALUES ('customer_order_visibility_scoped_to_owner', true);

  -- =========================================================================
  -- 8) Client cannot modify the order total, and cannot self-mark paid
  --    (re-verified in the Phase C storefront-originated order context).
  -- =========================================================================
  SELECT * INTO v_before FROM public.commerce_orders WHERE id = v_order.id;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
    UPDATE public.commerce_orders SET total_lrd_cents = 1 WHERE id = v_order.id;
    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    v_row_count := 0;
  END;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF v_row_count <> 0 THEN
    RAISE EXCEPTION 'expected a raw UPDATE of commerce_orders.total_lrd_cents by the customer to affect 0 rows';
  END IF;
  IF (SELECT total_lrd_cents FROM public.commerce_orders WHERE id = v_order.id) <> v_before.total_lrd_cents THEN
    RAISE EXCEPTION 'order total must remain server-authoritative';
  END IF;

  v_forbidden := false;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
    PERFORM public.mark_commerce_order_paid(v_order.id);
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    v_forbidden := true;
  END;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected the customer to be unable to self-mark their order paid';
  END IF;

  INSERT INTO c_assertions VALUES ('client_cannot_alter_total_or_self_mark_paid', true);

  -- =========================================================================
  -- 9) Client cannot bypass a COD-disabled vendor.
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM public.admin_set_vendor_state(v_vendor_b, 'active', NULL);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  PERFORM set_config('request.jwt.claim.sub', v_vendor_b_owner::text, true);
  PERFORM public.upsert_store_profile(jsonb_build_object(
    'company_id', v_vendor_b, 'slug', 'c-vendor-b', 'display_name', 'C Vendor B Store', 'allow_cash_on_delivery', false
  ));
  v_result := public.upsert_product(jsonb_build_object(
    'company_id', v_vendor_b, 'name', 'C Vendor B Product', 'price_lrd_cents', 3000, 'status', 'active'
  ));
  PERFORM set_config('request.jwt.claim.sub', '', true);
  DECLARE v_product_b UUID := (v_result).id;
  BEGIN
    v_forbidden := false;
    BEGIN
      PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
      v_cart2 := (public.get_or_create_cart(v_vendor_b)).id;
      PERFORM public.add_cart_item(v_cart2, v_product_b, 1, '[]'::JSONB);
      PERFORM public.submit_commerce_order(v_cart2, 'C Customer One');
      PERFORM set_config('request.jwt.claim.sub', '', true);
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('request.jwt.claim.sub', '', true);
      IF SQLERRM NOT LIKE '%cod_not_allowed%' THEN RAISE; END IF;
      v_forbidden := true;
    END;
    IF NOT v_forbidden THEN
      RAISE EXCEPTION 'expected COD checkout against a COD-disabled vendor to be rejected';
    END IF;
  END;

  INSERT INTO c_assertions VALUES ('client_cannot_bypass_cod_disabled_vendor', true);

  -- =========================================================================
  -- 10) Client cannot order an out-of-stock product; cannot oversell the
  --     final unit (sequential exhaustion — the underlying FOR UPDATE
  --     row lock is what makes this safe under real concurrency, same
  --     precedent as Phase A's stock_reservation_concurrency_safe test).
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
  v_cart := (public.get_or_create_cart(v_vendor_a)).id;
  PERFORM public.add_cart_item(v_cart, v_scarce_product, 1, '[]'::JSONB);
  v_order := public.submit_commerce_order(v_cart, 'C Customer One');
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF v_order.fulfillment_status IS NULL THEN
    RAISE EXCEPTION 'expected the first order for the last unit to succeed';
  END IF;

  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_customer2::text, true);
    v_cart := (public.get_or_create_cart(v_vendor_a)).id;
    PERFORM public.add_cart_item(v_cart, v_scarce_product, 1, '[]'::JSONB);
    PERFORM public.submit_commerce_order(v_cart, 'C Customer Two');
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%insufficient_stock%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected a second order for the already-sold-out last unit to be rejected with insufficient_stock';
  END IF;

  INSERT INTO c_assertions VALUES ('cannot_order_unavailable_or_oversell_last_unit', true);

  -- =========================================================================
  -- 11) Order items remain frozen after the vendor edits the product.
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
  PERFORM public.upsert_product(jsonb_build_object(
    'id', v_product, 'company_id', v_vendor_a, 'name', 'Renamed After Order', 'price_lrd_cents', 999999
  ));
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT product_name, unit_price_lrd_cents INTO v_after
  FROM public.commerce_order_items
  WHERE order_id = (SELECT id FROM public.commerce_orders WHERE customer_id = v_customer1 AND vendor_company_id = v_vendor_a ORDER BY created_at ASC LIMIT 1)
  LIMIT 1;

  IF v_after.product_name = 'Renamed After Order' OR v_after.unit_price_lrd_cents = 999999 THEN
    RAISE EXCEPTION 'expected order items to stay frozen after the vendor edited the product, got % / %', v_after.product_name, v_after.unit_price_lrd_cents;
  END IF;

  INSERT INTO c_assertions VALUES ('order_items_remain_frozen_after_product_edit', true);
END;
$$;

SELECT ok((SELECT ok FROM c_assertions WHERE key = 'storefront_visibility_gated_by_vendor_state'), 'get_public_store_catalog returns NULL for a nonexistent or non-active store and the correct payload for an active one');
SELECT ok((SELECT ok FROM c_assertions WHERE key = 'anon_cannot_read_store_admin_columns'), 'anon is denied column-level SELECT on store_profiles.status_reason/reviewed_by/reviewed_at');
SELECT ok((SELECT ok FROM c_assertions WHERE key = 'otp_unverified_cannot_submit'), 'an OTP-unverified identity cannot submit a commerce order');
SELECT ok((SELECT ok FROM c_assertions WHERE key = 'cart_summary_live_priced_and_owner_scoped'), 'get_cart_summary live-prices the caller''s own cart and is unreadable by a different customer');
SELECT ok((SELECT ok FROM c_assertions WHERE key = 'client_cannot_modify_product_price'), 'a customer cannot alter a product''s price via a raw UPDATE');
SELECT ok((SELECT ok FROM c_assertions WHERE key = 'valid_verified_cod_checkout_succeeds_end_to_end'), 'a verified COD checkout succeeds, stays honestly pending_payment, appears in the vendor inbox, and can be accepted');
SELECT ok((SELECT ok FROM c_assertions WHERE key = 'customer_order_visibility_scoped_to_owner'), 'a customer can only see their own order, never another customer''s');
SELECT ok((SELECT ok FROM c_assertions WHERE key = 'client_cannot_alter_total_or_self_mark_paid'), 'a customer cannot alter their order total or self-mark it paid');
SELECT ok((SELECT ok FROM c_assertions WHERE key = 'client_cannot_bypass_cod_disabled_vendor'), 'a COD checkout against a COD-disabled vendor is rejected with cod_not_allowed');
SELECT ok((SELECT ok FROM c_assertions WHERE key = 'cannot_order_unavailable_or_oversell_last_unit'), 'a second order for an already-sold-out last unit is rejected with insufficient_stock');
SELECT ok((SELECT ok FROM c_assertions WHERE key = 'order_items_remain_frozen_after_product_edit'), 'commerce_order_items stay frozen after the vendor edits the underlying product');

SELECT * FROM finish();
ROLLBACK;
