-- Regression coverage for the 25006 "cannot execute UPDATE in a read-only
-- transaction" production bug: get_active_company_subscription (STABLE)
-- was performing a nested write via expire_elapsed_company_trials, and
-- get_company_usage (STABLE) had its own independent instance of the same
-- anti-pattern. See 20260308193500_fix_subscription_read_path_volatility.sql.
--
-- Postgres does not allow switching a transaction back to READ WRITE after
-- any statement has executed under READ ONLY, so this file does all setup
-- writes (including the write-path scenarios) first, then switches the
-- transaction to READ ONLY once, near the end, to prove the read helpers
-- genuinely work under the same conditions PostgREST imposes on STABLE
-- RPCs. Nothing after that point performs a write — pgTAP's plan/pass
-- bookkeeping uses temp tables, which Postgres explicitly permits inside a
-- read-only transaction, and the final ROLLBACK needs no write permission.

BEGIN;
SELECT plan(9);

SELECT has_function('public', 'get_active_company_subscription', ARRAY['uuid']);
SELECT has_function('public', 'get_company_usage', ARRAY['uuid']);

-- ---------------------------------------------------------------------------
-- Helper: create a company + owner + trialing subscription with a given
-- trial_ends_at, wired up so assert_company_member / user_company_ids /
-- has_company_role all resolve for the returned owner.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.make_trial_company(
  p_label TEXT,
  p_trial_ends_at TIMESTAMPTZ
) RETURNS TABLE (company_id UUID, owner_id UUID) LANGUAGE plpgsql AS $$
DECLARE
  v_owner UUID := gen_random_uuid();
  v_company UUID := gen_random_uuid();
  v_plan UUID;
BEGIN
  SELECT id INTO v_plan FROM public.subscriptions WHERE slug = 'starter' LIMIT 1;

  INSERT INTO auth.users (id, phone, email, encrypted_password, phone_confirmed_at, aud, role)
  VALUES (
    v_owner, '+23177' || lpad((floor(random() * 999999))::text, 6, '0'),
    'ro-path-' || substr(v_owner::text, 1, 8) || '@test.local',
    crypt('x', gen_salt('bf')), now(), 'authenticated', 'authenticated'
  );
  INSERT INTO public.profiles (id, full_name) VALUES (v_owner, p_label)
  ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name;

  INSERT INTO public.companies (id, name, slug, phone, email, status, subscription_id)
  VALUES (v_company, p_label, 'ro-path-' || substr(v_company::text, 1, 8), '+231770000500', p_label || '@test.local', 'active', v_plan);

  INSERT INTO public.company_users (company_id, user_id, role, is_active)
  VALUES (v_company, v_owner, 'company_owner', true);

  INSERT INTO public.company_subscriptions (
    company_id, plan_id, status, starts_at, trial_ends_at, current_period_start, current_period_end
  ) VALUES (
    v_company, v_plan, 'trialing', now() - interval '1 day', p_trial_ends_at, now() - interval '1 day', p_trial_ends_at
  );

  RETURN QUERY SELECT v_company, v_owner;
END;
$$;

-- ===========================================================================
-- PHASE A (read-write): create every company this file needs, and run the
-- two write-path scenarios (5 and 6) to completion, since they need to
-- perform and verify an actual UPDATE.
-- ===========================================================================
DO $$
DECLARE
  v_c1 UUID; v_o1 UUID; -- get_workspace_report under read-only
  v_c2 UUID; v_o2 UUID; -- get_company_usage under read-only
  v_c3 UUID; v_o3 UUID; -- list_company_rider_locations gps gate under read-only
  v_c4 UUID; v_o4 UUID; -- logically-elapsed-but-not-mutated trial
  v_c7 UUID; v_o7 UUID; -- paid active subscription
BEGIN
  SELECT company_id, owner_id INTO v_c1, v_o1 FROM pg_temp.make_trial_company('RO Active Trial', now() + interval '3 days');
  SELECT company_id, owner_id INTO v_c2, v_o2 FROM pg_temp.make_trial_company('RO Usage Trial', now() + interval '3 days');
  SELECT company_id, owner_id INTO v_c3, v_o3 FROM pg_temp.make_trial_company('RO GPS Gate Trial', now() + interval '3 days');
  SELECT company_id, owner_id INTO v_c4, v_o4 FROM pg_temp.make_trial_company('Logically Elapsed Trial', now() - interval '1 hour');

  -- Stash the ids pgTAP needs later, outside this DO block's scope, using a
  -- session-level temp table (also permitted under read-only).
  CREATE TEMP TABLE ro_path_fixtures (key TEXT PRIMARY KEY, company_id UUID, owner_id UUID);
  INSERT INTO ro_path_fixtures VALUES
    ('c1', v_c1, v_o1),
    ('c2', v_c2, v_o2),
    ('c3', v_c3, v_o3),
    ('c4', v_c4, v_o4);
END;
$$;

-- 5) Operational writes still correctly block an expired trial
--    (assert_subscription_operational remains write-capable and unchanged).
--
-- Note on the row's physical status here: assert_subscription_operational
-- attempts an inline expiry before raising 'trial_expired', but that inline
-- UPDATE is only durable if the caller does NOT catch the exception within
-- the same subtransaction — PL/pgSQL's EXCEPTION block is an implicit
-- savepoint, so catching the RAISE (as this test does, and as an
-- uncaught-all-the-way-to-PostgREST error effectively also does at the
-- whole-request level) rolls that inline UPDATE back too. This is
-- pre-existing behavior, unrelated to this fix. It's exactly why the
-- requested architecture designates the *standalone* expire_elapsed_
-- company_trials sweep (test 6, and run_scheduled_maintenance_jobs in
-- production) as the reliable persistence path, not this inline attempt —
-- so this test only asserts the blocking behavior, then confirms the
-- standalone sweep can still reliably expire the same row afterward.
DO $$
DECLARE
  v_company UUID;
  v_owner UUID;
  v_blocked BOOLEAN := false;
  v_physical_status public.company_subscription_status;
BEGIN
  SELECT company_id, owner_id INTO v_company, v_owner
  FROM pg_temp.make_trial_company('Operational Expiry Trial', now() - interval '1 hour');

  BEGIN
    PERFORM public.assert_subscription_operational(v_company);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%trial_expired%' THEN
      RAISE;
    END IF;
    v_blocked := true;
  END;

  IF NOT v_blocked THEN
    RAISE EXCEPTION 'expected trial_expired from assert_subscription_operational';
  END IF;

  -- The reliable persistence path still works on this same row.
  PERFORM public.expire_elapsed_company_trials(v_company);
  SELECT status INTO v_physical_status FROM public.company_subscriptions WHERE company_id = v_company;
  IF v_physical_status <> 'expired' THEN
    RAISE EXCEPTION 'expected the standalone sweep to expire the row, got %', v_physical_status;
  END IF;
END;
$$;

SELECT pass('assert_subscription_operational still blocks an elapsed trial; the standalone sweep still expires it');

-- 6) Scheduled maintenance (expire_elapsed_company_trials) can still
--    persist trialing -> expired for a company nobody has touched yet.
DO $$
DECLARE
  v_company UUID;
  v_owner UUID;
  v_expired_count INT;
  v_physical_status public.company_subscription_status;
BEGIN
  SELECT company_id, owner_id INTO v_company, v_owner
  FROM pg_temp.make_trial_company('Sweep Expiry Trial', now() - interval '1 hour');

  v_expired_count := public.expire_elapsed_company_trials(v_company);
  IF v_expired_count <> 1 THEN
    RAISE EXCEPTION 'expected expire_elapsed_company_trials to report 1 row expired, got %', v_expired_count;
  END IF;

  SELECT status INTO v_physical_status FROM public.company_subscriptions WHERE company_id = v_company;
  IF v_physical_status <> 'expired' THEN
    RAISE EXCEPTION 'expected physical status expired after scheduled sweep, got %', v_physical_status;
  END IF;
END;
$$;

SELECT pass('scheduled maintenance (expire_elapsed_company_trials) still persists trialing -> expired');

-- Paid active subscription fixture for test 7.
DO $$
DECLARE
  v_owner UUID := gen_random_uuid();
  v_company UUID := gen_random_uuid();
  v_plan UUID;
BEGIN
  SELECT id INTO v_plan FROM public.subscriptions WHERE slug = 'business' LIMIT 1;

  INSERT INTO auth.users (id, phone, email, encrypted_password, phone_confirmed_at, aud, role)
  VALUES (
    v_owner, '+231770000599', 'ro-path-paid-' || substr(v_owner::text, 1, 8) || '@test.local',
    crypt('x', gen_salt('bf')), now(), 'authenticated', 'authenticated'
  );
  INSERT INTO public.profiles (id, full_name) VALUES (v_owner, 'Paid Plan Owner')
  ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name;

  INSERT INTO public.companies (id, name, slug, phone, email, status, subscription_id)
  VALUES (v_company, 'Paid Plan Co', 'ro-path-paid-' || substr(v_company::text, 1, 8), '+231770000598', 'paid@test.local', 'active', v_plan);

  INSERT INTO public.company_users (company_id, user_id, role, is_active)
  VALUES (v_company, v_owner, 'company_owner', true);

  INSERT INTO public.company_subscriptions (
    company_id, plan_id, status, starts_at, current_period_start, current_period_end
  ) VALUES (
    v_company, v_plan, 'active', now() - interval '5 days', now() - interval '5 days', now() + interval '25 days'
  );

  INSERT INTO ro_path_fixtures VALUES ('c7', v_company, v_owner);
END;
$$;

-- ===========================================================================
-- PHASE B (read-only from here to the end of the file): prove the actual
-- reported-broken RPCs, and the logical-exclusion behavior, work under the
-- exact transaction mode PostgREST uses for STABLE-marked RPCs.
-- ===========================================================================
SET LOCAL transaction_read_only = on;

-- 1) get_workspace_report(..., 'day') succeeds in a read-only transaction
--    for an active (unexpired) trial.
DO $$
DECLARE
  v_company UUID;
  v_owner UUID;
BEGIN
  SELECT company_id, owner_id INTO v_company, v_owner FROM ro_path_fixtures WHERE key = 'c1';
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM public.get_workspace_report(v_company, 'day');
END;
$$;

SELECT pass('get_workspace_report(..., ''day'') succeeds inside a read-only transaction for an active trial');

-- 2) get_company_usage() succeeds in a read-only transaction.
DO $$
DECLARE
  v_company UUID;
  v_owner UUID;
BEGIN
  SELECT company_id, owner_id INTO v_company, v_owner FROM ro_path_fixtures WHERE key = 'c2';
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM public.get_company_usage(v_company);
END;
$$;

SELECT pass('get_company_usage() succeeds inside a read-only transaction');

-- 3) list_company_rider_locations() on a Starter-plan company reaches the
--    expected gps_not_enabled plan gate — not a 25006 read-only failure —
--    inside a read-only transaction.
DO $$
DECLARE
  v_company UUID;
  v_owner UUID;
  v_hit_gate BOOLEAN := false;
BEGIN
  SELECT company_id, owner_id INTO v_company, v_owner FROM ro_path_fixtures WHERE key = 'c3';
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  BEGIN
    PERFORM public.list_company_rider_locations(v_company);
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '25006' THEN
      RAISE EXCEPTION 'list_company_rider_locations hit 25006 (read-only transaction violation), not the plan gate';
    END IF;
    IF SQLERRM NOT LIKE '%gps_not_enabled%' THEN
      RAISE;
    END IF;
    v_hit_gate := true;
  END;

  IF NOT v_hit_gate THEN
    RAISE EXCEPTION 'expected gps_not_enabled for a Starter-plan company';
  END IF;
END;
$$;

SELECT pass('list_company_rider_locations reaches gps_not_enabled on Starter, not a 25006 read-only error');

-- 4) An elapsed trial is treated as non-operational by every read helper
--    the instant its trial_ends_at passes, even though its physical status
--    column has NOT yet been mutated to 'expired' — proven under a
--    read-only transaction, so this also confirms no read helper attempts
--    a write to reach this conclusion.
DO $$
DECLARE
  v_company UUID;
  v_owner UUID;
  v_active public.company_subscriptions;
  v_can_sms BOOLEAN;
  v_usage JSONB;
  v_physical_status public.company_subscription_status;
BEGIN
  SELECT company_id, owner_id INTO v_company, v_owner FROM ro_path_fixtures WHERE key = 'c4';

  SELECT status INTO v_physical_status FROM public.company_subscriptions WHERE company_id = v_company;
  IF v_physical_status <> 'trialing' THEN
    RAISE EXCEPTION 'test setup invalid: expected physical status trialing, got %', v_physical_status;
  END IF;

  v_active := public.get_active_company_subscription(v_company);
  IF v_active.id IS NOT NULL THEN
    RAISE EXCEPTION 'get_active_company_subscription must logically exclude an elapsed trial';
  END IF;

  v_can_sms := public.can_use_feature(v_company, 'sms_notifications');
  IF v_can_sms THEN
    RAISE EXCEPTION 'can_use_feature must not grant access via an elapsed-but-not-yet-mutated trial';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  v_usage := public.get_company_usage(v_company);
  IF NOT (v_usage -> 'trial' ->> 'expired')::BOOLEAN THEN
    RAISE EXCEPTION 'get_company_usage must report the trial as expired based on trial_ends_at, not just the status column';
  END IF;

  -- Still not physically mutated — confirms these read helpers performed
  -- no write, which is exactly why they can run under read-only at all.
  SELECT status INTO v_physical_status FROM public.company_subscriptions WHERE company_id = v_company;
  IF v_physical_status <> 'trialing' THEN
    RAISE EXCEPTION 'read helpers must never mutate the row; physical status changed to %', v_physical_status;
  END IF;
END;
$$;

SELECT pass('an elapsed trial is excluded by read helpers under a read-only transaction, without any row mutation');

-- 7) Paid active subscriptions are unaffected by the trial-exclusion logic.
DO $$
DECLARE
  v_company UUID;
  v_owner UUID;
  v_active public.company_subscriptions;
  v_usage JSONB;
BEGIN
  SELECT company_id, owner_id INTO v_company, v_owner FROM ro_path_fixtures WHERE key = 'c7';

  v_active := public.get_active_company_subscription(v_company);
  IF v_active.id IS NULL OR v_active.status <> 'active' THEN
    RAISE EXCEPTION 'expected the active paid subscription to be returned unchanged';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  v_usage := public.get_company_usage(v_company);

  IF (v_usage -> 'trial' ->> 'is_free_trial')::BOOLEAN THEN
    RAISE EXCEPTION 'paid active subscription must not be reported as a free trial';
  END IF;
  IF v_usage -> 'subscription' ->> 'status' <> 'active' THEN
    RAISE EXCEPTION 'expected usage.subscription.status = active';
  END IF;
END;
$$;

SELECT pass('paid active subscriptions are unaffected, verified under a read-only transaction');

SELECT * FROM finish();
ROLLBACK;
