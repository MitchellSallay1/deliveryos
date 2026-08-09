BEGIN;
SELECT plan(8);

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

SELECT * FROM finish();
ROLLBACK;
