-- Coverage for DeliveryOS Commerce Phase D — Carrier Selection, Delivery
-- Request Conversion & Existing Delivery Engine Integration
-- (20260309100000_commerce_phase_d_carrier_delivery.sql).
--
-- Proves the full COD order -> vendor ready -> delivery request -> real,
-- differently-priced carrier offers -> customer selection -> carrier
-- acceptance -> real deliveries row -> pickup -> delivered -> COD
-- collected -> commerce payment_status='paid' pipeline works end-to-end
-- through the EXISTING marketplace/delivery engine, plus every security
-- and idempotency guarantee: another customer cannot see/select offers;
-- another vendor cannot convert someone else's order; duplicate
-- conversion is idempotent; the customer cannot alter the quoted amount;
-- an expired offer cannot be selected; a suspended carrier cannot be
-- selected; the customer cannot assign a rider; a carrier cannot read
-- another carrier's private accepted-job fields; a Commerce order can
-- never link to two deliveries.

BEGIN;
SELECT plan(14);

SELECT has_function('public'::name, 'request_commerce_order_delivery'::name);
SELECT has_function('public'::name, 'select_commerce_delivery_offer'::name);
SELECT has_function('public'::name, 'get_commerce_order_delivery_status'::name);

CREATE OR REPLACE FUNCTION pg_temp.make_customer(p_label TEXT)
RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
  v_user UUID := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, phone, email, encrypted_password, phone_confirmed_at, aud, role)
  VALUES (
    v_user, '+23177' || lpad((floor(random() * 999999))::text, 6, '0'),
    'commerce-d-' || substr(v_user::text, 1, 8) || '@test.local',
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
  v_vendor UUID; v_vendor_owner UUID;
  v_vendor_b UUID; v_vendor_b_owner UUID;
  v_carrier_a UUID; v_carrier_a_owner UUID;
  v_carrier_b UUID; v_carrier_b_owner UUID;
  v_customer1 UUID;
  v_customer2 UUID;
  v_product UUID;
  v_result RECORD;
  v_cart UUID;
  v_order public.commerce_orders;
  v_conv JSONB;
  v_status JSONB;
  v_offers JSONB;
  v_offer_a_id UUID;
  v_offer_b_id UUID;
  v_forbidden BOOLEAN;
  v_row_count INT;
  v_delivery public.deliveries;
  v_rider UUID;
  v_before_total INT;
BEGIN
  v_admin := pg_temp.make_customer('D Admin');
  UPDATE public.profiles SET is_super_admin = true WHERE id = v_admin;

  SELECT company_id, owner_id INTO v_vendor, v_vendor_owner FROM pg_temp.make_company('D Vendor', 'merchant');
  UPDATE public.companies SET address = '123 Broad Street, Monrovia' WHERE id = v_vendor;
  SELECT company_id, owner_id INTO v_vendor_b, v_vendor_b_owner FROM pg_temp.make_company('D Vendor B', 'merchant');
  SELECT company_id, owner_id INTO v_carrier_a, v_carrier_a_owner FROM pg_temp.make_company('D Carrier A', 'logistics_provider');
  SELECT company_id, owner_id INTO v_carrier_b, v_carrier_b_owner FROM pg_temp.make_company('D Carrier B', 'logistics_provider');
  v_customer1 := pg_temp.make_customer('D Customer One');
  v_customer2 := pg_temp.make_customer('D Customer Two');

  -- Carriers need a business+ plan for provider_network (starter/trial does
  -- not grant it) — upgrade both directly, bypassing the billing UI, same
  -- as any other test fixture shortcut in this suite.
  UPDATE public.company_subscriptions SET plan_id = (SELECT id FROM public.subscriptions WHERE slug = 'business')
  WHERE company_id IN (v_carrier_a, v_carrier_b);

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM public.admin_set_vendor_state(v_vendor, 'active', NULL);
  PERFORM public.admin_set_vendor_state(v_vendor_b, 'active', NULL);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  PERFORM set_config('request.jwt.claim.sub', v_vendor_owner::text, true);
  PERFORM public.upsert_store_profile(jsonb_build_object(
    'company_id', v_vendor, 'slug', 'd-vendor', 'display_name', 'D Vendor Store', 'allow_cash_on_delivery', true
  ));
  v_result := public.upsert_product(jsonb_build_object(
    'company_id', v_vendor, 'name', 'D Test Product', 'price_lrd_cents', 20000, 'status', 'active'
  ));
  v_product := (v_result).id;
  PERFORM set_config('request.jwt.claim.sub', '', true);

  -- Two carriers with DIFFERENT real, carrier-configured minimum fees —
  -- proves the customer sees genuinely different amounts, not a single
  -- fabricated/broadcast price.
  PERFORM set_config('request.jwt.claim.sub', v_carrier_a_owner::text, true);
  PERFORM public.upsert_provider_marketplace_profile(jsonb_build_object(
    'company_id', v_carrier_a, 'marketplace_enabled', true, 'accepting_jobs', true, 'minimum_delivery_fee_lrd_cents', 1500
  ));
  PERFORM set_config('request.jwt.claim.sub', '', true);

  PERFORM set_config('request.jwt.claim.sub', v_carrier_b_owner::text, true);
  PERFORM public.upsert_provider_marketplace_profile(jsonb_build_object(
    'company_id', v_carrier_b, 'marketplace_enabled', true, 'accepting_jobs', true, 'minimum_delivery_fee_lrd_cents', 2000
  ));
  PERFORM set_config('request.jwt.claim.sub', '', true);

  CREATE TEMP TABLE d_assertions (key TEXT PRIMARY KEY, ok BOOLEAN);

  -- =========================================================================
  -- Build a COD order through to ready_for_pickup.
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
  v_cart := (public.get_or_create_cart(v_vendor)).id;
  PERFORM public.add_cart_item(v_cart, v_product, 1, '[]'::JSONB);
  v_order := public.submit_commerce_order(v_cart, 'D Customer One', 'Behind the blue gate', 'Sinkor', NULL, NULL, NULL, 'cod');
  PERFORM set_config('request.jwt.claim.sub', '', true);

  PERFORM set_config('request.jwt.claim.sub', v_vendor_owner::text, true);
  PERFORM public.vendor_accept_commerce_order(v_order.id);
  PERFORM public.vendor_mark_order_preparing(v_order.id);
  v_order := public.vendor_mark_order_ready(v_order.id);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  -- =========================================================================
  -- 1) Another vendor cannot create a delivery request for this order.
  -- =========================================================================
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_vendor_b_owner::text, true);
    PERFORM public.request_commerce_order_delivery(v_order.id);
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%forbidden%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected a different vendor to be forbidden from converting another vendor''s order';
  END IF;

  INSERT INTO d_assertions VALUES ('another_vendor_cannot_convert', true);

  -- =========================================================================
  -- 2) Vendor converts the order; two real, differently-priced offers are
  --    created; a second call is idempotent (no duplicate request/offers).
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_vendor_owner::text, true);
  v_conv := public.request_commerce_order_delivery(v_order.id);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  IF (v_conv ->> 'offers_created')::INT <> 2 THEN
    RAISE EXCEPTION 'expected 2 real carrier offers to be created, got %', v_conv ->> 'offers_created';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_vendor_owner::text, true);
  v_conv := public.request_commerce_order_delivery(v_order.id);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  IF (v_conv ->> 'already_existed')::BOOLEAN IS NOT TRUE OR (v_conv ->> 'offers_created')::INT <> 0 THEN
    RAISE EXCEPTION 'expected a second conversion call to be idempotent (no new request/offers)';
  END IF;

  SELECT COUNT(*) INTO v_row_count FROM public.delivery_requests
  WHERE id = (SELECT delivery_request_id FROM public.commerce_orders WHERE id = v_order.id);
  IF v_row_count <> 1 THEN
    RAISE EXCEPTION 'expected exactly one delivery_requests row for this order, got %', v_row_count;
  END IF;

  INSERT INTO d_assertions VALUES ('conversion_creates_real_offers_and_is_idempotent', true);

  -- =========================================================================
  -- 3) Another customer cannot see or select offers for this order.
  -- =========================================================================
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_customer2::text, true);
    PERFORM public.get_commerce_order_delivery_status(v_order.id);
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%order_not_found%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected another customer to be unable to read this order''s carrier options';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
  v_status := public.get_commerce_order_delivery_status(v_order.id);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  v_offers := v_status -> 'offers';
  IF jsonb_array_length(v_offers) <> 2 THEN
    RAISE EXCEPTION 'expected the owning customer to see exactly 2 offers, got %', jsonb_array_length(v_offers);
  END IF;

  SELECT (o ->> 'offer_id')::UUID INTO v_offer_a_id FROM jsonb_array_elements(v_offers) o WHERE (o ->> 'quoted_amount_lrd_cents')::INT = 1500;
  SELECT (o ->> 'offer_id')::UUID INTO v_offer_b_id FROM jsonb_array_elements(v_offers) o WHERE (o ->> 'quoted_amount_lrd_cents')::INT = 2000;
  IF v_offer_a_id IS NULL OR v_offer_b_id IS NULL THEN
    RAISE EXCEPTION 'expected two distinct, real carrier-priced offers (1500 and 2000)';
  END IF;

  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_customer2::text, true);
    PERFORM public.select_commerce_delivery_offer(v_order.id, v_offer_a_id);
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%order_not_found%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected another customer to be forbidden from selecting an offer on this order';
  END IF;

  INSERT INTO d_assertions VALUES ('another_customer_cannot_see_or_select_offers', true);

  -- =========================================================================
  -- 4) Customer cannot change the quoted amount via a raw UPDATE.
  -- =========================================================================
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
    UPDATE public.delivery_offers SET quoted_amount_lrd_cents = 1 WHERE id = v_offer_a_id;
    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    v_row_count := 0;
  END;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF v_row_count <> 0 THEN
    RAISE EXCEPTION 'expected a raw UPDATE of delivery_offers.quoted_amount_lrd_cents by the customer to affect 0 rows';
  END IF;
  IF (SELECT quoted_amount_lrd_cents FROM public.delivery_offers WHERE id = v_offer_a_id) <> 1500 THEN
    RAISE EXCEPTION 'quoted amount must remain server/carrier-authoritative';
  END IF;

  INSERT INTO d_assertions VALUES ('customer_cannot_change_quoted_amount', true);

  -- =========================================================================
  -- 5) An expired offer cannot be selected.
  -- =========================================================================
  UPDATE public.delivery_offers SET expires_at = now() - interval '1 hour' WHERE id = v_offer_b_id;

  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
    PERFORM public.select_commerce_delivery_offer(v_order.id, v_offer_b_id);
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%offer_expired%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected an expired offer to be rejected with offer_expired';
  END IF;

  INSERT INTO d_assertions VALUES ('expired_offer_cannot_be_selected', true);

  -- =========================================================================
  -- 6) A suspended carrier cannot be selected (still resolves via the same
  --    provider_matches_delivery_request predicate the B2B flow uses).
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  UPDATE public.companies SET marketplace_suspended = true WHERE id = v_carrier_a;
  PERFORM set_config('request.jwt.claim.sub', '', true);

  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
    PERFORM public.select_commerce_delivery_offer(v_order.id, v_offer_a_id);
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%provider_not_available%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected a suspended carrier''s offer to be rejected with provider_not_available';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  UPDATE public.companies SET marketplace_suspended = false WHERE id = v_carrier_a;
  PERFORM set_config('request.jwt.claim.sub', '', true);

  INSERT INTO d_assertions VALUES ('suspended_carrier_cannot_be_selected', true);

  -- =========================================================================
  -- 7) Customer selects carrier A (now unsuspended); carrier B cannot
  --    accept the (unselected, now-expired) offer; carrier A accepts and
  --    the real deliveries row is created with correct linkage/amounts.
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
  PERFORM public.select_commerce_delivery_offer(v_order.id, v_offer_a_id);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_carrier_b_owner::text, true);
    PERFORM public.accept_marketplace_offer(v_offer_b_id, v_carrier_b);
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%offer_not_selected_by_customer%' AND SQLERRM NOT LIKE '%invalid_offer%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected carrier B to be rejected — its offer was never selected by the customer';
  END IF;

  v_before_total := v_order.subtotal_lrd_cents;

  PERFORM set_config('request.jwt.claim.sub', v_carrier_a_owner::text, true);
  PERFORM public.accept_marketplace_offer(v_offer_a_id, v_carrier_a);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT * INTO v_order FROM public.commerce_orders WHERE id = v_order.id;
  IF v_order.delivery_id IS NULL THEN
    RAISE EXCEPTION 'expected commerce_orders.delivery_id to be set after carrier acceptance';
  END IF;
  IF v_order.delivery_fee_lrd_cents <> 1500 OR v_order.total_lrd_cents <> v_before_total + 1500 THEN
    RAISE EXCEPTION 'expected the accepted offer''s amount to freeze onto commerce_orders.delivery_fee_lrd_cents/total_lrd_cents, got fee=% total=%', v_order.delivery_fee_lrd_cents, v_order.total_lrd_cents;
  END IF;

  SELECT * INTO v_delivery FROM public.deliveries WHERE id = v_order.delivery_id;
  IF v_delivery.commerce_order_id <> v_order.id THEN
    RAISE EXCEPTION 'expected the new deliveries row to link back via commerce_order_id';
  END IF;
  IF v_delivery.company_id <> v_carrier_a THEN
    RAISE EXCEPTION 'expected the delivery to be owned by the accepting carrier';
  END IF;
  IF v_delivery.amount_to_collect_lrd_cents <> v_before_total + 1500 THEN
    RAISE EXCEPTION 'expected amount_to_collect_lrd_cents = subtotal + delivery fee (COD due), got %', v_delivery.amount_to_collect_lrd_cents;
  END IF;
  IF v_delivery.delivery_fee_lrd_cents <> 1500 THEN
    RAISE EXCEPTION 'expected the carrier''s delivery fee to be preserved on the delivery row';
  END IF;

  INSERT INTO d_assertions VALUES ('carrier_accept_creates_correctly_linked_delivery', true);

  -- =========================================================================
  -- 8) Commerce order cannot link to two deliveries (DB-level defense in
  --    depth: unique index on deliveries.commerce_order_id).
  -- =========================================================================
  v_forbidden := false;
  BEGIN
    INSERT INTO public.deliveries (
      company_id, tracking_code, pickup_business_name, pickup_address,
      customer_name, customer_phone, destination_address, status, commerce_order_id
    ) VALUES (
      v_carrier_a, public.generate_tracking_code(), 'Test', 'Test address',
      'Test', '+231770000000', 'Test destination', 'pending', v_order.id
    );
  EXCEPTION WHEN unique_violation THEN
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected a second deliveries row for the same commerce_order_id to violate the unique index';
  END IF;

  INSERT INTO d_assertions VALUES ('commerce_order_cannot_link_two_deliveries', true);

  -- =========================================================================
  -- 9) Customer cannot assign a rider to the delivery.
  -- =========================================================================
  INSERT INTO public.riders (company_id, rider_code, full_name, phone, status)
  VALUES (v_carrier_a, 'D-RIDER-1', 'Test Rider', '+231881234567', 'available')
  RETURNING id INTO v_rider;

  v_forbidden := false;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
    PERFORM public.assign_delivery_rider(v_order.delivery_id, v_rider);
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    v_forbidden := true;
  END;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected the customer to be forbidden from assigning a rider';
  END IF;

  INSERT INTO d_assertions VALUES ('customer_cannot_assign_rider', true);

  -- =========================================================================
  -- 10) A carrier cannot read another carrier's private accepted-job
  --     fields (pickup/destination/customer contact) via the marketplace
  --     jobs listing.
  -- =========================================================================
  DECLARE
    v_jobs_b JSONB;
    v_leaked BOOLEAN;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_carrier_b_owner::text, true);
    v_jobs_b := public.list_marketplace_jobs_page(v_carrier_b, NULL, 25, 0);
    PERFORM set_config('request.jwt.claim.sub', '', true);

    SELECT EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_jobs_b -> 'items') j
      WHERE (j ->> 'delivery_request_id')::UUID = (SELECT delivery_request_id FROM public.commerce_orders WHERE id = v_order.id)
        AND j ->> 'customer_phone' IS NOT NULL
    ) INTO v_leaked;
    IF v_leaked THEN
      RAISE EXCEPTION 'expected carrier B to never see customer contact details for an offer it did not accept';
    END IF;
  END;

  INSERT INTO d_assertions VALUES ('carrier_cannot_read_other_carrier_private_job_fields', true);

  -- =========================================================================
  -- 11) End-to-end: pickup -> handed_to_carrier; delivered -> COD
  --     collected -> commerce payment_status = paid; completed.
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_carrier_a_owner::text, true);
  PERFORM public.assign_delivery_rider(v_order.delivery_id, v_rider);
  PERFORM public.transition_delivery_status(v_order.delivery_id, 'accepted', 'rider en route');
  PERFORM public.transition_delivery_status(v_order.delivery_id, 'picked_up', 'picked up from vendor');
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT * INTO v_order FROM public.commerce_orders WHERE id = v_order.id;
  IF v_order.fulfillment_status <> 'handed_to_carrier' THEN
    RAISE EXCEPTION 'expected fulfillment_status = handed_to_carrier after pickup, got %', v_order.fulfillment_status;
  END IF;
  IF v_order.payment_status <> 'pending_payment' THEN
    RAISE EXCEPTION 'COD must still be honestly pending at pickup, got %', v_order.payment_status;
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_carrier_a_owner::text, true);
  PERFORM public.transition_delivery_status(v_order.delivery_id, 'in_transit', 'on the way');
  PERFORM public.transition_delivery_status(v_order.delivery_id, 'delivered', 'delivered to customer');
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT * INTO v_order FROM public.commerce_orders WHERE id = v_order.id;
  IF v_order.fulfillment_status <> 'completed' THEN
    RAISE EXCEPTION 'expected fulfillment_status = completed after delivery, got %', v_order.fulfillment_status;
  END IF;
  IF v_order.payment_status <> 'paid' THEN
    RAISE EXCEPTION 'expected the COD collection sync to mark the order paid, got %', v_order.payment_status;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.payments WHERE delivery_id = v_order.delivery_id AND status = 'collected'
      AND amount_lrd_cents = v_order.subtotal_lrd_cents + v_order.delivery_fee_lrd_cents
  ) THEN
    RAISE EXCEPTION 'expected a payments row for the combined product+delivery COD amount, marked collected';
  END IF;

  INSERT INTO d_assertions VALUES ('e2e_pickup_delivered_cod_sync_to_paid', true);
END;
$$;

SELECT ok((SELECT ok FROM d_assertions WHERE key = 'another_vendor_cannot_convert'), 'a different vendor cannot create a delivery request for another vendor''s order');
SELECT ok((SELECT ok FROM d_assertions WHERE key = 'conversion_creates_real_offers_and_is_idempotent'), 'request_commerce_order_delivery creates real, per-carrier-priced offers and a second call is idempotent');
SELECT ok((SELECT ok FROM d_assertions WHERE key = 'another_customer_cannot_see_or_select_offers'), 'a different customer cannot read or select offers on someone else''s order');
SELECT ok((SELECT ok FROM d_assertions WHERE key = 'customer_cannot_change_quoted_amount'), 'a customer cannot alter a carrier''s quoted amount via a raw UPDATE');
SELECT ok((SELECT ok FROM d_assertions WHERE key = 'expired_offer_cannot_be_selected'), 'an expired offer cannot be selected');
SELECT ok((SELECT ok FROM d_assertions WHERE key = 'suspended_carrier_cannot_be_selected'), 'a marketplace-suspended carrier cannot be selected');
SELECT ok((SELECT ok FROM d_assertions WHERE key = 'carrier_accept_creates_correctly_linked_delivery'), 'the customer''s selection gates carrier acceptance, and acceptance creates one correctly-linked, correctly-priced deliveries row');
SELECT ok((SELECT ok FROM d_assertions WHERE key = 'commerce_order_cannot_link_two_deliveries'), 'a Commerce order can never link to two deliveries (DB-level unique index)');
SELECT ok((SELECT ok FROM d_assertions WHERE key = 'customer_cannot_assign_rider'), 'a customer cannot assign a rider to the delivery');
SELECT ok((SELECT ok FROM d_assertions WHERE key = 'carrier_cannot_read_other_carrier_private_job_fields'), 'a carrier cannot see another carrier''s private accepted-job customer contact fields');
SELECT ok((SELECT ok FROM d_assertions WHERE key = 'e2e_pickup_delivered_cod_sync_to_paid'), 'pickup syncs fulfillment_status to handed_to_carrier, delivery syncs to completed, and COD collection syncs commerce payment_status to paid');

SELECT * FROM finish();
ROLLBACK;
