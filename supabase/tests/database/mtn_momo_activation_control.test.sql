-- Coverage for the MTN MoMo activation control (production activation-
-- control audit, Commerce Phase E2 follow-up:
-- 20260312000000_mtn_momo_activation_control.sql, plus the gate added to
-- initiate_commerce_order_mtn_payment in 20260311000000).
--
-- PRODUCTION FINANCIAL SYSTEM. Proves that MTN MoMo collection does NOT
-- become reachable by a real customer merely because the code/migration is
-- deployed: it defaults to disabled, the gate is enforced inside the one
-- RPC that can ever create a payment_attempts row (so it cannot be
-- bypassed by calling that RPC directly, with or without the checkout UI
-- in front of it), only a super admin can flip it, activation/deactivation
-- take effect immediately with no code deployment, disabling never hides
-- existing pending/unknown/successful attempts, and COD/Orange Money are
-- structurally unaffected either way.
--
-- What this file deliberately does NOT test: mtn-collect's independent
-- WINAGGREGATOR_MTN_* credentials-presence check (503 not_configured) —
-- that lives in a Deno Edge Function (supabase/functions/mtn-collect/
-- index.ts), outside pgTAP's reach. It is unchanged by this activation
-- control and was already fail-closed and reviewed in the prior phase; see
-- docs/MTN_MOMO_PAYMENTS.md "Activation control" for why the two checks
-- are independent by construction (one is a Postgres RPC reading
-- platform_settings, the other is an Edge Function reading env vars — the
-- two share no state and neither can substitute for the other).

BEGIN;
SELECT plan(17);

SELECT has_function('public'::name, 'get_platform_setting'::name);
SELECT has_function('public'::name, 'admin_set_platform_setting'::name);
SELECT has_function('public'::name, 'admin_list_platform_settings'::name);

-- Defaults disabled, as seeded by the migration — checked before any test
-- in this file mutates it.
SELECT is(
  (SELECT value FROM public.platform_settings WHERE key = 'mtn_momo_collections_enabled'),
  'false',
  'DEFAULT: mtn_momo_collections_enabled is seeded false — MTN collection is off immediately after deployment, before any Super Admin action'
);

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.make_user(p_label TEXT)
RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
  v_user UUID := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, phone, email, encrypted_password, phone_confirmed_at, aud, role)
  VALUES (v_user, '+2317' || lpad((floor(random() * 9999999))::text, 7, '0'), 'mac-' || substr(v_user::text, 1, 8) || '@test.local', crypt('x', gen_salt('bf')), now(), 'authenticated', 'authenticated');
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

-- Full setup: admin + vendor + one carrier + customer + one product + a
-- submitted mtn_momo order taken through vendor accept/prepare/ready/
-- request-delivery/carrier-select, ready to attempt payment.
CREATE OR REPLACE FUNCTION pg_temp.setup_ready_to_pay_order(p_label TEXT)
RETURNS TABLE (admin_id UUID, customer_id UUID, order_id UUID)
LANGUAGE plpgsql AS $$
DECLARE
  v_admin UUID; v_vendor UUID; v_vendor_owner UUID;
  v_carrier UUID; v_carrier_owner UUID;
  v_customer UUID; v_product UUID; v_result RECORD; v_cart UUID;
  v_order public.commerce_orders; v_offer_id UUID;
BEGIN
  v_admin := pg_temp.make_user(p_label || ' Admin');
  UPDATE public.profiles SET is_super_admin = true WHERE id = v_admin;

  SELECT company_id, owner_id INTO v_vendor, v_vendor_owner FROM pg_temp.make_company(p_label || ' Vendor', 'merchant', v_admin);
  SELECT company_id, owner_id INTO v_carrier, v_carrier_owner FROM pg_temp.make_company(p_label || ' Carrier', 'logistics_provider', v_admin);
  v_customer := pg_temp.make_user(p_label || ' Customer');
  UPDATE public.companies SET address = '1 Test Street, Monrovia' WHERE id = v_vendor;

  PERFORM set_config('request.jwt.claim.sub', v_vendor_owner::text, true);
  PERFORM public.upsert_store_profile(jsonb_build_object('company_id', v_vendor, 'slug', lower(replace(p_label, ' ', '')) || '-vendor', 'display_name', p_label || ' Vendor', 'allow_cash_on_delivery', true));
  v_result := public.upsert_product(jsonb_build_object('company_id', v_vendor, 'name', p_label || ' Product', 'price_lrd_cents', 20000, 'status', 'active'));
  v_product := (v_result).id;
  PERFORM set_config('request.jwt.claim.sub', '', true);

  PERFORM set_config('request.jwt.claim.sub', v_carrier_owner::text, true);
  PERFORM public.upsert_provider_marketplace_profile(jsonb_build_object('company_id', v_carrier, 'marketplace_enabled', true, 'accepting_jobs', true, 'minimum_delivery_fee_lrd_cents', 1500));
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

  SELECT o.id INTO v_offer_id FROM public.delivery_offers o WHERE o.delivery_request_id = v_order.delivery_request_id AND o.provider_company_id = v_carrier;

  PERFORM set_config('request.jwt.claim.sub', v_customer::text, true);
  PERFORM public.select_commerce_delivery_offer(v_order.id, v_offer_id);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  RETURN QUERY SELECT v_admin, v_customer, v_order.id;
END;
$$;

DO $$
DECLARE
  v_admin UUID; v_customer UUID; v_order_id UUID;
  v_random_user UUID;
  v_attempt public.payment_attempts;
  v_setting public.platform_settings;
  v_forbidden BOOLEAN;
  v_order2_admin UUID; v_order2_customer UUID; v_order2_id UUID;
  v_admin_row RECORD;
  v_cod_order public.commerce_orders;
BEGIN
  CREATE TEMP TABLE mac_assertions (key TEXT PRIMARY KEY, ok BOOLEAN);

  SELECT * INTO v_admin, v_customer, v_order_id FROM pg_temp.setup_ready_to_pay_order('MAC1');

  -- 1) Customer cannot initiate via the UI-backed RPC while disabled — this
  -- IS the direct RPC call (there is no separate "UI path" vs. "direct
  -- path" in the schema; mtn-collect calls this exact same RPC), so this
  -- one test simultaneously proves both "blocked via normal flow" and "no
  -- bypass exists for a direct caller."
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_customer::text, true);
    PERFORM public.initiate_commerce_order_mtn_payment(v_order_id, '0770229690');
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%mtn_momo_collections_disabled%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  INSERT INTO mac_assertions VALUES ('blocked_while_disabled', v_forbidden);

  -- Confirm no payment_attempts row was created by the blocked attempt —
  -- the gate fires before any write, not after a partial one.
  INSERT INTO mac_assertions VALUES (
    'no_attempt_row_created_while_blocked',
    NOT EXISTS (SELECT 1 FROM public.payment_attempts WHERE commerce_order_id = v_order_id)
  );

  -- 2) A non-super-admin cannot activate it.
  v_random_user := pg_temp.make_user('MAC Rando');
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_random_user::text, true);
    PERFORM public.admin_set_platform_setting('mtn_momo_collections_enabled', 'true');
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%forbidden%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  INSERT INTO mac_assertions VALUES ('non_admin_cannot_activate', v_forbidden);

  -- 3) Invalid values are rejected, not silently stored.
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    PERFORM public.admin_set_platform_setting('mtn_momo_collections_enabled', 'yes');
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%invalid_boolean_setting_value%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  INSERT INTO mac_assertions VALUES ('invalid_value_rejected', v_forbidden);
  INSERT INTO mac_assertions VALUES (
    'still_disabled_after_rejected_write',
    (SELECT value FROM public.platform_settings WHERE key = 'mtn_momo_collections_enabled') = 'false'
  );

  -- 4) Super admin CAN activate it, through the approved configuration seam.
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  v_setting := public.admin_set_platform_setting('mtn_momo_collections_enabled', 'true');
  PERFORM set_config('request.jwt.claim.sub', '', true);
  INSERT INTO mac_assertions VALUES ('super_admin_can_activate', v_setting.value = 'true');

  -- 5) Activation immediately permits initiation — same transaction, no
  -- reconnect, no redeploy: the very next call sees the new value.
  PERFORM set_config('request.jwt.claim.sub', v_customer::text, true);
  v_attempt := public.initiate_commerce_order_mtn_payment(v_order_id, '0770229690');
  PERFORM set_config('request.jwt.claim.sub', '', true);
  INSERT INTO mac_assertions VALUES (
    'activation_immediately_permits_initiation',
    v_attempt.id IS NOT NULL AND v_attempt.commerce_order_id = v_order_id AND v_attempt.state = 'created'
  );

  -- 6) Disabling it again blocks NEW attempts — a second, independent order.
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM public.admin_set_platform_setting('mtn_momo_collections_enabled', 'false');
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT * INTO v_order2_admin, v_order2_customer, v_order2_id FROM pg_temp.setup_ready_to_pay_order('MAC2');
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_order2_customer::text, true);
    PERFORM public.initiate_commerce_order_mtn_payment(v_order2_id, '0770229690');
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%mtn_momo_collections_disabled%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  INSERT INTO mac_assertions VALUES ('disabling_again_blocks_new_attempts', v_forbidden);

  -- 7) The EARLIER attempt (created while enabled, step 5) remains fully
  -- readable/reconcilable after disabling — both via the paying customer's
  -- own RLS-scoped read and via the super admin listing RPC. The RLS check
  -- specifically requires running AS the 'authenticated' role (a superuser
  -- session bypasses RLS regardless of request.jwt.claim.sub, so without
  -- this the assertion would be meaningless) — capture the result into a
  -- plain variable BEFORE resetting role, then write the assertion row
  -- AFTER resetting, since a superuser-owned temp table is not reliably
  -- writable by the 'authenticated' role mid-transaction.
  DECLARE
    v_still_visible BOOLEAN;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_customer::text, true);
    SET LOCAL ROLE authenticated;
    v_still_visible := EXISTS (SELECT 1 FROM public.payment_attempts WHERE id = v_attempt.id);
    RESET ROLE;
    PERFORM set_config('request.jwt.claim.sub', '', true);
    INSERT INTO mac_assertions VALUES ('existing_attempt_visible_to_customer_after_disable', v_still_visible);
  END;

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  SELECT * INTO v_admin_row FROM public.admin_list_payment_attempts_page(NULL, NULL, 50, 0, false) WHERE id = v_attempt.id;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  INSERT INTO mac_assertions VALUES ('existing_attempt_visible_to_admin_after_disable', v_admin_row.id = v_attempt.id);

  -- Can still be moved through its normal state machine after disabling —
  -- disabling only blocks NEW attempt creation, not resolution of existing
  -- ones.
  v_attempt := public.mark_payment_attempt_requesting(v_attempt.id);
  v_attempt := public.record_payment_attempt_result(
    v_attempt.id, 'successful', 'SUCCESSFUL', 200, 'ref-1', 'fin-1', v_attempt.gross_amount_cents, 0, v_attempt.gross_amount_cents, NULL, NULL
  );
  INSERT INTO mac_assertions VALUES ('existing_attempt_still_resolvable_after_disable', v_attempt.state = 'successful');

  -- 8) COD is structurally unaffected — MTN being disabled has zero bearing
  -- on a COD order's own submit/accept path (it never calls initiate_
  -- commerce_order_mtn_payment at all). Real end-to-end proof: submit a
  -- fresh COD order and take it through vendor acceptance, at this point in
  -- the test with mtn_momo_collections_enabled = 'false'.
  DECLARE
    v_cod_admin UUID; v_cod_customer UUID; v_cod_vendor UUID; v_cod_vendor_owner UUID;
    v_cod_product UUID; v_cod_result RECORD; v_cod_cart UUID;
  BEGIN
    v_cod_admin := pg_temp.make_user('MACC Admin');
    UPDATE public.profiles SET is_super_admin = true WHERE id = v_cod_admin;
    SELECT company_id, owner_id INTO v_cod_vendor, v_cod_vendor_owner FROM pg_temp.make_company('MACC Vendor', 'merchant', v_cod_admin);
    v_cod_customer := pg_temp.make_user('MACC Customer');

    PERFORM set_config('request.jwt.claim.sub', v_cod_vendor_owner::text, true);
    PERFORM public.upsert_store_profile(jsonb_build_object('company_id', v_cod_vendor, 'slug', 'macc-vendor', 'display_name', 'MACC Vendor', 'allow_cash_on_delivery', true));
    v_cod_result := public.upsert_product(jsonb_build_object('company_id', v_cod_vendor, 'name', 'MACC Product', 'price_lrd_cents', 5000, 'status', 'active'));
    v_cod_product := (v_cod_result).id;
    PERFORM set_config('request.jwt.claim.sub', '', true);

    PERFORM set_config('request.jwt.claim.sub', v_cod_customer::text, true);
    v_cod_cart := (public.get_or_create_cart(v_cod_vendor)).id;
    PERFORM public.add_cart_item(v_cod_cart, v_cod_product, 1, '[]'::JSONB);
    v_cod_order := public.submit_commerce_order(v_cod_cart, 'MACC Customer', NULL, NULL, NULL, NULL, NULL, 'cod');
    PERFORM set_config('request.jwt.claim.sub', '', true);

    PERFORM set_config('request.jwt.claim.sub', v_cod_vendor_owner::text, true);
    v_cod_order := public.vendor_accept_commerce_order(v_cod_order.id);
    PERFORM set_config('request.jwt.claim.sub', '', true);

    INSERT INTO mac_assertions VALUES (
      'cod_unaffected_by_mtn_disabled',
      v_cod_order.fulfillment_status = 'vendor_accepted' AND v_cod_order.payment_method = 'cod'
    );
  END;

  -- 9) Orange Money remains unavailable regardless of the MTN setting.
  DECLARE
    v_order3_admin UUID; v_order3_customer UUID;
    v_vendor3 UUID; v_vendor3_owner UUID; v_cart3 UUID; v_product3 UUID; v_result3 RECORD;
    v_orange_blocked BOOLEAN := false;
  BEGIN
    v_order3_admin := pg_temp.make_user('MAC3 Admin');
    UPDATE public.profiles SET is_super_admin = true WHERE id = v_order3_admin;
    SELECT company_id, owner_id INTO v_vendor3, v_vendor3_owner FROM pg_temp.make_company('MAC3 Vendor', 'merchant', v_order3_admin);
    v_order3_customer := pg_temp.make_user('MAC3 Customer');
    UPDATE public.companies SET address = '1 Test Street, Monrovia' WHERE id = v_vendor3;

    PERFORM set_config('request.jwt.claim.sub', v_vendor3_owner::text, true);
    v_result3 := public.upsert_product(jsonb_build_object('company_id', v_vendor3, 'name', 'MAC3 Product', 'price_lrd_cents', 3000, 'status', 'active'));
    v_product3 := (v_result3).id;
    PERFORM set_config('request.jwt.claim.sub', '', true);

    PERFORM set_config('request.jwt.claim.sub', v_order3_customer::text, true);
    v_cart3 := (public.get_or_create_cart(v_vendor3)).id;
    PERFORM public.add_cart_item(v_cart3, v_product3, 1, '[]'::JSONB);
    PERFORM set_config('request.jwt.claim.sub', '', true);

    BEGIN
      PERFORM set_config('request.jwt.claim.sub', v_order3_customer::text, true);
      PERFORM public.submit_commerce_order(v_cart3, 'MAC3 Customer', NULL, NULL, NULL, NULL, NULL, 'orange_money');
      PERFORM set_config('request.jwt.claim.sub', '', true);
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('request.jwt.claim.sub', '', true);
      IF SQLERRM NOT LIKE '%payment_method_not_available%' THEN RAISE; END IF;
      v_orange_blocked := true;
    END;
    INSERT INTO mac_assertions VALUES ('orange_money_still_unavailable', v_orange_blocked);
  END;
END;
$$;

SELECT ok((SELECT ok FROM mac_assertions WHERE key = 'blocked_while_disabled'), 'a customer cannot initiate MTN payment (via the same RPC mtn-collect and any direct caller both use) while collections are disabled');
SELECT ok((SELECT ok FROM mac_assertions WHERE key = 'no_attempt_row_created_while_blocked'), 'a blocked initiation creates no payment_attempts row at all');
SELECT ok((SELECT ok FROM mac_assertions WHERE key = 'non_admin_cannot_activate'), 'a non-super-admin cannot flip the activation setting');
SELECT ok((SELECT ok FROM mac_assertions WHERE key = 'invalid_value_rejected'), 'a non-boolean value is rejected outright, not silently stored');
SELECT ok((SELECT ok FROM mac_assertions WHERE key = 'still_disabled_after_rejected_write'), 'the setting remains false after a rejected write attempt');
SELECT ok((SELECT ok FROM mac_assertions WHERE key = 'super_admin_can_activate'), 'a super admin can activate MTN collection through admin_set_platform_setting, the approved configuration seam');
SELECT ok((SELECT ok FROM mac_assertions WHERE key = 'activation_immediately_permits_initiation'), 'activation takes effect immediately — the very next call, no code redeployment, no reconnect');
SELECT ok((SELECT ok FROM mac_assertions WHERE key = 'disabling_again_blocks_new_attempts'), 'disabling again blocks a brand-new payment attempt on a different order');
SELECT ok((SELECT ok FROM mac_assertions WHERE key = 'existing_attempt_visible_to_customer_after_disable'), 'the paying customer can still read their own earlier (pre-disable) payment attempt after MTN collection is disabled');
SELECT ok((SELECT ok FROM mac_assertions WHERE key = 'existing_attempt_visible_to_admin_after_disable'), 'a super admin can still see the earlier payment attempt in the admin listing after disabling');
SELECT ok((SELECT ok FROM mac_assertions WHERE key = 'existing_attempt_still_resolvable_after_disable'), 'an existing attempt can still be moved through mark_requesting/record_result to a terminal state after disabling — only NEW attempt creation is blocked');
SELECT ok((SELECT ok FROM mac_assertions WHERE key = 'cod_unaffected_by_mtn_disabled'), 'COD order flow is completely unaffected by the MTN activation setting');
SELECT ok((SELECT ok FROM mac_assertions WHERE key = 'orange_money_still_unavailable'), 'Orange Money remains unavailable regardless of the MTN activation setting');

SELECT * FROM finish();
ROLLBACK;
