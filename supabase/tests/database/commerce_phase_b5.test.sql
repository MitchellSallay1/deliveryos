-- Coverage for DeliveryOS Commerce Phase B.5 — Payment Method Foundation +
-- COD (20260308230000_commerce_phase_b5_cod_payment.sql).
--
-- Proves: a COD order can be accepted by its vendor while genuinely NOT
-- marked paid (payment stays honestly pending_payment through acceptance);
-- an online-payment order cannot be accepted before a server-side payment
-- confirmation; a vendor's allow_cash_on_delivery flag gates COD order
-- submission; a different vendor cannot tamper with another vendor's
-- payment configuration or an order's payment fields (RPC and raw-table
-- paths both blocked); a customer cannot self-mark an order paid or
-- manipulate the server-computed order total/COD amount; an invalid or
-- not-yet-available payment method is rejected at submission; and the
-- dormant COD cash-collection sync seam correctly flips a linked order to
-- paid once wired up.

BEGIN;
SELECT plan(13);

SELECT has_function('public'::name, 'commerce_order_payment_eligible_for_acceptance'::name);
SELECT has_function('public'::name, 'submit_commerce_order'::name);
SELECT has_function('public'::name, 'upsert_store_profile'::name);
SELECT has_function('public'::name, 'trg_sync_commerce_order_payment_from_cod'::name);

CREATE OR REPLACE FUNCTION pg_temp.make_customer(p_label TEXT)
RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
  v_user UUID := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, phone, email, encrypted_password, phone_confirmed_at, aud, role)
  VALUES (
    v_user, '+23177' || lpad((floor(random() * 999999))::text, 6, '0'),
    'commerce-b5-' || substr(v_user::text, 1, 8) || '@test.local',
    crypt('x', gen_salt('bf')), now(), 'authenticated', 'authenticated'
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
  v_product UUID;
  v_result RECORD;
  v_cart UUID;
  v_order_cod public.commerce_orders;
  v_order_online public.commerce_orders;
  v_forbidden BOOLEAN;
  v_row_count INT;
  v_before public.commerce_orders;
  v_after public.commerce_orders;
  v_delivery_id UUID;
  v_payment_id UUID;
BEGIN
  v_admin := pg_temp.make_customer('B5 Admin');
  UPDATE public.profiles SET is_super_admin = true WHERE id = v_admin;

  SELECT company_id, owner_id INTO v_vendor_a, v_vendor_a_owner FROM pg_temp.make_vendor_company('B5 Vendor A');
  SELECT company_id, owner_id INTO v_vendor_b, v_vendor_b_owner FROM pg_temp.make_vendor_company('B5 Vendor B');
  v_customer1 := pg_temp.make_customer('B5 Customer One');
  v_customer2 := pg_temp.make_customer('B5 Customer Two');

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM public.admin_set_vendor_state(v_vendor_a, 'active', NULL);
  PERFORM public.admin_set_vendor_state(v_vendor_b, 'active', NULL);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  -- Vendor A opts into COD; Vendor B deliberately does NOT (tests the
  -- conservative default + explicit disablement path).
  PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
  PERFORM public.upsert_store_profile(jsonb_build_object(
    'company_id', v_vendor_a, 'slug', 'b5-vendor-a', 'display_name', 'B5 Vendor A', 'allow_cash_on_delivery', true
  ));
  v_result := public.upsert_product(jsonb_build_object(
    'company_id', v_vendor_a, 'name', 'B5 Test Product', 'price_lrd_cents', 15000, 'status', 'active'
  ));
  v_product := (v_result).id;
  PERFORM set_config('request.jwt.claim.sub', '', true);

  CREATE TEMP TABLE b5_assertions (key TEXT PRIMARY KEY, ok BOOLEAN);

  -- =========================================================================
  -- 1) COD order: vendor can accept it while it is genuinely, honestly still
  --    pending_payment — never fabricated as 'paid'.
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
  v_cart := (public.get_or_create_cart(v_vendor_a)).id;
  PERFORM public.add_cart_item(v_cart, v_product, 2, '[]'::JSONB);
  v_order_cod := public.submit_commerce_order(v_cart, 'B5 Customer One');
  PERFORM set_config('request.jwt.claim.sub', '', true);

  IF v_order_cod.payment_method <> 'cod' THEN
    RAISE EXCEPTION 'expected default payment_method = cod, got %', v_order_cod.payment_method;
  END IF;
  IF v_order_cod.payment_status <> 'pending_payment' THEN
    RAISE EXCEPTION 'expected a freshly submitted COD order to stay pending_payment, got %', v_order_cod.payment_status;
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
  v_order_cod := public.vendor_accept_commerce_order(v_order_cod.id);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  IF v_order_cod.fulfillment_status <> 'vendor_accepted' THEN
    RAISE EXCEPTION 'expected the COD order to be accepted, got fulfillment_status %', v_order_cod.fulfillment_status;
  END IF;
  IF v_order_cod.payment_status <> 'pending_payment' THEN
    RAISE EXCEPTION 'expected acceptance to NEVER fabricate payment_status = paid for a COD order, got %', v_order_cod.payment_status;
  END IF;

  INSERT INTO b5_assertions VALUES ('cod_accepted_honestly_unpaid', true);

  -- =========================================================================
  -- 2) Online-payment order: cannot be accepted before payment confirmation;
  --    becomes acceptable once the internal webhook seam marks it paid.
  --    submit_commerce_order rejects mtn_momo/orange_money as not yet
  --    usable, so this fixture is built via a direct INSERT bypassing it —
  --    the intended shape for when the future MoMo integration is enabled.
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
  v_cart := (public.get_or_create_cart(v_vendor_a)).id;
  PERFORM public.add_cart_item(v_cart, v_product, 1, '[]'::JSONB);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  INSERT INTO public.commerce_orders (
    customer_id, vendor_company_id, cart_id, customer_name, customer_phone,
    payment_method, subtotal_lrd_cents, total_lrd_cents
  ) VALUES (
    v_customer1, v_vendor_a, v_cart, 'B5 Customer One', '+231770000000',
    'mtn_momo', 15000, 15000
  ) RETURNING * INTO v_order_online;

  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
    PERFORM public.vendor_accept_commerce_order(v_order_online.id);
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%payment_not_confirmed%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected an unconfirmed mtn_momo order to be rejected with payment_not_confirmed';
  END IF;

  -- Internal webhook seam (invoked here as the elevated test role, standing
  -- in for the future service-role payment webhook) confirms payment.
  v_order_online := public.mark_commerce_order_paid(v_order_online.id);
  IF v_order_online.payment_status <> 'paid' THEN
    RAISE EXCEPTION 'expected mark_commerce_order_paid to set payment_status = paid, got %', v_order_online.payment_status;
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
  v_order_online := public.vendor_accept_commerce_order(v_order_online.id);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF v_order_online.fulfillment_status <> 'vendor_accepted' THEN
    RAISE EXCEPTION 'expected the now-paid online order to be accepted, got %', v_order_online.fulfillment_status;
  END IF;

  INSERT INTO b5_assertions VALUES ('online_payment_requires_confirmation', true);

  -- =========================================================================
  -- 3) Vendor B never opted into COD (conservative default) — a COD order
  --    submission against Vendor B is rejected with cod_not_allowed.
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_vendor_b_owner::text, true);
  v_result := public.upsert_product(jsonb_build_object(
    'company_id', v_vendor_b, 'name', 'B5 Vendor B Product', 'price_lrd_cents', 5000, 'status', 'active'
  ));
  PERFORM set_config('request.jwt.claim.sub', '', true);
  DECLARE v_product_b UUID := (v_result).id;
  BEGIN
    v_forbidden := false;
    BEGIN
      PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
      v_cart := (public.get_or_create_cart(v_vendor_b)).id;
      PERFORM public.add_cart_item(v_cart, v_product_b, 1, '[]'::JSONB);
      PERFORM public.submit_commerce_order(v_cart, 'B5 Customer One');
      PERFORM set_config('request.jwt.claim.sub', '', true);
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('request.jwt.claim.sub', '', true);
      IF SQLERRM NOT LIKE '%cod_not_allowed%' THEN RAISE; END IF;
      v_forbidden := true;
    END;
    IF NOT v_forbidden THEN
      RAISE EXCEPTION 'expected a COD order against a store with allow_cash_on_delivery=false to be rejected with cod_not_allowed';
    END IF;
  END;

  INSERT INTO b5_assertions VALUES ('vendor_cod_disabled_blocks_submission', true);

  -- =========================================================================
  -- 4) Invalid / not-yet-available payment methods are rejected server-side
  --    at submission — the client string is never trusted as-is.
  -- =========================================================================
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
    v_cart := (public.get_or_create_cart(v_vendor_a)).id;
    PERFORM public.add_cart_item(v_cart, v_product, 1, '[]'::JSONB);
    PERFORM public.submit_commerce_order(v_cart, 'B5 Customer One', NULL, NULL, NULL, NULL, NULL, 'bitcoin');
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%invalid_payment_method%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected an unrecognized payment method string to be rejected with invalid_payment_method';
  END IF;

  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
    v_cart := (public.get_or_create_cart(v_vendor_a)).id;
    PERFORM public.add_cart_item(v_cart, v_product, 1, '[]'::JSONB);
    PERFORM public.submit_commerce_order(v_cart, 'B5 Customer One', NULL, NULL, NULL, NULL, NULL, 'mtn_momo');
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%payment_method_not_available%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected mtn_momo to be rejected with payment_method_not_available (modeled, not yet usable)';
  END IF;

  INSERT INTO b5_assertions VALUES ('invalid_and_unavailable_payment_methods_rejected', true);

  -- =========================================================================
  -- 5) Cross-vendor payment-config tampering blocked: Vendor B cannot flip
  --    Vendor A's allow_cash_on_delivery via the RPC, nor via a raw UPDATE.
  -- =========================================================================
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_vendor_b_owner::text, true);
    PERFORM public.upsert_store_profile(jsonb_build_object(
      'company_id', v_vendor_a, 'slug', 'b5-vendor-a-hijack', 'display_name', 'Hijacked', 'allow_cash_on_delivery', false
    ));
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%forbidden%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected Vendor B to be forbidden from changing Vendor A''s store_profiles via the RPC';
  END IF;

  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.sub', v_vendor_b_owner::text, true);
    UPDATE public.store_profiles SET allow_cash_on_delivery = false WHERE company_id = v_vendor_a;
    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    v_row_count := 0;
  END;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF v_row_count <> 0 THEN
    RAISE EXCEPTION 'expected a raw UPDATE on store_profiles by a non-owning vendor to affect 0 rows under RLS, affected %', v_row_count;
  END IF;
  IF NOT (SELECT allow_cash_on_delivery FROM public.store_profiles WHERE company_id = v_vendor_a) THEN
    RAISE EXCEPTION 'Vendor A''s allow_cash_on_delivery must remain true — it must not have been tampered with';
  END IF;

  INSERT INTO b5_assertions VALUES ('cross_vendor_payment_config_tamper_blocked', true);

  -- =========================================================================
  -- 6) A customer cannot self-mark their own order paid or failed — the
  --    internal webhook seams stay unreachable from any authenticated role.
  -- =========================================================================
  v_forbidden := false;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
    PERFORM public.mark_commerce_order_paid(v_order_cod.id);
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    v_forbidden := true;
  END;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected mark_commerce_order_paid to be unreachable by an authenticated client';
  END IF;

  v_forbidden := false;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
    PERFORM public.mark_commerce_order_payment_failed(v_order_cod.id, 'self-inflicted');
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    v_forbidden := true;
  END;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected mark_commerce_order_payment_failed to be unreachable by an authenticated client';
  END IF;

  INSERT INTO b5_assertions VALUES ('customer_cannot_self_mark_payment', true);

  -- =========================================================================
  -- 6b) commerce_order_payment_eligible_for_acceptance is an internal helper
  --     only — no authenticated client (not even the owning vendor) may call
  --     it directly. vendor_accept_commerce_order (tests 1/2 above) proves it
  --     still works correctly when invoked internally, regardless of this
  --     revoke.
  -- =========================================================================
  v_forbidden := false;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
    PERFORM public.commerce_order_payment_eligible_for_acceptance(v_order_cod.id);
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    v_forbidden := true;
  END;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected commerce_order_payment_eligible_for_acceptance to be unreachable by any authenticated client, including the owning vendor';
  END IF;

  INSERT INTO b5_assertions VALUES ('eligibility_helper_not_directly_callable', true);

  -- =========================================================================
  -- 7) A customer cannot manipulate the COD amount / order total via a raw
  --    UPDATE — commerce_orders has no write RLS policy, so the attempt
  --    affects 0 rows and the server-computed total survives untouched.
  -- =========================================================================
  SELECT * INTO v_before FROM public.commerce_orders WHERE id = v_order_cod.id;

  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
    UPDATE public.commerce_orders SET total_lrd_cents = 1, subtotal_lrd_cents = 1 WHERE id = v_order_cod.id;
    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    v_row_count := 0;
  END;
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT * INTO v_after FROM public.commerce_orders WHERE id = v_order_cod.id;
  IF v_row_count <> 0 THEN
    RAISE EXCEPTION 'expected a raw UPDATE of commerce_orders by the owning customer to affect 0 rows under RLS, affected %', v_row_count;
  END IF;
  IF v_after.total_lrd_cents <> v_before.total_lrd_cents OR v_after.subtotal_lrd_cents <> v_before.subtotal_lrd_cents THEN
    RAISE EXCEPTION 'the server-computed order total/subtotal must never be client-alterable, got total % subtotal %', v_after.total_lrd_cents, v_after.subtotal_lrd_cents;
  END IF;

  INSERT INTO b5_assertions VALUES ('customer_cannot_manipulate_order_amount', true);

  -- =========================================================================
  -- 8) COD cash-collection sync seam: dormant until Phase D populates
  --    deliveries.commerce_order_id, but real and testable now — manually
  --    wire a delivery to the COD order, record its payment as collected,
  --    and confirm the trigger flips the linked order to paid.
  -- =========================================================================
  -- A fresh, still-pending COD order to sync (v_order_cod is already
  -- vendor_accepted from test 1 — reuse it; sync only requires
  -- payment_status = pending_payment, which it still honestly is).
  INSERT INTO public.deliveries (
    company_id, created_by, tracking_code, pickup_business_name, pickup_address,
    destination_address, customer_name, customer_phone, status, commerce_order_id
  ) VALUES (
    v_vendor_a, v_vendor_a_owner, public.generate_tracking_code(), 'B5 Test Vendor', 'B5 Test Pickup',
    'B5 Test Dropoff', 'B5 Customer One', '+231770000000', 'pending', v_order_cod.id
  ) RETURNING id INTO v_delivery_id;

  INSERT INTO public.payments (delivery_id, company_id, amount_lrd_cents, status)
  VALUES (v_delivery_id, v_vendor_a, v_order_cod.total_lrd_cents, 'pending')
  RETURNING id INTO v_payment_id;

  UPDATE public.payments SET status = 'collected' WHERE id = v_payment_id;

  SELECT payment_status INTO v_after.payment_status FROM public.commerce_orders WHERE id = v_order_cod.id;
  IF v_after.payment_status <> 'paid' THEN
    RAISE EXCEPTION 'expected the COD sync trigger to flip the linked commerce order to paid once cash is collected, got %', v_after.payment_status;
  END IF;

  INSERT INTO b5_assertions VALUES ('cod_cash_collection_sync_seam_works', true);
END;
$$;

SELECT ok((SELECT ok FROM b5_assertions WHERE key = 'cod_accepted_honestly_unpaid'), 'a COD order can be accepted by its vendor while genuinely still pending_payment — never fabricated as paid');
SELECT ok((SELECT ok FROM b5_assertions WHERE key = 'online_payment_requires_confirmation'), 'an online-payment order cannot be accepted before payment_status=paid, and becomes acceptable once the internal webhook seam confirms it');
SELECT ok((SELECT ok FROM b5_assertions WHERE key = 'vendor_cod_disabled_blocks_submission'), 'a vendor that has not enabled allow_cash_on_delivery rejects a COD order submission with cod_not_allowed');
SELECT ok((SELECT ok FROM b5_assertions WHERE key = 'invalid_and_unavailable_payment_methods_rejected'), 'an unrecognized payment method is rejected with invalid_payment_method, and a modeled-but-not-yet-usable method (mtn_momo) is rejected with payment_method_not_available');
SELECT ok((SELECT ok FROM b5_assertions WHERE key = 'cross_vendor_payment_config_tamper_blocked'), 'a different vendor cannot change another vendor''s COD setting via the RPC or a raw UPDATE');
SELECT ok((SELECT ok FROM b5_assertions WHERE key = 'customer_cannot_self_mark_payment'), 'mark_commerce_order_paid/mark_commerce_order_payment_failed remain unreachable by any authenticated client');
SELECT ok((SELECT ok FROM b5_assertions WHERE key = 'eligibility_helper_not_directly_callable'), 'commerce_order_payment_eligible_for_acceptance is an internal helper — no authenticated client, including the owning vendor, can call it directly');
SELECT ok((SELECT ok FROM b5_assertions WHERE key = 'customer_cannot_manipulate_order_amount'), 'a customer cannot alter the server-computed order total/subtotal (and therefore the COD amount) via a raw UPDATE');
SELECT ok((SELECT ok FROM b5_assertions WHERE key = 'cod_cash_collection_sync_seam_works'), 'once a delivery is linked to a COD order and its cash payment is recorded as collected, the sync trigger correctly flips the order to paid');

SELECT * FROM finish();
ROLLBACK;
