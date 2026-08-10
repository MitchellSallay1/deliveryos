-- Coverage for admin_list_platform_users / admin_platform_user_funnel
-- (20260308194000_admin_platform_user_lifecycle.sql), added after the phone
-- auth lifecycle audit found that Super Admin's "Platform users" page
-- queried public.profiles directly/unfiltered — which counts unverified
-- ghost profiles (created the instant signInWithOtp is called, before the
-- OTP is ever entered) as if they were registered users.
--
-- Proves: (1) lifecycle_status is derived correctly for every real state —
-- unverified, verified_incomplete, active (via company or rider), and
-- super_admin; (2) the funnel counts identities/verified/active/stale
-- ghosts correctly; (3) neither RPC mutates auth.users; (4) both RPCs fail
-- closed for any non-super-admin caller, including an unrecognized/anon
-- identity.

BEGIN;
SELECT plan(12);

SELECT has_function('public'::name, 'admin_list_platform_users'::name);
SELECT has_function('public'::name, 'admin_platform_user_funnel'::name);

CREATE OR REPLACE FUNCTION pg_temp.make_lifecycle_fixture(
  p_label TEXT,
  p_phone TEXT,
  p_created_at TIMESTAMPTZ,
  p_phone_confirmed_at TIMESTAMPTZ,
  p_super_admin BOOLEAN DEFAULT false
) RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
  v_user UUID := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, phone, email, encrypted_password, phone_confirmed_at, aud, role, created_at)
  VALUES (
    v_user, p_phone, 'lc-fixture-' || substr(v_user::text, 1, 8) || '@test.local',
    crypt('x', gen_salt('bf')), p_phone_confirmed_at, 'authenticated', 'authenticated', p_created_at
  );
  INSERT INTO public.profiles (id, full_name, is_super_admin)
  VALUES (v_user, p_label, p_super_admin)
  ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, is_super_admin = EXCLUDED.is_super_admin;
  RETURN v_user;
END;
$$;

DO $$
DECLARE
  v_tag TEXT := substr(gen_random_uuid()::text, 1, 8);
  v_admin UUID;
  v_unverified UUID;
  v_verified_incomplete UUID;
  v_active_company UUID;
  v_active_rider UUID;
  v_super_admin_subject UUID;
  v_stale_unverified UUID;
  v_company UUID;
  v_plan UUID;
  v_rider UUID;
  v_funnel_before JSONB;
  v_funnel_after JSONB;
  v_result JSONB;
  v_rows JSONB;
  v_row JSONB;
  v_before_confirmed TIMESTAMPTZ;
  v_before_signin TIMESTAMPTZ;
  v_after_confirmed TIMESTAMPTZ;
  v_after_signin TIMESTAMPTZ;
  v_forbidden BOOLEAN;
BEGIN
  -- Acting super admin caller, created before the funnel baseline so it is
  -- part of the "before" snapshot, not the measured delta.
  v_admin := pg_temp.make_lifecycle_fixture(
    'LC Admin Caller ' || v_tag, '+23177' || lpad((floor(random() * 999999))::text, 6, '0'),
    now(), now(), true
  );

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  v_funnel_before := public.admin_platform_user_funnel();

  -- (a) unverified: OTP requested, never entered — the exact ghost case
  -- from the audit. phone_confirmed_at IS NULL.
  v_unverified := pg_temp.make_lifecycle_fixture(
    'LC-' || v_tag || '-Unverified', '+23177' || lpad((floor(random() * 999999))::text, 6, '0'),
    now(), NULL
  );

  -- (b) verified_incomplete: phone verified, abandoned before finishing
  -- onboarding (no company_users row, no rider link).
  v_verified_incomplete := pg_temp.make_lifecycle_fixture(
    'LC-' || v_tag || '-VerifiedIncomplete', '+23177' || lpad((floor(random() * 999999))::text, 6, '0'),
    now(), now()
  );

  -- (c) active via company membership.
  v_active_company := pg_temp.make_lifecycle_fixture(
    'LC-' || v_tag || '-ActiveCompany', '+23177' || lpad((floor(random() * 999999))::text, 6, '0'),
    now(), now()
  );
  SELECT phone_confirmed_at, last_sign_in_at INTO v_before_confirmed, v_before_signin
  FROM auth.users WHERE id = v_active_company;
  SELECT id INTO v_plan FROM public.subscriptions WHERE slug = 'starter' LIMIT 1;
  INSERT INTO public.companies (id, name, slug, phone, email, status, subscription_id)
  VALUES (
    gen_random_uuid(), 'LC Co ' || v_tag, 'lc-co-' || v_tag, '+231770000700', 'lc-' || v_tag || '@test.local',
    'active', v_plan
  ) RETURNING id INTO v_company;
  INSERT INTO public.company_users (company_id, user_id, role, is_active)
  VALUES (v_company, v_active_company, 'company_owner', true);

  -- (d) active via linked rider account (no company membership row at all).
  v_active_rider := pg_temp.make_lifecycle_fixture(
    'LC-' || v_tag || '-ActiveRider', '+23177' || lpad((floor(random() * 999999))::text, 6, '0'),
    now(), now()
  );
  INSERT INTO public.riders (id, company_id, user_id, rider_code, full_name, phone, status)
  VALUES (gen_random_uuid(), v_company, v_active_rider, 'LC-' || v_tag, 'LC Rider', '+231770000701', 'offline')
  RETURNING id INTO v_rider;

  -- (e) super_admin: lifecycle_status overrides to 'super_admin' regardless
  -- of membership.
  v_super_admin_subject := pg_temp.make_lifecycle_fixture(
    'LC-' || v_tag || '-SuperAdmin', '+23177' || lpad((floor(random() * 999999))::text, 6, '0'),
    now(), now(), true
  );

  -- (f) stale unverified ghost: never verified, requested 40 days ago —
  -- the exact population admin_platform_user_funnel's unverified_over_30d
  -- is meant to surface.
  v_stale_unverified := pg_temp.make_lifecycle_fixture(
    'LC-' || v_tag || '-StaleUnverified', '+23177' || lpad((floor(random() * 999999))::text, 6, '0'),
    now() - interval '40 days', NULL
  );

  -- ---------------------------------------------------------------------
  -- lifecycle_status derivation, via the RPC (as the super admin caller).
  -- ---------------------------------------------------------------------
  v_result := public.admin_list_platform_users('LC-' || v_tag, NULL, 50, 0);
  v_rows := v_result -> 'rows';

  IF jsonb_array_length(v_rows) <> 6 THEN
    RAISE EXCEPTION 'expected 6 tagged fixtures, got %', jsonb_array_length(v_rows);
  END IF;

  FOR v_row IN SELECT * FROM jsonb_array_elements(v_rows)
  LOOP
    IF (v_row ->> 'id')::UUID = v_unverified AND (v_row ->> 'lifecycle_status') <> 'unverified' THEN
      RAISE EXCEPTION 'unverified fixture got status %', v_row ->> 'lifecycle_status';
    ELSIF (v_row ->> 'id')::UUID = v_verified_incomplete AND (v_row ->> 'lifecycle_status') <> 'verified_incomplete' THEN
      RAISE EXCEPTION 'verified_incomplete fixture got status %', v_row ->> 'lifecycle_status';
    ELSIF (v_row ->> 'id')::UUID = v_active_company AND (v_row ->> 'lifecycle_status') <> 'active' THEN
      RAISE EXCEPTION 'active-via-company fixture got status %', v_row ->> 'lifecycle_status';
    ELSIF (v_row ->> 'id')::UUID = v_active_rider AND (v_row ->> 'lifecycle_status') <> 'active' THEN
      RAISE EXCEPTION 'active-via-rider fixture got status %', v_row ->> 'lifecycle_status';
    ELSIF (v_row ->> 'id')::UUID = v_super_admin_subject AND (v_row ->> 'lifecycle_status') <> 'super_admin' THEN
      RAISE EXCEPTION 'super_admin fixture got status %', v_row ->> 'lifecycle_status';
    ELSIF (v_row ->> 'id')::UUID = v_stale_unverified AND (v_row ->> 'lifecycle_status') <> 'unverified' THEN
      RAISE EXCEPTION 'stale unverified fixture got status %', v_row ->> 'lifecycle_status';
    END IF;
  END LOOP;

  CREATE TEMP TABLE lc_assertions (key TEXT PRIMARY KEY, ok BOOLEAN);
  INSERT INTO lc_assertions VALUES ('lifecycle_status', true);

  -- ---------------------------------------------------------------------
  -- status filter: 'unverified' -> exactly the 2 never-verified fixtures.
  -- ---------------------------------------------------------------------
  v_result := public.admin_list_platform_users('LC-' || v_tag, 'unverified', 50, 0);
  IF (v_result ->> 'total')::INT <> 2 THEN
    RAISE EXCEPTION 'expected 2 unverified fixtures, got %', v_result ->> 'total';
  END IF;
  INSERT INTO lc_assertions VALUES ('status_filter_unverified', true);

  -- status filter: 'active' -> exactly the 2 active fixtures.
  v_result := public.admin_list_platform_users('LC-' || v_tag, 'active', 50, 0);
  IF (v_result ->> 'total')::INT <> 2 THEN
    RAISE EXCEPTION 'expected 2 active fixtures, got %', v_result ->> 'total';
  END IF;
  INSERT INTO lc_assertions VALUES ('status_filter_active', true);

  -- invalid status filter is rejected, not silently ignored.
  v_forbidden := false;
  BEGIN
    PERFORM public.admin_list_platform_users('LC-' || v_tag, 'not_a_real_status', 50, 0);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%invalid status filter%' THEN
      RAISE;
    END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected an invalid status filter to raise, not be silently ignored';
  END IF;
  INSERT INTO lc_assertions VALUES ('invalid_status_rejected', true);

  -- ---------------------------------------------------------------------
  -- funnel deltas: 6 identities added, 4 verified (b,c,d,e), 2 active
  -- (c,d only — funnel's "active" is membership-based, independent of the
  -- super_admin flag), 1 newly-stale-unverified (f; a is recent).
  -- ---------------------------------------------------------------------
  v_funnel_after := public.admin_platform_user_funnel();

  IF (v_funnel_after ->> 'identities')::BIGINT - (v_funnel_before ->> 'identities')::BIGINT <> 6 THEN
    RAISE EXCEPTION 'expected identities delta 6, got %',
      (v_funnel_after ->> 'identities')::BIGINT - (v_funnel_before ->> 'identities')::BIGINT;
  END IF;
  IF (v_funnel_after ->> 'verified')::BIGINT - (v_funnel_before ->> 'verified')::BIGINT <> 4 THEN
    RAISE EXCEPTION 'expected verified delta 4, got %',
      (v_funnel_after ->> 'verified')::BIGINT - (v_funnel_before ->> 'verified')::BIGINT;
  END IF;
  IF (v_funnel_after ->> 'active')::BIGINT - (v_funnel_before ->> 'active')::BIGINT <> 2 THEN
    RAISE EXCEPTION 'expected active delta 2, got %',
      (v_funnel_after ->> 'active')::BIGINT - (v_funnel_before ->> 'active')::BIGINT;
  END IF;
  IF (v_funnel_after ->> 'unverified_over_30d')::BIGINT - (v_funnel_before ->> 'unverified_over_30d')::BIGINT <> 1 THEN
    RAISE EXCEPTION 'expected unverified_over_30d delta 1, got %',
      (v_funnel_after ->> 'unverified_over_30d')::BIGINT - (v_funnel_before ->> 'unverified_over_30d')::BIGINT;
  END IF;
  INSERT INTO lc_assertions VALUES ('funnel_deltas', true);

  -- ---------------------------------------------------------------------
  -- neither RPC mutates auth.users — snapshot one fixture's Auth fields
  -- before/after every call above.
  -- ---------------------------------------------------------------------
  SELECT phone_confirmed_at, last_sign_in_at INTO v_after_confirmed, v_after_signin
  FROM auth.users WHERE id = v_active_company;
  IF v_after_confirmed IS DISTINCT FROM v_before_confirmed OR v_after_signin IS DISTINCT FROM v_before_signin THEN
    RAISE EXCEPTION 'auth.users fields changed after calling the admin RPCs: phone_confirmed_at % -> %, last_sign_in_at % -> %',
      v_before_confirmed, v_after_confirmed, v_before_signin, v_after_signin;
  END IF;
  INSERT INTO lc_assertions VALUES ('no_auth_mutation', true);

  -- ---------------------------------------------------------------------
  -- security: a real but non-admin authenticated tenant user is forbidden.
  -- ---------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_verified_incomplete::text, true);

  v_forbidden := false;
  BEGIN
    PERFORM public.admin_list_platform_users(NULL, NULL, 10, 0);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%forbidden%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected admin_list_platform_users to reject a non-admin tenant user';
  END IF;
  INSERT INTO lc_assertions VALUES ('tenant_forbidden_list', true);

  v_forbidden := false;
  BEGIN
    PERFORM public.admin_platform_user_funnel();
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%forbidden%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected admin_platform_user_funnel to reject a non-admin tenant user';
  END IF;
  INSERT INTO lc_assertions VALUES ('tenant_forbidden_funnel', true);

  -- ---------------------------------------------------------------------
  -- security: an unrecognized identity (no profile row at all — the
  -- closest local equivalent to an anon/unauthenticated caller) is
  -- forbidden, not merely un-elevated.
  -- ---------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);

  v_forbidden := false;
  BEGIN
    PERFORM public.admin_list_platform_users(NULL, NULL, 10, 0);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%forbidden%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected admin_list_platform_users to reject an unrecognized identity';
  END IF;
  INSERT INTO lc_assertions VALUES ('anon_forbidden_list', true);

  v_forbidden := false;
  BEGIN
    PERFORM public.admin_platform_user_funnel();
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%forbidden%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected admin_platform_user_funnel to reject an unrecognized identity';
  END IF;
  INSERT INTO lc_assertions VALUES ('anon_forbidden_funnel', true);

  PERFORM set_config('request.jwt.claim.sub', '', true);
END;
$$;

SELECT ok((SELECT ok FROM lc_assertions WHERE key = 'lifecycle_status'), 'lifecycle_status is derived correctly for unverified / verified_incomplete / active (company) / active (rider) / super_admin / stale-unverified');
SELECT ok((SELECT ok FROM lc_assertions WHERE key = 'status_filter_unverified'), 'p_status=''unverified'' returns exactly the never-verified fixtures');
SELECT ok((SELECT ok FROM lc_assertions WHERE key = 'status_filter_active'), 'p_status=''active'' returns exactly the membership/rider-linked fixtures');
SELECT ok((SELECT ok FROM lc_assertions WHERE key = 'invalid_status_rejected'), 'an invalid status filter raises instead of being silently ignored');
SELECT ok((SELECT ok FROM lc_assertions WHERE key = 'funnel_deltas'), 'admin_platform_user_funnel reports identities/verified/active/unverified_over_30d deltas correctly');
SELECT ok((SELECT ok FROM lc_assertions WHERE key = 'no_auth_mutation'), 'neither RPC mutates auth.users');
SELECT ok((SELECT ok FROM lc_assertions WHERE key = 'tenant_forbidden_list'), 'a non-admin authenticated tenant user is forbidden from admin_list_platform_users');
SELECT ok((SELECT ok FROM lc_assertions WHERE key = 'tenant_forbidden_funnel'), 'a non-admin authenticated tenant user is forbidden from admin_platform_user_funnel');
SELECT ok((SELECT ok FROM lc_assertions WHERE key = 'anon_forbidden_list'), 'an unrecognized/anon-like identity is forbidden from admin_list_platform_users');
SELECT ok((SELECT ok FROM lc_assertions WHERE key = 'anon_forbidden_funnel'), 'an unrecognized/anon-like identity is forbidden from admin_platform_user_funnel');

SELECT * FROM finish();
ROLLBACK;
