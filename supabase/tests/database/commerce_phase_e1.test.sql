-- Coverage for DeliveryOS Commerce Phase E1 — Finance, Ledger & Settlement
-- Foundation (20260309200000_commerce_phase_e1_finance_ledger.sql).
--
-- Proves the full COD accounting lifecycle end-to-end (vendor gross/
-- commission/net, carrier gross/commission/net, platform revenue, all
-- balanced), that fee rules are read from Super-Admin configuration (not
-- hardcoded) and frozen per event (a later rule change never rewrites
-- history), zero-commission behavior, manual single- and multi-order
-- settlement, vendor/carrier/customer isolation, Super Admin visibility,
-- that no client role can mutate a ledger entry or self-settle, that
-- duplicate financial posting and duplicate settlement are both
-- idempotent/prevented, the reversal primitive, that neither internal
-- posting RPC is directly callable by a client role, that a vendor cannot
-- drive any stage of a settlement's lifecycle (not just creation), and
-- that a failed or reversed settlement genuinely releases its payable
-- entries for re-claiming by a new settlement (not just a status flip)
-- without ever mutating the underlying ledger entries or destroying prior
-- settlement history.

BEGIN;
SELECT plan(20);

SELECT has_table('public'::name, 'commerce_financial_events'::name);
SELECT has_table('public'::name, 'commerce_ledger_entries'::name);
SELECT has_table('public'::name, 'commerce_settlements'::name);
SELECT has_table('public'::name, 'commerce_settlement_items'::name);
SELECT has_function('public'::name, 'recognize_commerce_order_financials'::name);
SELECT has_function('public'::name, 'reverse_commerce_order_financials'::name);
SELECT has_function('public'::name, 'admin_create_commerce_settlement'::name);

CREATE OR REPLACE FUNCTION pg_temp.make_customer(p_label TEXT)
RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
  v_user UUID := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, phone, email, encrypted_password, phone_confirmed_at, aud, role)
  VALUES (
    v_user, '+23177' || lpad((floor(random() * 999999))::text, 6, '0'),
    'commerce-e1-' || substr(v_user::text, 1, 8) || '@test.local',
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

-- Runs one COD order all the way from checkout to delivered/collected,
-- using whichever carrier company is passed in (already marketplace-
-- configured by the caller). Returns the final commerce_orders row.
CREATE OR REPLACE FUNCTION pg_temp.run_cod_order_to_collected(
  p_customer_id UUID, p_vendor_id UUID, p_vendor_owner_id UUID,
  p_product_id UUID, p_carrier_id UUID, p_carrier_owner_id UUID
)
RETURNS public.commerce_orders LANGUAGE plpgsql AS $$
DECLARE
  v_cart UUID;
  v_order public.commerce_orders;
  v_offer_id UUID;
  v_rider UUID;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_customer_id::text, true);
  v_cart := (public.get_or_create_cart(p_vendor_id)).id;
  PERFORM public.add_cart_item(v_cart, p_product_id, 1, '[]'::JSONB);
  v_order := public.submit_commerce_order(v_cart, 'E1 Customer', 'Test address', 'Test area', NULL, NULL, NULL, 'cod');
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

  INSERT INTO public.riders (company_id, rider_code, full_name, phone, status)
  VALUES (p_carrier_id, 'E1-' || substr(gen_random_uuid()::text, 1, 8), 'E1 Rider', '+231881' || lpad((floor(random()*999999))::text,6,'0'), 'available')
  RETURNING id INTO v_rider;

  PERFORM set_config('request.jwt.claim.sub', p_carrier_owner_id::text, true);
  PERFORM public.assign_delivery_rider(v_order.delivery_id, v_rider);
  PERFORM public.transition_delivery_status(v_order.delivery_id, 'accepted', NULL);
  PERFORM public.transition_delivery_status(v_order.delivery_id, 'picked_up', NULL);
  PERFORM public.transition_delivery_status(v_order.delivery_id, 'in_transit', NULL);
  PERFORM public.transition_delivery_status(v_order.delivery_id, 'delivered', NULL);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT * INTO v_order FROM public.commerce_orders WHERE id = v_order.id;
  RETURN v_order;
END;
$$;

DO $$
DECLARE
  v_admin UUID;
  v_vendor_a UUID; v_vendor_a_owner UUID;
  v_vendor_b UUID; v_vendor_b_owner UUID;
  v_carrier_a UUID; v_carrier_a_owner UUID;
  v_carrier_b UUID; v_carrier_b_owner UUID;
  v_customer1 UUID;
  v_customer2 UUID;
  v_product_a UUID;
  v_product_b UUID;
  v_result RECORD;
  v_order_a public.commerce_orders;
  v_order_a2 public.commerce_orders;
  v_order_b1 public.commerce_orders;
  v_order_b2 public.commerce_orders;
  v_event_a public.commerce_financial_events;
  v_entries_sum RECORD;
  v_forbidden BOOLEAN;
  v_row_count INT;
  v_vendor_b_fee_rule UUID;
  v_settlement public.commerce_settlements;
  v_snapshot_before JSONB;
  v_snapshot_after JSONB;
  v_finance JSONB;
  v_overview JSONB;
BEGIN
  v_admin := pg_temp.make_customer('E1 Admin');
  UPDATE public.profiles SET is_super_admin = true WHERE id = v_admin;

  SELECT company_id, owner_id INTO v_vendor_a, v_vendor_a_owner FROM pg_temp.make_company('E1 Vendor A', 'merchant');
  SELECT company_id, owner_id INTO v_vendor_b, v_vendor_b_owner FROM pg_temp.make_company('E1 Vendor B', 'merchant');
  SELECT company_id, owner_id INTO v_carrier_a, v_carrier_a_owner FROM pg_temp.make_company('E1 Carrier A', 'logistics_provider');
  SELECT company_id, owner_id INTO v_carrier_b, v_carrier_b_owner FROM pg_temp.make_company('E1 Carrier B', 'logistics_provider');
  v_customer1 := pg_temp.make_customer('E1 Customer One');
  v_customer2 := pg_temp.make_customer('E1 Customer Two');

  UPDATE public.companies SET address = '1 Test Street, Monrovia' WHERE id IN (v_vendor_a, v_vendor_b);
  UPDATE public.company_subscriptions SET plan_id = (SELECT id FROM public.subscriptions WHERE slug = 'business')
  WHERE company_id IN (v_carrier_a, v_carrier_b);

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM public.admin_set_vendor_state(v_vendor_a, 'active', NULL);
  PERFORM public.admin_set_vendor_state(v_vendor_b, 'active', NULL);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
  PERFORM public.upsert_store_profile(jsonb_build_object('company_id', v_vendor_a, 'slug', 'e1-vendor-a', 'display_name', 'E1 Vendor A', 'allow_cash_on_delivery', true));
  v_result := public.upsert_product(jsonb_build_object('company_id', v_vendor_a, 'name', 'E1 Product A', 'price_lrd_cents', 20000, 'status', 'active'));
  v_product_a := (v_result).id;
  PERFORM set_config('request.jwt.claim.sub', '', true);

  PERFORM set_config('request.jwt.claim.sub', v_vendor_b_owner::text, true);
  PERFORM public.upsert_store_profile(jsonb_build_object('company_id', v_vendor_b, 'slug', 'e1-vendor-b', 'display_name', 'E1 Vendor B', 'allow_cash_on_delivery', true));
  v_result := public.upsert_product(jsonb_build_object('company_id', v_vendor_b, 'name', 'E1 Product B', 'price_lrd_cents', 10000, 'status', 'active'));
  v_product_b := (v_result).id;
  PERFORM set_config('request.jwt.claim.sub', '', true);

  -- Vendor A uses the platform's zero_commission default. Vendor B gets an
  -- explicit, Super-Admin-configured 5% (500 bps) rule — proving fee rules
  -- are read from real configuration, independently per vendor, never
  -- hardcoded.
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  v_result := public.admin_upsert_commerce_fee_rule(jsonb_build_object(
    'name', 'E1 Vendor B 5%', 'fee_model', 'percentage', 'percentage_bps', 500,
    'is_active', true, 'applies_to_vendor_company_id', v_vendor_b
  ));
  v_vendor_b_fee_rule := (v_result).id;
  PERFORM set_config('request.jwt.claim.sub', '', true);

  PERFORM set_config('request.jwt.claim.sub', v_carrier_a_owner::text, true);
  PERFORM public.upsert_provider_marketplace_profile(jsonb_build_object(
    'company_id', v_carrier_a, 'marketplace_enabled', true, 'accepting_jobs', true, 'minimum_delivery_fee_lrd_cents', 2000
  ));
  PERFORM set_config('request.jwt.claim.sub', '', true);

  PERFORM set_config('request.jwt.claim.sub', v_carrier_b_owner::text, true);
  PERFORM public.upsert_provider_marketplace_profile(jsonb_build_object(
    'company_id', v_carrier_b, 'marketplace_enabled', true, 'accepting_jobs', true, 'minimum_delivery_fee_lrd_cents', 1500
  ));
  PERFORM set_config('request.jwt.claim.sub', '', true);

  CREATE TEMP TABLE e1_assertions (key TEXT PRIMARY KEY, ok BOOLEAN);

  -- =========================================================================
  -- 1) Zero-fee carrier hardening: a carrier who never explicitly
  --    configured marketplace pricing is excluded from Commerce offers
  --    even though minimum_delivery_fee_lrd_cents defaults to 0.
  -- =========================================================================
  DECLARE
    v_unconfigured_carrier UUID; v_unconfigured_owner UUID;
    v_probe_order public.commerce_orders;
    v_probe_cart UUID;
    v_offer_count INT;
  BEGIN
    SELECT company_id, owner_id INTO v_unconfigured_carrier, v_unconfigured_owner FROM pg_temp.make_company('E1 Unconfigured Carrier', 'logistics_provider');
    UPDATE public.company_subscriptions SET plan_id = (SELECT id FROM public.subscriptions WHERE slug = 'business') WHERE company_id = v_unconfigured_carrier;
    -- create_company_with_owner already auto-creates the provider_marketplace_profiles
    -- row (marketplace_enabled=false) — never touched via upsert, so
    -- delivery_pricing_configured_at stays NULL. Enable marketplace_enabled
    -- directly at the table level to isolate this test from the "never
    -- configured" gate itself (proving the gate, not marketplace_enabled).
    UPDATE public.provider_marketplace_profiles SET marketplace_enabled = true, accepting_jobs = true WHERE company_id = v_unconfigured_carrier;
    IF EXISTS (SELECT 1 FROM public.provider_marketplace_profiles WHERE company_id = v_unconfigured_carrier AND delivery_pricing_configured_at IS NOT NULL) THEN
      RAISE EXCEPTION 'test setup invalid — carrier should not be pricing-configured yet';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
    v_probe_cart := (public.get_or_create_cart(v_vendor_a)).id;
    PERFORM public.add_cart_item(v_probe_cart, v_product_a, 1, '[]'::JSONB);
    v_probe_order := public.submit_commerce_order(v_probe_cart, 'E1 Probe Customer', 'Probe address', 'Probe area', NULL, NULL, NULL, 'cod');
    PERFORM set_config('request.jwt.claim.sub', '', true);

    PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
    PERFORM public.vendor_accept_commerce_order(v_probe_order.id);
    PERFORM public.vendor_mark_order_preparing(v_probe_order.id);
    v_probe_order := public.vendor_mark_order_ready(v_probe_order.id);
    PERFORM public.request_commerce_order_delivery(v_probe_order.id);
    PERFORM set_config('request.jwt.claim.sub', '', true);

    SELECT COUNT(*) INTO v_offer_count FROM public.delivery_offers
    WHERE delivery_request_id = (SELECT delivery_request_id FROM public.commerce_orders WHERE id = v_probe_order.id)
      AND provider_company_id = v_unconfigured_carrier;
    IF v_offer_count <> 0 THEN
      RAISE EXCEPTION 'expected an unconfigured carrier to receive 0 Commerce offers, got %', v_offer_count;
    END IF;
  END;

  INSERT INTO e1_assertions VALUES ('zero_fee_carrier_hardening', true);

  -- =========================================================================
  -- 2) Full COD lifecycle for Vendor A (zero commission) + Carrier A —
  --    vendor gross/net, carrier gross/commission/net, platform revenue,
  --    all balanced.
  -- =========================================================================
  v_order_a := pg_temp.run_cod_order_to_collected(v_customer1, v_vendor_a, v_vendor_a_owner, v_product_a, v_carrier_a, v_carrier_a_owner);

  IF v_order_a.payment_status <> 'paid' OR v_order_a.fulfillment_status <> 'completed' THEN
    RAISE EXCEPTION 'expected order to reach paid/completed, got % / %', v_order_a.payment_status, v_order_a.fulfillment_status;
  END IF;

  SELECT * INTO v_event_a FROM public.commerce_financial_events
  WHERE commerce_order_id = v_order_a.id AND event_type = 'cod_collected';
  IF v_event_a.id IS NULL THEN RAISE EXCEPTION 'expected a cod_collected financial event'; END IF;
  IF v_event_a.idempotency_key <> ('cod_collected:' || v_order_a.id::TEXT) THEN
    RAISE EXCEPTION 'unexpected idempotency key %', v_event_a.idempotency_key;
  END IF;

  -- Vendor A: zero commission -> vendor keeps 100% of subtotal (20000).
  IF (v_event_a.snapshot ->> 'vendor_gross_lrd_cents')::INT <> 20000
     OR (v_event_a.snapshot ->> 'vendor_platform_fee_lrd_cents')::INT <> 0
     OR (v_event_a.snapshot ->> 'vendor_net_lrd_cents')::INT <> 20000 THEN
    RAISE EXCEPTION 'expected zero-commission vendor split 20000/0/20000, got %', v_event_a.snapshot;
  END IF;

  -- Carrier A: gross 2000, 10% platform default marketplace fee -> fee 200, net 1800.
  IF (v_event_a.snapshot ->> 'carrier_gross_lrd_cents')::INT <> 2000
     OR (v_event_a.snapshot ->> 'carrier_platform_fee_lrd_cents')::INT <> 200
     OR (v_event_a.snapshot ->> 'carrier_net_lrd_cents')::INT <> 1800 THEN
    RAISE EXCEPTION 'expected carrier split 2000/200/1800 (10%% marketplace default), got %', v_event_a.snapshot;
  END IF;

  SELECT
    COALESCE(SUM(amount_lrd_cents) FILTER (WHERE account_type = 'cod_clearing'), 0) AS clearing,
    COALESCE(SUM(amount_lrd_cents) FILTER (WHERE account_type = 'vendor_payable'), 0) AS vendor_payable,
    COALESCE(SUM(amount_lrd_cents) FILTER (WHERE account_type = 'carrier_payable'), 0) AS carrier_payable,
    COALESCE(SUM(amount_lrd_cents) FILTER (WHERE account_type = 'platform_revenue'), 0) AS platform_revenue,
    COALESCE(SUM(amount_lrd_cents) FILTER (WHERE direction = 'debit'), 0) AS debits,
    COALESCE(SUM(amount_lrd_cents) FILTER (WHERE direction = 'credit'), 0) AS credits
  INTO v_entries_sum
  FROM public.commerce_ledger_entries WHERE financial_event_id = v_event_a.id;

  -- COD collected = order subtotal + accepted delivery fee, exactly.
  IF v_entries_sum.clearing <> 22000 THEN
    RAISE EXCEPTION 'expected cod_clearing = subtotal(20000) + delivery fee(2000) = 22000, got %', v_entries_sum.clearing;
  END IF;
  IF v_entries_sum.vendor_payable <> 20000 OR v_entries_sum.carrier_payable <> 1800 OR v_entries_sum.platform_revenue <> 200 THEN
    RAISE EXCEPTION 'expected vendor_payable=20000 carrier_payable=1800 platform_revenue=200, got %', v_entries_sum;
  END IF;
  IF v_entries_sum.debits <> v_entries_sum.credits THEN
    RAISE EXCEPTION 'ledger event is unbalanced: debits=% credits=%', v_entries_sum.debits, v_entries_sum.credits;
  END IF;

  INSERT INTO e1_assertions VALUES ('cod_lifecycle_zero_commission_balanced', true);

  -- =========================================================================
  -- 3) Duplicate financial posting is idempotent.
  -- =========================================================================
  DECLARE v_repost JSONB; v_entry_count_before INT; v_entry_count_after INT;
  BEGIN
    SELECT COUNT(*) INTO v_entry_count_before FROM public.commerce_ledger_entries WHERE financial_event_id = v_event_a.id;
    v_repost := public.recognize_commerce_order_financials(v_order_a.id);
    SELECT COUNT(*) INTO v_entry_count_after FROM public.commerce_ledger_entries WHERE financial_event_id = v_event_a.id;
    IF (v_repost ->> 'already_recognized')::BOOLEAN IS NOT TRUE THEN
      RAISE EXCEPTION 'expected a repeat recognition call to report already_recognized=true';
    END IF;
    IF v_entry_count_before <> v_entry_count_after THEN
      RAISE EXCEPTION 'expected no new ledger entries from a duplicate recognition call';
    END IF;
    IF (SELECT COUNT(*) FROM public.commerce_financial_events WHERE commerce_order_id = v_order_a.id AND event_type = 'cod_collected') <> 1 THEN
      RAISE EXCEPTION 'expected exactly one cod_collected event for this order';
    END IF;
  END;

  INSERT INTO e1_assertions VALUES ('duplicate_financial_posting_idempotent', true);

  -- =========================================================================
  -- 4) Fee rule change does not rewrite historical order economics; a
  --    NEW order under the new rule uses the new rate.
  -- =========================================================================
  v_snapshot_before := v_event_a.snapshot;

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM public.admin_upsert_commerce_fee_rule(jsonb_build_object(
    'id', (SELECT id FROM public.commerce_fee_rules WHERE is_platform_default = true),
    'fee_model', 'percentage', 'percentage_bps', 2000
  ));
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT snapshot INTO v_snapshot_after FROM public.commerce_financial_events WHERE id = v_event_a.id;
  IF v_snapshot_after IS DISTINCT FROM v_snapshot_before THEN
    RAISE EXCEPTION 'expected historical financial event snapshot to remain frozen after a fee rule change';
  END IF;

  -- A fresh order for Vendor A now recognizes under the NEW 20% default.
  PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
  v_result := public.upsert_product(jsonb_build_object('company_id', v_vendor_a, 'name', 'E1 Product A2', 'price_lrd_cents', 10000, 'status', 'active'));
  PERFORM set_config('request.jwt.claim.sub', '', true);
  DECLARE v_product_a2 UUID := (v_result).id; v_event_a2 public.commerce_financial_events;
  BEGIN
    v_order_a2 := pg_temp.run_cod_order_to_collected(v_customer1, v_vendor_a, v_vendor_a_owner, v_product_a2, v_carrier_a, v_carrier_a_owner);
    SELECT * INTO v_event_a2 FROM public.commerce_financial_events WHERE commerce_order_id = v_order_a2.id AND event_type = 'cod_collected';
    IF (v_event_a2.snapshot ->> 'vendor_platform_fee_lrd_cents')::INT <> 2000 THEN
      RAISE EXCEPTION 'expected the new order to recognize under the new 20%% rate (fee=2000), got %', v_event_a2.snapshot ->> 'vendor_platform_fee_lrd_cents';
    END IF;
  END;

  INSERT INTO e1_assertions VALUES ('fee_rule_change_freezes_history_new_orders_use_new_rate', true);

  -- =========================================================================
  -- 5) Vendor B: independently-configured 5% rule, confirming per-vendor
  --    fee rules are genuinely read from Super Admin configuration.
  -- =========================================================================
  v_order_b1 := pg_temp.run_cod_order_to_collected(v_customer2, v_vendor_b, v_vendor_b_owner, v_product_b, v_carrier_b, v_carrier_b_owner);
  DECLARE v_event_b1 public.commerce_financial_events;
  BEGIN
    SELECT * INTO v_event_b1 FROM public.commerce_financial_events WHERE commerce_order_id = v_order_b1.id AND event_type = 'cod_collected';
    -- subtotal 10000 * 5% = 500 fee, 9500 net.
    IF (v_event_b1.snapshot ->> 'vendor_platform_fee_lrd_cents')::INT <> 500
       OR (v_event_b1.snapshot ->> 'vendor_net_lrd_cents')::INT <> 9500 THEN
      RAISE EXCEPTION 'expected Vendor B 5%% split (fee=500, net=9500), got %', v_event_b1.snapshot;
    END IF;
  END;

  -- A second order for Vendor B, for the multi-order settlement test below.
  PERFORM set_config('request.jwt.claim.sub', v_vendor_b_owner::text, true);
  v_result := public.upsert_product(jsonb_build_object('company_id', v_vendor_b, 'name', 'E1 Product B2', 'price_lrd_cents', 8000, 'status', 'active'));
  PERFORM set_config('request.jwt.claim.sub', '', true);
  DECLARE v_product_b2 UUID := (v_result).id;
  BEGIN
    v_order_b2 := pg_temp.run_cod_order_to_collected(v_customer2, v_vendor_b, v_vendor_b_owner, v_product_b2, v_carrier_b, v_carrier_b_owner);
  END;

  INSERT INTO e1_assertions VALUES ('vendor_specific_fee_rule_applied', true);

  -- =========================================================================
  -- 6) Vendor / carrier / customer isolation + Super Admin visibility.
  -- =========================================================================
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_vendor_b_owner::text, true);
    PERFORM public.get_vendor_commerce_finance(v_vendor_a);
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN RAISE EXCEPTION 'expected Vendor B to be forbidden from reading Vendor A''s finance'; END IF;

  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_carrier_b_owner::text, true);
    PERFORM public.get_carrier_commerce_finance(v_carrier_a);
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN RAISE EXCEPTION 'expected Carrier B to be forbidden from reading Carrier A''s finance'; END IF;

  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_customer1::text, true);
    PERFORM public.get_vendor_commerce_finance(v_vendor_a);
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN RAISE EXCEPTION 'expected a customer to be forbidden from reading vendor finance'; END IF;

  PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
  v_finance := public.get_vendor_commerce_finance(v_vendor_a);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF (v_finance ->> 'net_earnings_lrd_cents')::INT <= 0 THEN
    RAISE EXCEPTION 'expected Vendor A to see their own real positive net earnings, got %', v_finance ->> 'net_earnings_lrd_cents';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  v_overview := public.get_admin_commerce_finance_overview(NULL, NULL, NULL, NULL);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF (v_overview ->> 'commerce_gmv_lrd_cents')::INT <= 0 OR (v_overview ->> 'platform_revenue_lrd_cents')::INT <= 0 THEN
    RAISE EXCEPTION 'expected Super Admin overview to show real positive platform-wide figures, got %', v_overview;
  END IF;

  INSERT INTO e1_assertions VALUES ('isolation_and_admin_visibility', true);

  -- =========================================================================
  -- 7) No client role can mutate a ledger entry directly.
  -- =========================================================================
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
    UPDATE public.commerce_ledger_entries SET amount_lrd_cents = 1 WHERE financial_event_id = v_event_a.id;
    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    v_row_count := 0;
  END;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF v_row_count <> 0 THEN
    RAISE EXCEPTION 'expected a raw UPDATE of commerce_ledger_entries to affect 0 rows under RLS';
  END IF;

  v_forbidden := false;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
    INSERT INTO public.commerce_ledger_entries (financial_event_id, account_type, direction, company_id, amount_lrd_cents)
    VALUES (v_event_a.id, 'vendor_payable', 'credit', v_vendor_a, 999999);
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    v_forbidden := true;
  END;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected a raw INSERT into commerce_ledger_entries by a tenant to be rejected';
  END IF;

  INSERT INTO e1_assertions VALUES ('client_cannot_mutate_ledger', true);

  -- =========================================================================
  -- 8) Client cannot self-settle (neither create a settlement nor mark
  --    one completed).
  -- =========================================================================
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
    PERFORM public.admin_create_commerce_settlement('vendor', v_vendor_a, NULL);
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%forbidden%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN RAISE EXCEPTION 'expected a vendor to be forbidden from creating their own settlement'; END IF;

  INSERT INTO e1_assertions VALUES ('client_cannot_self_settle', true);

  -- =========================================================================
  -- 9) Manual single-order settlement (Vendor A) and multi-order
  --    settlement (Vendor B, both orders in one settlement); duplicate
  --    settlement is prevented once all payables are claimed; concurrent-
  --    safety mechanism (FOR UPDATE SKIP LOCKED excludes already-claimed
  --    entries from a second settlement attempt).
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  v_settlement := public.admin_create_commerce_settlement('vendor', v_vendor_a, 'E1 test settlement');
  PERFORM set_config('request.jwt.claim.sub', '', true);

  IF v_settlement.total_amount_lrd_cents <> 20000 + 8000 THEN
    -- Vendor A had 2 recognized orders (v_order_a: net 20000, v_order_a2: net 8000 after 20% -> 8000 gross 10000, fee 2000, net 8000)
    RAISE EXCEPTION 'expected settlement to batch all unsettled Vendor A payables (20000+8000=28000), got %', v_settlement.total_amount_lrd_cents;
  END IF;
  IF (SELECT COUNT(*) FROM public.commerce_settlement_items WHERE settlement_id = v_settlement.id) <> 2 THEN
    RAISE EXCEPTION 'expected the settlement to contain 2 line items';
  END IF;

  -- Duplicate settlement attempt: nothing left unclaimed for Vendor A.
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    PERFORM public.admin_create_commerce_settlement('vendor', v_vendor_a, NULL);
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%no_unsettled_payables%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN RAISE EXCEPTION 'expected a duplicate settlement attempt to find no unsettled payables'; END IF;

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM public.admin_mark_commerce_settlement_completed(v_settlement.id);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  IF (SELECT status FROM public.commerce_settlements WHERE id = v_settlement.id) <> 'settled' THEN
    RAISE EXCEPTION 'expected settlement to be marked settled';
  END IF;

  -- Multi-order settlement for Vendor B (2 orders' payables batched).
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  v_settlement := public.admin_create_commerce_settlement('vendor', v_vendor_b, NULL);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF v_settlement.total_amount_lrd_cents <> 9500 + (8000 - (8000 * 500 / 10000)) THEN
    RAISE EXCEPTION 'expected Vendor B multi-order settlement total, got %', v_settlement.total_amount_lrd_cents;
  END IF;
  IF (SELECT COUNT(*) FROM public.commerce_settlement_items WHERE settlement_id = v_settlement.id) <> 2 THEN
    RAISE EXCEPTION 'expected the Vendor B settlement to batch both orders'' payables into one settlement';
  END IF;

  INSERT INTO e1_assertions VALUES ('settlement_single_and_multi_order_and_duplicate_prevented', true);

  -- =========================================================================
  -- 10) Neither internal posting RPC is directly callable by a client
  --     role — both are internal-only (REVOKE ALL FROM PUBLIC, no GRANT to
  --     authenticated), reachable only from within another SECURITY
  --     DEFINER function.
  -- =========================================================================
  v_forbidden := false;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
    PERFORM public.recognize_commerce_order_financials(v_order_a.id);
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    v_forbidden := true;
  END;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected a client role to be forbidden from calling recognize_commerce_order_financials directly';
  END IF;

  v_forbidden := false;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.sub', v_vendor_a_owner::text, true);
    PERFORM public.reverse_commerce_order_financials(v_order_a.id, 'client attempt');
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    v_forbidden := true;
  END;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected a client role to be forbidden from calling reverse_commerce_order_financials directly';
  END IF;

  INSERT INTO e1_assertions VALUES ('client_cannot_call_internal_posting_rpcs', true);

  -- =========================================================================
  -- 11) A vendor cannot advance, complete, fail, or reverse a settlement —
  --     even one for their own company (create-settlement forbidden-ness
  --     is already covered in section 8; this covers every other stage).
  --     Uses Vendor B's still-pending multi-order settlement from section 9.
  -- =========================================================================
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_vendor_b_owner::text, true);
    PERFORM public.admin_mark_commerce_settlement_processing(v_settlement.id);
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%forbidden%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN RAISE EXCEPTION 'expected a vendor to be forbidden from marking their own settlement processing'; END IF;

  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_vendor_b_owner::text, true);
    PERFORM public.admin_record_commerce_settlement_reference(v_settlement.id, 'fake-ref', NULL);
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%forbidden%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN RAISE EXCEPTION 'expected a vendor to be forbidden from recording a reference on their own settlement'; END IF;

  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_vendor_b_owner::text, true);
    PERFORM public.admin_mark_commerce_settlement_completed(v_settlement.id);
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%forbidden%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN RAISE EXCEPTION 'expected a vendor to be forbidden from marking their own settlement completed'; END IF;

  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_vendor_b_owner::text, true);
    PERFORM public.admin_mark_commerce_settlement_failed(v_settlement.id, 'vendor attempt');
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%forbidden%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN RAISE EXCEPTION 'expected a vendor to be forbidden from failing their own settlement'; END IF;

  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_vendor_b_owner::text, true);
    PERFORM public.admin_reverse_commerce_settlement(v_settlement.id, 'vendor attempt');
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%forbidden%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN RAISE EXCEPTION 'expected a vendor to be forbidden from reversing their own settlement'; END IF;

  IF (SELECT status FROM public.commerce_settlements WHERE id = v_settlement.id) <> 'pending' THEN
    RAISE EXCEPTION 'expected settlement to remain pending after forbidden vendor mutation attempts';
  END IF;

  INSERT INTO e1_assertions VALUES ('vendor_cannot_mutate_settlement_lifecycle', true);

  -- =========================================================================
  -- 12) A failed settlement releases its payable entries exactly once, and
  --     a settled-then-reversed settlement's freed entries can genuinely
  --     be re-claimed by a brand-new settlement (this previously raised a
  --     unique_violation on commerce_settlement_items before its
  --     uniqueness was scoped per-settlement instead of globally). Also
  --     proves neither failure nor reversal ever mutates the underlying
  --     ledger entries or destroys the superseded settlement's item
  --     history.
  -- =========================================================================
  DECLARE
    v_entry_ids UUID[];
    v_entry_amounts INT[];
    v_settlement_2 public.commerce_settlements;
    v_settlement_3 public.commerce_settlements;
    v_items_total_for_entries INT;
  BEGIN
    SELECT array_agg(id ORDER BY id), array_agg(amount_lrd_cents ORDER BY id)
    INTO v_entry_ids, v_entry_amounts
    FROM public.commerce_ledger_entries WHERE settlement_id = v_settlement.id;
    IF array_length(v_entry_ids, 1) <> 2 THEN
      RAISE EXCEPTION 'expected 2 claimed entries going into the fail/resettle test, got %', array_length(v_entry_ids, 1);
    END IF;

    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    v_settlement := public.admin_mark_commerce_settlement_failed(v_settlement.id, 'e1 test failure');
    PERFORM set_config('request.jwt.claim.sub', '', true);

    IF v_settlement.status <> 'failed' OR v_settlement.failed_at IS NULL OR v_settlement.failed_by <> v_admin THEN
      RAISE EXCEPTION 'expected settlement to be marked failed with failed_at/failed_by set, got status=% failed_at=% failed_by=%',
        v_settlement.status, v_settlement.failed_at, v_settlement.failed_by;
    END IF;

    IF (SELECT COUNT(*) FROM public.commerce_ledger_entries WHERE id = ANY(v_entry_ids) AND settlement_id IS NOT NULL) <> 0 THEN
      RAISE EXCEPTION 'expected both entries to be freed (settlement_id NULL) after the settlement failed';
    END IF;

    IF (SELECT COUNT(*) FROM public.commerce_settlement_items WHERE settlement_id = v_settlement.id) <> 2 THEN
      RAISE EXCEPTION 'expected the failed settlement to keep its 2 historical settlement_items rows';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    v_settlement_2 := public.admin_create_commerce_settlement('vendor', v_vendor_b, 'e1 resettle after failure');
    PERFORM set_config('request.jwt.claim.sub', '', true);

    IF v_settlement_2.total_amount_lrd_cents <> 17100 THEN
      RAISE EXCEPTION 'expected the resettlement to reclaim the same 17100 total, got %', v_settlement_2.total_amount_lrd_cents;
    END IF;
    IF (SELECT COUNT(*) FROM public.commerce_ledger_entries WHERE id = ANY(v_entry_ids) AND settlement_id = v_settlement_2.id) <> 2 THEN
      RAISE EXCEPTION 'expected both originally-claimed entries to be re-claimed by the new settlement';
    END IF;

    SELECT COUNT(*) INTO v_items_total_for_entries
    FROM public.commerce_settlement_items WHERE ledger_entry_id = ANY(v_entry_ids);
    IF v_items_total_for_entries <> 4 THEN
      RAISE EXCEPTION 'expected 4 total settlement_items rows (2 historical from the failed attempt + 2 from the new one), got %', v_items_total_for_entries;
    END IF;

    IF (
      SELECT array_agg(amount_lrd_cents ORDER BY id) FROM public.commerce_ledger_entries WHERE id = ANY(v_entry_ids)
    ) <> v_entry_amounts THEN
      RAISE EXCEPTION 'expected ledger entry amounts to be unchanged across the fail/resettle cycle';
    END IF;

    -- Settle and reverse the NEW settlement, proving the reclaim path
    -- works after a REVERSAL too, not just a failure.
    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    v_settlement_2 := public.admin_mark_commerce_settlement_completed(v_settlement_2.id);
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF v_settlement_2.status <> 'settled' OR v_settlement_2.settled_at IS NULL THEN
      RAISE EXCEPTION 'expected the resettlement to be marked settled';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    v_settlement_2 := public.admin_reverse_commerce_settlement(v_settlement_2.id, 'e1 test reversal of settled settlement');
    PERFORM set_config('request.jwt.claim.sub', '', true);

    IF v_settlement_2.status <> 'reversed' OR v_settlement_2.reversed_at IS NULL OR v_settlement_2.reversed_by <> v_admin THEN
      RAISE EXCEPTION 'expected the settlement to be reversed with reversed_at/reversed_by set, got status=% reversed_at=% reversed_by=%',
        v_settlement_2.status, v_settlement_2.reversed_at, v_settlement_2.reversed_by;
    END IF;
    IF (SELECT COUNT(*) FROM public.commerce_ledger_entries WHERE id = ANY(v_entry_ids) AND settlement_id IS NOT NULL) <> 0 THEN
      RAISE EXCEPTION 'expected both entries to be freed again after the settled settlement was reversed';
    END IF;
    IF (SELECT COUNT(*) FROM public.commerce_settlement_items WHERE settlement_id = v_settlement_2.id) <> 2 THEN
      RAISE EXCEPTION 'expected the reversed settlement to keep its 2 historical settlement_items rows';
    END IF;

    -- A THIRD settlement must be able to re-claim these entries yet again.
    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    v_settlement_3 := public.admin_create_commerce_settlement('vendor', v_vendor_b, 'e1 resettle after reversal');
    PERFORM set_config('request.jwt.claim.sub', '', true);

    IF v_settlement_3.total_amount_lrd_cents <> 17100 THEN
      RAISE EXCEPTION 'expected the post-reversal resettlement to reclaim the same 17100 total, got %', v_settlement_3.total_amount_lrd_cents;
    END IF;

    -- An unrelated already-settled settlement (Vendor A, section 9) must
    -- be completely unaffected by any of the above.
    IF (SELECT status FROM public.commerce_settlements WHERE payee_type = 'vendor' AND payee_company_id = v_vendor_a AND total_amount_lrd_cents = 28000) <> 'settled' THEN
      RAISE EXCEPTION 'expected Vendor A''s unrelated settled settlement to remain settled and unaffected';
    END IF;
  END;

  INSERT INTO e1_assertions VALUES ('failed_and_reversed_settlements_release_entries_for_resettlement', true);

  -- =========================================================================
  -- 13) Reversal primitive: balanced, net-zero, idempotent.
  -- =========================================================================
  DECLARE
    v_reversal JSONB;
    v_reversal_event_id UUID;
    v_net_after_reversal RECORD;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    v_reversal := public.reverse_commerce_order_financials(v_order_a2.id, 'e1 test reversal');
    PERFORM set_config('request.jwt.claim.sub', '', true);

    IF (v_reversal ->> 'already_reversed')::BOOLEAN IS TRUE THEN
      RAISE EXCEPTION 'expected the first reversal call to actually reverse';
    END IF;
    v_reversal_event_id := (v_reversal ->> 'event_id')::UUID;

    SELECT
      COALESCE(SUM(amount_lrd_cents) FILTER (WHERE direction = 'debit'), 0) AS debits,
      COALESCE(SUM(amount_lrd_cents) FILTER (WHERE direction = 'credit'), 0) AS credits
    INTO v_net_after_reversal
    FROM public.commerce_ledger_entries WHERE financial_event_id = v_reversal_event_id;

    IF v_net_after_reversal.debits <> v_net_after_reversal.credits THEN
      RAISE EXCEPTION 'expected the reversal event itself to be balanced';
    END IF;

    -- Net effect across the original + reversal for vendor_payable is zero.
    IF (
      SELECT COALESCE(SUM(CASE WHEN direction = 'credit' THEN amount_lrd_cents ELSE -amount_lrd_cents END), 0)
      FROM public.commerce_ledger_entries le
      JOIN public.commerce_financial_events e ON e.id = le.financial_event_id
      WHERE e.commerce_order_id = v_order_a2.id AND le.account_type = 'vendor_payable'
    ) <> 0 THEN
      RAISE EXCEPTION 'expected net vendor_payable effect for the reversed order to be zero';
    END IF;

    -- Idempotent: reversing again is a safe no-op.
    v_reversal := public.reverse_commerce_order_financials(v_order_a2.id, 'e1 test reversal again');
    IF (v_reversal ->> 'already_reversed')::BOOLEAN IS NOT TRUE THEN
      RAISE EXCEPTION 'expected a second reversal call to report already_reversed=true';
    END IF;
  END;

  INSERT INTO e1_assertions VALUES ('reversal_primitive_balanced_net_zero_idempotent', true);
END;
$$;

SELECT ok((SELECT ok FROM e1_assertions WHERE key = 'zero_fee_carrier_hardening'), 'a carrier who never explicitly configured marketplace pricing receives 0 Commerce offers, even though minimum_delivery_fee_lrd_cents defaults to 0');
SELECT ok((SELECT ok FROM e1_assertions WHERE key = 'cod_lifecycle_zero_commission_balanced'), 'a full COD order lifecycle recognizes correct vendor gross/net (zero commission), carrier gross/commission/net, and platform revenue, with the ledger event fully balanced and cod_clearing = subtotal + accepted delivery fee');
SELECT ok((SELECT ok FROM e1_assertions WHERE key = 'duplicate_financial_posting_idempotent'), 'calling recognize_commerce_order_financials twice for the same order posts no duplicate entries');
SELECT ok((SELECT ok FROM e1_assertions WHERE key = 'fee_rule_change_freezes_history_new_orders_use_new_rate'), 'changing the platform default fee rule never rewrites an already-recognized event''s frozen snapshot, while a new order recognizes under the new rate');
SELECT ok((SELECT ok FROM e1_assertions WHERE key = 'vendor_specific_fee_rule_applied'), 'a vendor-specific commerce_fee_rules override is read and applied instead of the platform default');
SELECT ok((SELECT ok FROM e1_assertions WHERE key = 'isolation_and_admin_visibility'), 'vendors/carriers/customers cannot read another company''s finance, and Super Admin sees real platform-wide figures');
SELECT ok((SELECT ok FROM e1_assertions WHERE key = 'client_cannot_mutate_ledger'), 'no tenant role can INSERT or UPDATE commerce_ledger_entries directly');
SELECT ok((SELECT ok FROM e1_assertions WHERE key = 'client_cannot_self_settle'), 'a vendor cannot create their own settlement');
SELECT ok((SELECT ok FROM e1_assertions WHERE key = 'settlement_single_and_multi_order_and_duplicate_prevented'), 'a settlement can batch multiple orders'' payables, marking completed works, and a duplicate settlement attempt finds nothing left unclaimed');
SELECT ok((SELECT ok FROM e1_assertions WHERE key = 'client_cannot_call_internal_posting_rpcs'), 'a client role cannot directly call recognize_commerce_order_financials or reverse_commerce_order_financials');
SELECT ok((SELECT ok FROM e1_assertions WHERE key = 'vendor_cannot_mutate_settlement_lifecycle'), 'a vendor cannot advance, complete, fail, or reverse a settlement, even their own');
SELECT ok((SELECT ok FROM e1_assertions WHERE key = 'failed_and_reversed_settlements_release_entries_for_resettlement'), 'a failed or reversed settlement genuinely releases its payable entries for re-claiming by a new settlement, without mutating ledger entries or losing prior settlement history');
SELECT ok((SELECT ok FROM e1_assertions WHERE key = 'reversal_primitive_balanced_net_zero_idempotent'), 'reverse_commerce_order_financials posts a balanced, net-zero offsetting event and is idempotent on a second call');

SELECT * FROM finish();
ROLLBACK;
