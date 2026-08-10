-- Coverage for provision_company_sms_allowance and its wiring into
-- ensure_initial_company_subscription / admin_set_company_subscription /
-- queue_outbound_sms / admin_add_sms_credits
-- (20260308200000_sms_allowance_provisioning.sql).
--
-- Company/Tenant Production Readiness Audit, Phase 1 item 1: companies.
-- sms_credits always defaulted to 0 and nothing ever funded it from the
-- plan's monthly_sms_allowance. This file proves the fix is idempotent,
-- plan-aware (reads the live subscriptions catalog, never a hardcoded
-- number), period-aware (a new company_subscriptions row forfeits the old
-- included balance and grants the new plan's), isolated per company,
-- preserves manual top-ups separately, and that nothing in the Auth OTP path
-- (which fires the same handle_new_user trigger as every other auth.users
-- insert) ever touches a company's SMS balance.

BEGIN;
SELECT plan(9);

SELECT has_function('public'::name, 'provision_company_sms_allowance'::name);

CREATE OR REPLACE FUNCTION pg_temp.make_company_no_subscription(p_label TEXT)
RETURNS TABLE (company_id UUID, owner_id UUID) LANGUAGE plpgsql AS $$
DECLARE
  v_owner UUID := gen_random_uuid();
  v_company UUID := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, phone, email, encrypted_password, phone_confirmed_at, aud, role)
  VALUES (
    v_owner, '+23177' || lpad((floor(random() * 999999))::text, 6, '0'),
    'sms-prov-' || substr(v_owner::text, 1, 8) || '@test.local',
    crypt('x', gen_salt('bf')), now(), 'authenticated', 'authenticated'
  );
  INSERT INTO public.profiles (id, full_name) VALUES (v_owner, p_label)
  ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name;

  -- subscription_id must reference a real plan even though this fixture has
  -- no company_subscriptions row yet; starter is a safe placeholder default.
  INSERT INTO public.companies (id, name, slug, phone, email, status, subscription_id)
  SELECT v_company, p_label, 'sms-prov-' || substr(v_company::text, 1, 8), '+231770000900', p_label || '@test.local',
    'active', s.id
  FROM public.subscriptions s WHERE s.slug = 'starter' LIMIT 1;

  INSERT INTO public.company_users (company_id, user_id, role, is_active)
  VALUES (v_company, v_owner, 'company_owner', true);

  RETURN QUERY SELECT v_company, v_owner;
END;
$$;

DO $$
DECLARE
  v_admin UUID := gen_random_uuid();
  v_c1 UUID; v_o1 UUID; -- trial provisioning + idempotent ensure_initial_company_subscription
  v_c2 UUID; v_o2 UUID; -- direct provision_company_sms_allowance double-call
  v_c3 UUID; v_o3 UUID; -- plan-change forfeits old included, grants new
  v_c4 UUID; v_o4 UUID; -- manual top-up survives a plan-change provisioning event
  v_c5 UUID; v_o5 UUID; -- consumption order: included before purchased
  v_c6 UUID; v_o6 UUID; -- per-company isolation
  v_c7 UUID; v_o7 UUID; -- isolation partner (must stay untouched by v_c6's activity)
  v_ghost_identity UUID := gen_random_uuid(); -- OTP-like auth.users insert never touches sms_credits
  v_starter_allowance INT;
  v_business_allowance INT;
  v_enterprise_allowance INT;
  v_starter_id UUID;
  v_business_id UUID;
  v_enterprise_id UUID;
  v_cs public.company_subscriptions;
  v_cs2 public.company_subscriptions;
  v_included INT;
  v_purchased INT;
  v_total INT;
  v_grant_count INT;
  v_ledger_count INT;
  v_second_call BOOLEAN;
BEGIN
  INSERT INTO auth.users (id, phone, email, encrypted_password, phone_confirmed_at, aud, role)
  VALUES (
    v_admin, '+231770000901', 'sms-prov-admin-' || substr(v_admin::text, 1, 8) || '@test.local',
    crypt('x', gen_salt('bf')), now(), 'authenticated', 'authenticated'
  );
  INSERT INTO public.profiles (id, full_name, is_super_admin) VALUES (v_admin, 'SMS Prov Admin', true)
  ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, is_super_admin = true;

  SELECT id, monthly_sms_allowance INTO v_starter_id, v_starter_allowance FROM public.subscriptions WHERE slug = 'starter';
  SELECT id, monthly_sms_allowance INTO v_business_id, v_business_allowance FROM public.subscriptions WHERE slug = 'business';
  SELECT id, monthly_sms_allowance INTO v_enterprise_id, v_enterprise_allowance FROM public.subscriptions WHERE slug = 'enterprise';

  CREATE TEMP TABLE sms_prov_assertions (key TEXT PRIMARY KEY, ok BOOLEAN);

  -- ===========================================================================
  -- 1) Trial creation grants exactly the Starter plan's CURRENT catalog
  --    allowance — never a hardcoded number.
  -- ===========================================================================
  SELECT company_id, owner_id INTO v_c1, v_o1 FROM pg_temp.make_company_no_subscription('Trial Prov Co');
  v_cs := public.ensure_initial_company_subscription(v_c1);

  SELECT sms_credits_included, sms_credits_purchased INTO v_included, v_purchased
  FROM public.companies WHERE id = v_c1;

  IF v_included <> v_starter_allowance THEN
    RAISE EXCEPTION 'expected trial to grant starter allowance %, got %', v_starter_allowance, v_included;
  END IF;
  IF v_purchased <> 0 THEN
    RAISE EXCEPTION 'expected purchased bucket untouched at 0, got %', v_purchased;
  END IF;

  SELECT COUNT(*)::INT INTO v_ledger_count
  FROM public.sms_credit_ledger
  WHERE company_id = v_c1 AND reason = 'plan_allowance_provisioned' AND bucket = 'included';
  IF v_ledger_count <> 1 THEN
    RAISE EXCEPTION 'expected exactly 1 provisioning ledger entry, got %', v_ledger_count;
  END IF;

  -- Calling ensure_initial_company_subscription again for the same company
  -- must not double-credit (it returns the existing row, no new
  -- company_subscriptions row, so provisioning is never re-invoked).
  v_cs2 := public.ensure_initial_company_subscription(v_c1);
  IF v_cs2.id <> v_cs.id THEN
    RAISE EXCEPTION 'expected the same subscription row back, got a different id';
  END IF;

  SELECT sms_credits_included INTO v_included FROM public.companies WHERE id = v_c1;
  IF v_included <> v_starter_allowance THEN
    RAISE EXCEPTION 'expected balance unchanged after re-calling ensure_initial_company_subscription, got %', v_included;
  END IF;

  INSERT INTO sms_prov_assertions VALUES ('trial_provisioning', true);

  -- ===========================================================================
  -- 2) Direct double-call of provision_company_sms_allowance for the same
  --    company_subscription_id is a guaranteed no-op.
  -- ===========================================================================
  SELECT company_id, owner_id INTO v_c2, v_o2 FROM pg_temp.make_company_no_subscription('Direct Double Call Co');
  v_cs := public.ensure_initial_company_subscription(v_c2);

  SELECT sms_credits_included INTO v_included FROM public.companies WHERE id = v_c2;
  IF v_included <> v_starter_allowance THEN
    RAISE EXCEPTION 'setup invalid: expected initial grant %, got %', v_starter_allowance, v_included;
  END IF;

  v_second_call := public.provision_company_sms_allowance(v_cs.id);
  IF v_second_call <> false THEN
    RAISE EXCEPTION 'expected a second provisioning call for the same row to return false';
  END IF;

  SELECT sms_credits_included INTO v_included FROM public.companies WHERE id = v_c2;
  IF v_included <> v_starter_allowance THEN
    RAISE EXCEPTION 'expected balance unchanged after redundant provisioning call, got %', v_included;
  END IF;

  SELECT COUNT(*)::INT INTO v_grant_count
  FROM public.sms_allowance_grants WHERE company_subscription_id = v_cs.id;
  IF v_grant_count <> 1 THEN
    RAISE EXCEPTION 'expected exactly 1 grant row, got %', v_grant_count;
  END IF;

  INSERT INTO sms_prov_assertions VALUES ('direct_double_call_idempotent', true);

  -- ===========================================================================
  -- 3) Plan change (admin_set_company_subscription): forfeits the old
  --    plan's leftover included balance (no rollover) and grants the new
  --    plan's allowance — reading Business's CURRENT catalog value, not a
  --    hardcoded number.
  -- ===========================================================================
  SELECT company_id, owner_id INTO v_c3, v_o3 FROM pg_temp.make_company_no_subscription('Plan Change Co');
  PERFORM public.ensure_initial_company_subscription(v_c3);

  SELECT sms_credits_included INTO v_included FROM public.companies WHERE id = v_c3;
  IF v_included <> v_starter_allowance THEN
    RAISE EXCEPTION 'setup invalid: expected starter allowance %, got %', v_starter_allowance, v_included;
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM public.admin_set_company_subscription(v_c3, v_business_id, 'active'::public.company_subscription_status);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT sms_credits_included, sms_credits_purchased INTO v_included, v_purchased
  FROM public.companies WHERE id = v_c3;

  IF v_included <> v_business_allowance THEN
    RAISE EXCEPTION 'expected business allowance % after plan change, got %', v_business_allowance, v_included;
  END IF;
  IF v_purchased <> 0 THEN
    RAISE EXCEPTION 'expected purchased bucket still 0, got %', v_purchased;
  END IF;

  SELECT COUNT(*)::INT INTO v_ledger_count
  FROM public.sms_credit_ledger
  WHERE company_id = v_c3 AND reason = 'included_allowance_expired' AND bucket = 'included';
  IF v_ledger_count <> 1 THEN
    RAISE EXCEPTION 'expected exactly 1 forfeiture ledger entry, got %', v_ledger_count;
  END IF;

  -- Enterprise is priced 0 (custom/contact-sales) — confirm SMS provisioning
  -- is entirely decoupled from price and still grants Enterprise's real
  -- catalog allowance correctly.
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM public.admin_set_company_subscription(v_c3, v_enterprise_id, 'active'::public.company_subscription_status);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT sms_credits_included INTO v_included FROM public.companies WHERE id = v_c3;
  IF v_included <> v_enterprise_allowance THEN
    RAISE EXCEPTION 'expected enterprise allowance % after second plan change, got %', v_enterprise_allowance, v_included;
  END IF;

  INSERT INTO sms_prov_assertions VALUES ('plan_change_no_rollover', true);

  -- ===========================================================================
  -- 4) Manual top-up lands in the purchased bucket and survives a
  --    subsequent plan-change provisioning event untouched.
  -- ===========================================================================
  SELECT company_id, owner_id INTO v_c4, v_o4 FROM pg_temp.make_company_no_subscription('Manual Topup Co');
  PERFORM public.ensure_initial_company_subscription(v_c4);

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM public.admin_add_sms_credits(v_c4, 50, 'admin_top_up');
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT sms_credits_included, sms_credits_purchased INTO v_included, v_purchased FROM public.companies WHERE id = v_c4;
  IF v_purchased <> 50 THEN
    RAISE EXCEPTION 'expected purchased balance 50 after top-up, got %', v_purchased;
  END IF;
  IF v_included <> v_starter_allowance THEN
    RAISE EXCEPTION 'expected included allowance untouched by top-up, got %', v_included;
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM public.admin_set_company_subscription(v_c4, v_business_id, 'active'::public.company_subscription_status);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT sms_credits_included, sms_credits_purchased INTO v_included, v_purchased FROM public.companies WHERE id = v_c4;
  IF v_purchased <> 50 THEN
    RAISE EXCEPTION 'expected purchased 50 to survive the plan change untouched, got %', v_purchased;
  END IF;
  IF v_included <> v_business_allowance THEN
    RAISE EXCEPTION 'expected new included allowance % after plan change, got %', v_business_allowance, v_included;
  END IF;

  SELECT COUNT(*)::INT INTO v_ledger_count
  FROM public.sms_credit_ledger WHERE company_id = v_c4 AND reason = 'admin_top_up' AND bucket = 'purchased';
  IF v_ledger_count <> 1 THEN
    RAISE EXCEPTION 'expected the manual top-up itself recorded once in the ledger, got %', v_ledger_count;
  END IF;

  INSERT INTO sms_prov_assertions VALUES ('manual_topup_preserved', true);

  -- ===========================================================================
  -- 5) Consumption order: queue_outbound_sms draws from included first, only
  --    reaching purchased once included is exhausted.
  -- ===========================================================================
  SELECT company_id, owner_id INTO v_c5, v_o5 FROM pg_temp.make_company_no_subscription('Consumption Order Co');
  PERFORM public.ensure_initial_company_subscription(v_c5);

  -- Drain included to exactly 1, add a small purchased balance.
  UPDATE public.companies SET sms_credits_included = 1 WHERE id = v_c5;
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM public.admin_add_sms_credits(v_c5, 3, 'admin_top_up');
  PERFORM set_config('request.jwt.claim.sub', '', true);

  PERFORM public.queue_outbound_sms(v_c5, '+231770000902', 'test message 1');
  SELECT sms_credits_included, sms_credits_purchased INTO v_included, v_purchased FROM public.companies WHERE id = v_c5;
  IF v_included <> 0 OR v_purchased <> 3 THEN
    RAISE EXCEPTION 'expected first send to draw from included (0/3), got (%/%)', v_included, v_purchased;
  END IF;

  PERFORM public.queue_outbound_sms(v_c5, '+231770000902', 'test message 2');
  SELECT sms_credits_included, sms_credits_purchased INTO v_included, v_purchased FROM public.companies WHERE id = v_c5;
  IF v_included <> 0 OR v_purchased <> 2 THEN
    RAISE EXCEPTION 'expected second send to draw from purchased (0/2), got (%/%)', v_included, v_purchased;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.sms_credit_ledger
    WHERE company_id = v_c5 AND reason = 'outbound_sms' AND bucket = 'included'
  ) IS NOT TRUE THEN
    RAISE EXCEPTION 'expected an included-bucket outbound_sms ledger entry';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.sms_credit_ledger
    WHERE company_id = v_c5 AND reason = 'outbound_sms' AND bucket = 'purchased'
  ) IS NOT TRUE THEN
    RAISE EXCEPTION 'expected a purchased-bucket outbound_sms ledger entry';
  END IF;

  INSERT INTO sms_prov_assertions VALUES ('consumption_order', true);

  -- ===========================================================================
  -- 6) Per-company isolation: activity on one company never touches another.
  -- ===========================================================================
  SELECT company_id, owner_id INTO v_c6, v_o6 FROM pg_temp.make_company_no_subscription('Isolation Co A');
  SELECT company_id, owner_id INTO v_c7, v_o7 FROM pg_temp.make_company_no_subscription('Isolation Co B');
  PERFORM public.ensure_initial_company_subscription(v_c6);
  PERFORM public.ensure_initial_company_subscription(v_c7);

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM public.admin_add_sms_credits(v_c6, 25, 'admin_top_up');
  PERFORM public.admin_set_company_subscription(v_c6, v_enterprise_id, 'active'::public.company_subscription_status);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM public.queue_outbound_sms(v_c6, '+231770000903', 'isolation test');

  SELECT sms_credits_included, sms_credits_purchased INTO v_included, v_purchased FROM public.companies WHERE id = v_c7;
  IF v_included <> v_starter_allowance OR v_purchased <> 0 THEN
    RAISE EXCEPTION 'expected company B unaffected by company A activity, got (%/%)', v_included, v_purchased;
  END IF;
  -- Company B legitimately has exactly one ledger entry of its own (its own
  -- trial provisioning from setup above) — none of company A's top-up,
  -- plan-change, or outbound-SMS entries should appear against company B.
  SELECT COUNT(*)::INT INTO v_ledger_count FROM public.sms_credit_ledger WHERE company_id = v_c7;
  IF v_ledger_count <> 1 THEN
    RAISE EXCEPTION 'expected exactly 1 ledger entry for company B (its own trial provisioning), got %', v_ledger_count;
  END IF;

  INSERT INTO sms_prov_assertions VALUES ('per_company_isolation', true);

  -- ===========================================================================
  -- 7) Auth OTP separation: an OTP-request-shaped auth.users insert (the
  --    same handle_new_user trigger every signInWithOtp call fires) must
  --    never change any company's sms_credits. Snapshot every company's
  --    total balance, insert the ghost identity, re-snapshot, diff.
  -- ===========================================================================
  CREATE TEMP TABLE sms_prov_balance_before AS
  SELECT id, sms_credits FROM public.companies;

  INSERT INTO auth.users (id, phone, email, encrypted_password, phone_confirmed_at, aud, role)
  VALUES (
    v_ghost_identity, '+231770000904',
    'sms-prov-ghost-' || substr(v_ghost_identity::text, 1, 8) || '@test.local',
    crypt('x', gen_salt('bf')), NULL, 'authenticated', 'authenticated'
  );

  IF EXISTS (
    SELECT 1
    FROM public.companies c
    JOIN sms_prov_balance_before b ON b.id = c.id
    WHERE c.sms_credits <> b.sms_credits
  ) THEN
    RAISE EXCEPTION 'an OTP-shaped auth.users insert changed at least one company sms_credits balance';
  END IF;

  INSERT INTO sms_prov_assertions VALUES ('otp_never_touches_credits', true);

  -- ===========================================================================
  -- 8) Plan allowance edits apply forward only: changing a plan's
  --    monthly_sms_allowance must not rewrite historical ledger entries.
  -- ===========================================================================
  UPDATE public.subscriptions SET monthly_sms_allowance = v_starter_allowance + 777 WHERE id = v_starter_id;

  SELECT delta INTO v_total
  FROM public.sms_credit_ledger
  WHERE company_id = v_c1 AND reason = 'plan_allowance_provisioned'
  ORDER BY created_at LIMIT 1;
  IF v_total <> v_starter_allowance THEN
    RAISE EXCEPTION 'expected historical ledger entry to stay at the original allowance %, got %', v_starter_allowance, v_total;
  END IF;

  -- Restore the catalog so nothing outside this file's transaction is
  -- affected (this whole file rolls back anyway, but keep it explicit).
  UPDATE public.subscriptions SET monthly_sms_allowance = v_starter_allowance WHERE id = v_starter_id;

  INSERT INTO sms_prov_assertions VALUES ('plan_edit_does_not_rewrite_history', true);
END;
$$;

SELECT ok((SELECT ok FROM sms_prov_assertions WHERE key = 'trial_provisioning'), 'trial creation grants the Starter plan''s current catalog allowance, and re-running ensure_initial_company_subscription does not double-credit');
SELECT ok((SELECT ok FROM sms_prov_assertions WHERE key = 'direct_double_call_idempotent'), 'a redundant direct call to provision_company_sms_allowance for the same row is a guaranteed no-op');
SELECT ok((SELECT ok FROM sms_prov_assertions WHERE key = 'plan_change_no_rollover'), 'changing plans forfeits the old included balance (no rollover) and grants the new plan''s current allowance, including Enterprise''s custom/zero-priced plan');
SELECT ok((SELECT ok FROM sms_prov_assertions WHERE key = 'manual_topup_preserved'), 'a manual super-admin top-up lands in the purchased bucket and survives a subsequent plan-change provisioning event');
SELECT ok((SELECT ok FROM sms_prov_assertions WHERE key = 'consumption_order'), 'queue_outbound_sms consumes included credits before purchased credits, correctly logging each bucket');
SELECT ok((SELECT ok FROM sms_prov_assertions WHERE key = 'per_company_isolation'), 'provisioning and consumption for one company never affects another company''s balance or ledger');
SELECT ok((SELECT ok FROM sms_prov_assertions WHERE key = 'otp_never_touches_credits'), 'an OTP-request-shaped auth.users insert never changes any company''s sms_credits');
SELECT ok((SELECT ok FROM sms_prov_assertions WHERE key = 'plan_edit_does_not_rewrite_history'), 'editing a plan''s monthly_sms_allowance does not rewrite historical sms_credit_ledger entries');

SELECT * FROM finish();
ROLLBACK;
