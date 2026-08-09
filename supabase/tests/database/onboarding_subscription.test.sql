BEGIN;
SELECT plan(12);

SELECT has_function('public', 'ensure_initial_company_subscription', ARRAY['uuid']);
SELECT has_function('public', 'expire_elapsed_company_trials', ARRAY['uuid']);

SELECT ok(
  EXISTS (SELECT 1 FROM public.subscriptions WHERE slug = 'starter'),
  'starter plan exists'
);

-- New company gets 7-day trialing subscription
DO $$
DECLARE
  v_company UUID := gen_random_uuid();
  v_plan UUID;
  v_sub public.company_subscriptions;
BEGIN
  SELECT id INTO v_plan FROM public.subscriptions WHERE slug = 'starter' LIMIT 1;

  INSERT INTO public.companies (id, name, slug, phone, email, status, subscription_id)
  VALUES (v_company, 'Trial Co', 'trial-co-' || substr(v_company::text, 1, 8), '+231770000099', 'trial@test.local', 'active', v_plan);

  v_sub := public.ensure_initial_company_subscription(v_company);

  IF v_sub.status <> 'trialing' THEN
    RAISE EXCEPTION 'expected trialing, got %', v_sub.status;
  END IF;

  IF v_sub.trial_ends_at IS NULL OR v_sub.current_period_end <> v_sub.trial_ends_at THEN
    RAISE EXCEPTION 'trial end must match period end';
  END IF;

  IF v_sub.trial_ends_at < now() + interval '6 days 23 hours'
     OR v_sub.trial_ends_at > now() + interval '7 days 1 hour' THEN
    RAISE EXCEPTION 'expected ~7 day trial window';
  END IF;

  DELETE FROM public.company_subscriptions WHERE company_id = v_company;
  DELETE FROM public.companies WHERE id = v_company;
END;
$$;

SELECT pass('new company gets 7-day trialing subscription');

-- Idempotent retry
DO $$
DECLARE
  v_company UUID := gen_random_uuid();
  v_plan UUID;
  v_count INT;
BEGIN
  SELECT id INTO v_plan FROM public.subscriptions WHERE slug = 'starter' LIMIT 1;
  INSERT INTO public.companies (id, name, slug, phone, email, status, subscription_id)
  VALUES (v_company, 'Idem Co', 'idem-' || substr(v_company::text, 1, 8), '+231770000088', 'idem@test.local', 'active', v_plan);

  PERFORM public.ensure_initial_company_subscription(v_company);
  PERFORM public.ensure_initial_company_subscription(v_company);

  SELECT COUNT(*)::INT INTO v_count
  FROM public.company_subscriptions WHERE company_id = v_company;

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'expected one subscription row, got %', v_count;
  END IF;

  DELETE FROM public.company_subscriptions WHERE company_id = v_company;
  DELETE FROM public.companies WHERE id = v_company;
END;
$$;

SELECT pass('onboarding retry does not duplicate subscription');

-- Preserve existing active subscription
DO $$
DECLARE
  v_company UUID := gen_random_uuid();
  v_plan UUID;
  v_existing UUID;
  v_returned UUID;
BEGIN
  SELECT id INTO v_plan FROM public.subscriptions WHERE slug = 'starter' LIMIT 1;
  INSERT INTO public.companies (id, name, slug, phone, email, status, subscription_id)
  VALUES (v_company, 'Active Co', 'active-' || substr(v_company::text, 1, 8), '+231770000087', 'active@test.local', 'active', v_plan);

  INSERT INTO public.company_subscriptions (
    company_id, plan_id, status, starts_at, current_period_start, current_period_end
  ) VALUES (
    v_company, v_plan, 'active', now(), now(), now() + interval '30 days'
  )
  RETURNING id INTO v_existing;

  v_returned := (public.ensure_initial_company_subscription(v_company)).id;
  IF v_returned <> v_existing THEN
    RAISE EXCEPTION 'must preserve active subscription';
  END IF;

  DELETE FROM public.company_subscriptions WHERE company_id = v_company;
  DELETE FROM public.companies WHERE id = v_company;
END;
$$;

SELECT pass('existing active subscription preserved');

-- Rider and delivery allowed during trial
DO $$
DECLARE
  v_company UUID := gen_random_uuid();
  v_plan UUID;
  v_max_riders INT;
BEGIN
  SELECT id, max_riders INTO v_plan, v_max_riders FROM public.subscriptions WHERE slug = 'starter' LIMIT 1;

  INSERT INTO public.companies (id, name, slug, phone, email, status, subscription_id)
  VALUES (v_company, 'Ops Trial Co', 'ops-trial-' || substr(v_company::text, 1, 8), '+231770000086', 'ops@test.local', 'active', v_plan);

  PERFORM public.ensure_initial_company_subscription(v_company);
  PERFORM public.assert_subscription_operational(v_company);

  INSERT INTO public.riders (company_id, full_name, phone, rider_code, status)
  VALUES (v_company, 'Rider', '+231770000001', 'R-T-1', 'available');

  INSERT INTO public.deliveries (
    company_id, tracking_code, pickup_business_name, pickup_address,
    customer_name, customer_phone, destination_address, status
  ) VALUES (
    v_company, 'TRK-' || substr(v_company::text, 1, 8), 'Shop', 'Addr A', 'Cust', '+231770000002', 'Addr B', 'pending'
  );

  IF v_max_riders IS NULL OR v_max_riders < 1 THEN
    RAISE EXCEPTION 'starter plan must define rider limit';
  END IF;

  DELETE FROM public.deliveries WHERE company_id = v_company;
  DELETE FROM public.riders WHERE company_id = v_company;
  DELETE FROM public.company_subscriptions WHERE company_id = v_company;
  DELETE FROM public.companies WHERE id = v_company;
END;
$$;

SELECT pass('rider and delivery creation allowed during trial');

-- Trial expiry blocks operational creation but history readable
DO $$
DECLARE
  v_company UUID := gen_random_uuid();
  v_plan UUID;
  v_delivery_count INT;
  v_blocked BOOLEAN := false;
BEGIN
  SELECT id INTO v_plan FROM public.subscriptions WHERE slug = 'starter' LIMIT 1;
  INSERT INTO public.companies (id, name, slug, phone, email, status, subscription_id)
  VALUES (v_company, 'Expired Co', 'expired-' || substr(v_company::text, 1, 8), '+231770000085', 'exp@test.local', 'active', v_plan);

  PERFORM public.ensure_initial_company_subscription(v_company);

  INSERT INTO public.riders (company_id, full_name, phone, rider_code, status)
  VALUES (v_company, 'Rider Old', '+231770000003', 'R-OLD', 'available');

  INSERT INTO public.deliveries (
    company_id, tracking_code, pickup_business_name, pickup_address,
    customer_name, customer_phone, destination_address, status
  ) VALUES (
    v_company, 'TRK-EXP-' || substr(v_company::text, 1, 6), 'Shop', 'A', 'C', '+231770000004', 'B', 'delivered'
  );

  UPDATE public.company_subscriptions
  SET trial_ends_at = now() - interval '1 hour',
      current_period_end = now() - interval '1 hour'
  WHERE company_id = v_company AND status = 'trialing';

  BEGIN
    PERFORM public.assert_subscription_operational(v_company);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%trial_expired%' THEN
      RAISE;
    END IF;
    v_blocked := true;
  END;

  IF NOT v_blocked THEN
    RAISE EXCEPTION 'expected trial_expired after expiry';
  END IF;

  SELECT COUNT(*)::INT INTO v_delivery_count FROM public.deliveries WHERE company_id = v_company;
  IF v_delivery_count < 1 THEN
    RAISE EXCEPTION 'historical deliveries must remain readable';
  END IF;

  DELETE FROM public.deliveries WHERE company_id = v_company;
  DELETE FROM public.riders WHERE company_id = v_company;
  DELETE FROM public.company_subscriptions WHERE company_id = v_company;
  DELETE FROM public.companies WHERE id = v_company;
END;
$$;

SELECT pass('expired trial blocks ops but keeps historical data');

-- Self-service registration (the real create_company_with_owner RPC, not a
-- raw INSERT) activates the company immediately and starts the trial —
-- this is the foundation fix under test, not just its downstream effects.
DO $$
DECLARE
  v_user UUID := gen_random_uuid();
  v_company UUID;
  v_status public.company_status;
  v_sub_status public.company_subscription_status;
BEGIN
  INSERT INTO auth.users (id, phone, email, encrypted_password, phone_confirmed_at, aud, role)
  VALUES (
    v_user, '+231770000201', 'foundation-owner-' || substr(v_user::text, 1, 8) || '@test.local',
    crypt('x', gen_salt('bf')), now(), 'authenticated', 'authenticated'
  );
  INSERT INTO public.profiles (id, full_name) VALUES (v_user, 'Foundation Owner')
  ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name;

  PERFORM set_config('request.jwt.claim.sub', v_user::text, true);
  v_company := public.create_company_with_owner(
    'Foundation Co', '+231770000201', 'foundation@test.local', NULL,
    'logistics_provider'::public.company_business_type
  );
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT status INTO v_status FROM public.companies WHERE id = v_company;
  IF v_status <> 'active' THEN
    RAISE EXCEPTION 'expected self-service company to be active immediately, got %', v_status;
  END IF;

  SELECT status INTO v_sub_status FROM public.company_subscriptions WHERE company_id = v_company;
  IF v_sub_status <> 'trialing' THEN
    RAISE EXCEPTION 'expected trialing subscription immediately, got %', v_sub_status;
  END IF;

  DELETE FROM public.company_subscriptions WHERE company_id = v_company;
  DELETE FROM public.company_users WHERE company_id = v_company;
  DELETE FROM public.companies WHERE id = v_company;
  DELETE FROM public.profiles WHERE id = v_user;
  DELETE FROM auth.users WHERE id = v_user;
END;
$$;

SELECT pass('self-service company registration activates immediately with a trialing subscription');

-- Merchant registration goes through the same function and must behave the
-- same way — active immediately — while keeping its business-type-specific
-- behavior (no provider_marketplace_profiles row) intact.
DO $$
DECLARE
  v_user UUID := gen_random_uuid();
  v_company UUID;
  v_status public.company_status;
  v_btype public.company_business_type;
  v_profile_count INT;
BEGIN
  INSERT INTO auth.users (id, phone, email, encrypted_password, phone_confirmed_at, aud, role)
  VALUES (
    v_user, '+231770000202', 'foundation-merchant-' || substr(v_user::text, 1, 8) || '@test.local',
    crypt('x', gen_salt('bf')), now(), 'authenticated', 'authenticated'
  );
  INSERT INTO public.profiles (id, full_name) VALUES (v_user, 'Foundation Merchant')
  ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name;

  PERFORM set_config('request.jwt.claim.sub', v_user::text, true);
  v_company := public.create_company_with_owner(
    'Foundation Merchant Co', '+231770000202', 'foundation-merchant@test.local', NULL,
    'merchant'::public.company_business_type
  );
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT status, business_type INTO v_status, v_btype FROM public.companies WHERE id = v_company;
  IF v_status <> 'active' THEN
    RAISE EXCEPTION 'expected merchant company to be active immediately, got %', v_status;
  END IF;
  IF v_btype <> 'merchant' THEN
    RAISE EXCEPTION 'expected business_type merchant, got %', v_btype;
  END IF;

  SELECT COUNT(*)::INT INTO v_profile_count
  FROM public.provider_marketplace_profiles WHERE company_id = v_company;
  IF v_profile_count <> 0 THEN
    RAISE EXCEPTION 'merchant companies must not get a provider_marketplace_profiles row';
  END IF;

  DELETE FROM public.company_subscriptions WHERE company_id = v_company;
  DELETE FROM public.company_users WHERE company_id = v_company;
  DELETE FROM public.companies WHERE id = v_company;
  DELETE FROM public.profiles WHERE id = v_user;
  DELETE FROM auth.users WHERE id = v_user;
END;
$$;

SELECT pass('merchant registration activates immediately and keeps merchant-specific behavior');

-- A super admin can suspend an active trial company, and once suspended it
-- stays blocked from operational writes — the activation fix must not
-- weaken this in any way.
DO $$
DECLARE
  v_owner UUID := gen_random_uuid();
  v_admin UUID := gen_random_uuid();
  v_company UUID;
  v_status public.company_status;
  v_blocked BOOLEAN := false;
BEGIN
  INSERT INTO auth.users (id, phone, email, encrypted_password, phone_confirmed_at, aud, role)
  VALUES (
    v_owner, '+231770000203', 'foundation-susp-owner-' || substr(v_owner::text, 1, 8) || '@test.local',
    crypt('x', gen_salt('bf')), now(), 'authenticated', 'authenticated'
  );
  INSERT INTO public.profiles (id, full_name) VALUES (v_owner, 'Suspend Target Owner')
  ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name;

  INSERT INTO auth.users (id, phone, email, encrypted_password, phone_confirmed_at, aud, role)
  VALUES (
    v_admin, '+231770000204', 'foundation-admin-' || substr(v_admin::text, 1, 8) || '@test.local',
    crypt('x', gen_salt('bf')), now(), 'authenticated', 'authenticated'
  );
  INSERT INTO public.profiles (id, full_name, is_super_admin) VALUES (v_admin, 'Platform Admin', true)
  ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, is_super_admin = true;

  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  v_company := public.create_company_with_owner(
    'Suspend Target Co', '+231770000203', 'foundation-susp@test.local', NULL,
    'logistics_provider'::public.company_business_type
  );
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT status INTO v_status FROM public.companies WHERE id = v_company;
  IF v_status <> 'active' THEN
    RAISE EXCEPTION 'expected company active before suspension test, got %', v_status;
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM public.admin_set_company_status(v_company, 'suspended'::public.company_status);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT status INTO v_status FROM public.companies WHERE id = v_company;
  IF v_status <> 'suspended' THEN
    RAISE EXCEPTION 'expected super admin suspension to take effect, got %', v_status;
  END IF;

  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
    PERFORM public.create_delivery(
      v_company, 'Pickup Shop', 'Monrovia', 'Customer', '+231770000399', 'Destination St'
    );
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%company_suspended%' AND SQLERRM NOT LIKE '%company_not_operational%' THEN
      RAISE;
    END IF;
    v_blocked := true;
  END;

  IF NOT v_blocked THEN
    RAISE EXCEPTION 'expected suspended company to be blocked from creating deliveries';
  END IF;

  DELETE FROM public.company_subscriptions WHERE company_id = v_company;
  DELETE FROM public.company_users WHERE company_id = v_company;
  DELETE FROM public.companies WHERE id = v_company;
  DELETE FROM public.profiles WHERE id IN (v_owner, v_admin);
  DELETE FROM auth.users WHERE id IN (v_owner, v_admin);
END;
$$;

SELECT pass('super admin can suspend an active trial company, and it stays blocked');

-- The activation fix is a CREATE OR REPLACE FUNCTION only — it must never
-- retroactively touch existing rows. Directly-inserted companies (standing
-- in for pre-migration data) keep whatever status they already had.
DO $$
DECLARE
  v_plan UUID;
  v_pending UUID := gen_random_uuid();
  v_suspended UUID := gen_random_uuid();
  v_already_active UUID := gen_random_uuid();
  v_status public.company_status;
BEGIN
  SELECT id INTO v_plan FROM public.subscriptions WHERE slug = 'starter' LIMIT 1;

  INSERT INTO public.companies (id, name, slug, phone, email, status, subscription_id)
  VALUES
    (v_pending, 'Preexisting Pending', 'pre-pending-' || substr(v_pending::text, 1, 8), '+231770000301', 'p@test.local', 'pending', v_plan),
    (v_suspended, 'Preexisting Suspended', 'pre-suspended-' || substr(v_suspended::text, 1, 8), '+231770000302', 's@test.local', 'suspended', v_plan),
    (v_already_active, 'Preexisting Active', 'pre-active-' || substr(v_already_active::text, 1, 8), '+231770000303', 'a@test.local', 'active', v_plan);

  -- Unrelated activity on the database (another company's onboarding)
  -- must not touch these rows.
  PERFORM public.ensure_initial_company_subscription(v_already_active);

  SELECT status INTO v_status FROM public.companies WHERE id = v_pending;
  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'pre-existing pending company must stay pending, got %', v_status;
  END IF;

  SELECT status INTO v_status FROM public.companies WHERE id = v_suspended;
  IF v_status <> 'suspended' THEN
    RAISE EXCEPTION 'pre-existing suspended company must never be auto-reactivated, got %', v_status;
  END IF;

  SELECT status INTO v_status FROM public.companies WHERE id = v_already_active;
  IF v_status <> 'active' THEN
    RAISE EXCEPTION 'pre-existing active company must stay active, got %', v_status;
  END IF;

  DELETE FROM public.company_subscriptions WHERE company_id = v_already_active;
  DELETE FROM public.companies WHERE id IN (v_pending, v_suspended, v_already_active);
END;
$$;

SELECT pass('the activation migration never retroactively modifies existing companies');

SELECT * FROM finish();
ROLLBACK;
