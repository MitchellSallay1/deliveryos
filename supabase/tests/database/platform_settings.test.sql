-- Coverage for DeliveryOS platform_settings
-- (20260309230000_platform_settings_public_app_url.sql).
--
-- Proves: platform_settings is not directly readable/writable by any
-- client role (RLS, zero policies); only Super Admin can list/set
-- settings via the SECURITY DEFINER RPCs; an invalid key or a
-- public_app_url that doesn't start with https:// is rejected;
-- notify_customer_tracking includes a real tracking link once
-- public_app_url is configured, and omits the link entirely (never a
-- broken/placeholder URL) when it is unset or cleared.

BEGIN;
SELECT plan(10);

SELECT has_table('public'::name, 'platform_settings'::name);
SELECT has_function('public'::name, 'get_platform_setting'::name);
SELECT has_function('public'::name, 'admin_list_platform_settings'::name);
SELECT has_function('public'::name, 'admin_set_platform_setting'::name);

CREATE OR REPLACE FUNCTION pg_temp.make_customer(p_label TEXT)
RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
  v_user UUID := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, phone, email, encrypted_password, phone_confirmed_at, aud, role)
  VALUES (
    v_user, '+23179' || lpad((floor(random() * 999999))::text, 6, '0'),
    'platform-settings-' || substr(v_user::text, 1, 8) || '@test.local',
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
    p_label, '+23179' || lpad((floor(random() * 999999))::text, 6, '0'),
    lower(replace(p_label, ' ', '')) || '@test.local', NULL, p_business_type
  );
  PERFORM set_config('request.jwt.claim.sub', '', true);
  RETURN QUERY SELECT v_company, v_owner;
END;
$$;

DO $$
DECLARE
  v_admin UUID;
  v_carrier UUID; v_carrier_owner UUID;
  v_customer UUID;
  v_delivery public.deliveries;
  v_rider UUID;
  v_forbidden BOOLEAN;
  v_row public.platform_settings;
  v_setting_value TEXT;
  v_sms_body TEXT;
BEGIN
  v_admin := pg_temp.make_customer('PS Admin');
  UPDATE public.profiles SET is_super_admin = true WHERE id = v_admin;

  SELECT company_id, owner_id INTO v_carrier, v_carrier_owner FROM pg_temp.make_company('PS Carrier', 'logistics_provider');
  v_customer := pg_temp.make_customer('PS Customer');

  CREATE TEMP TABLE ps_assertions (key TEXT PRIMARY KEY, ok BOOLEAN);

  -- =========================================================================
  -- 1) platform_settings is not directly readable or writable by any
  --    client role — RLS enabled, zero policies.
  -- =========================================================================
  v_forbidden := false;
  DECLARE v_count INT;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    SELECT COUNT(*) INTO v_count FROM public.platform_settings;
    RESET ROLE;
    IF v_count <> 0 THEN v_forbidden := false; ELSE v_forbidden := true; END IF;
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    v_forbidden := true;
  END;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF NOT v_forbidden THEN
    RAISE EXCEPTION 'expected a raw authenticated SELECT of platform_settings to return 0 rows or be rejected (even as super admin — no SELECT policy exists at all)';
  END IF;

  v_forbidden := false;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    UPDATE public.platform_settings SET value = 'https://evil.example.com' WHERE key = 'public_app_url';
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    v_forbidden := true;
  END;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF (SELECT public.get_platform_setting('public_app_url')) IS NOT NULL THEN
    RAISE EXCEPTION 'expected a raw authenticated UPDATE of platform_settings to never actually take effect';
  END IF;

  INSERT INTO ps_assertions VALUES ('platform_settings_not_directly_client_accessible', true);

  -- =========================================================================
  -- 2) Only Super Admin can list/set platform settings.
  -- =========================================================================
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_carrier_owner::text, true);
    PERFORM public.admin_list_platform_settings();
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%forbidden%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN RAISE EXCEPTION 'expected a non-admin to be forbidden from admin_list_platform_settings'; END IF;

  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_carrier_owner::text, true);
    PERFORM public.admin_set_platform_setting('public_app_url', 'https://not-allowed.example.com');
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%forbidden%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN RAISE EXCEPTION 'expected a non-admin to be forbidden from admin_set_platform_setting'; END IF;

  INSERT INTO ps_assertions VALUES ('only_super_admin_can_manage_settings', true);

  -- =========================================================================
  -- 3) Invalid key and invalid public_app_url format are rejected.
  -- =========================================================================
  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    PERFORM public.admin_set_platform_setting('not_a_real_setting', 'anything');
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%invalid_setting_key%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN RAISE EXCEPTION 'expected an unknown setting key to be rejected'; END IF;

  v_forbidden := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    PERFORM public.admin_set_platform_setting('public_app_url', 'not-a-url');
    PERFORM set_config('request.jwt.claim.sub', '', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF SQLERRM NOT LIKE '%invalid_public_app_url%' THEN RAISE; END IF;
    v_forbidden := true;
  END;
  IF NOT v_forbidden THEN RAISE EXCEPTION 'expected a non-https public_app_url to be rejected'; END IF;

  INSERT INTO ps_assertions VALUES ('invalid_key_and_url_rejected', true);

  -- =========================================================================
  -- 4) Super Admin can set public_app_url; trailing slash is normalized;
  --    get_platform_setting (the internal read seam) returns it.
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  v_row := public.admin_set_platform_setting('public_app_url', 'https://app.example-test.com/');
  PERFORM set_config('request.jwt.claim.sub', '', true);

  IF v_row.value <> 'https://app.example-test.com' THEN
    RAISE EXCEPTION 'expected trailing slash to be stripped, got %', v_row.value;
  END IF;

  v_setting_value := public.get_platform_setting('public_app_url');
  IF v_setting_value <> 'https://app.example-test.com' THEN
    RAISE EXCEPTION 'expected get_platform_setting to return the configured value, got %', v_setting_value;
  END IF;

  INSERT INTO ps_assertions VALUES ('super_admin_can_set_and_read_setting', true);

  -- =========================================================================
  -- 5) notify_customer_tracking includes a real tracking link once
  --    public_app_url is configured (no domain hardcoded anywhere).
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_carrier_owner::text, true);
  v_delivery := public.create_delivery(
    v_carrier, 'PS Test Pickup', 'Monrovia', 'PS Regular Customer', '+231770001234', 'PS Regular Destination'
  );
  PERFORM set_config('request.jwt.claim.sub', '', true);

  INSERT INTO public.riders (company_id, rider_code, full_name, phone, status)
  VALUES (v_carrier, 'PS-' || substr(gen_random_uuid()::text, 1, 8), 'PS Rider', '+231884' || lpad((floor(random()*999999))::text,6,'0'), 'available')
  RETURNING id INTO v_rider;

  PERFORM set_config('request.jwt.claim.sub', v_carrier_owner::text, true);
  PERFORM public.assign_delivery_rider(v_delivery.id, v_rider);
  PERFORM public.transition_delivery_status(v_delivery.id, 'accepted', NULL);
  PERFORM public.transition_delivery_status(v_delivery.id, 'picked_up', NULL);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT body INTO v_sms_body FROM public.sms_outbox
  WHERE delivery_id = v_delivery.id AND phone = v_delivery.customer_phone
  ORDER BY created_at DESC LIMIT 1;

  IF v_sms_body IS NULL OR v_sms_body NOT LIKE '%Track: https://app.example-test.com/track/%' THEN
    RAISE EXCEPTION 'expected the tracking SMS to include the configured public_app_url, got %', v_sms_body;
  END IF;

  INSERT INTO ps_assertions VALUES ('tracking_sms_includes_configured_url', true);

  -- =========================================================================
  -- 6) Clearing public_app_url makes notify_customer_tracking omit the
  --    tracking line entirely — never a broken/placeholder link.
  -- =========================================================================
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  v_row := public.admin_set_platform_setting('public_app_url', '');
  PERFORM set_config('request.jwt.claim.sub', '', true);

  IF v_row.value IS NOT NULL THEN
    RAISE EXCEPTION 'expected an empty value to normalize to NULL, got %', v_row.value;
  END IF;
  IF public.get_platform_setting('public_app_url') IS NOT NULL THEN
    RAISE EXCEPTION 'expected get_platform_setting to return NULL once cleared';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_carrier_owner::text, true);
  PERFORM public.transition_delivery_status(v_delivery.id, 'in_transit', NULL);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  -- now() is frozen for this whole test's transaction, so both SMS rows
  -- share an identical created_at — filter by the status-specific body
  -- content (unique per transition) rather than relying on ordering.
  SELECT body INTO v_sms_body FROM public.sms_outbox
  WHERE delivery_id = v_delivery.id AND phone = v_delivery.customer_phone AND body LIKE '%in transit%';

  IF v_sms_body IS NULL OR v_sms_body LIKE '%Track:%' OR v_sms_body LIKE '%localhost%' THEN
    RAISE EXCEPTION 'expected the tracking SMS to omit any link (never a broken/localhost one) once public_app_url is unset, got %', v_sms_body;
  END IF;

  INSERT INTO ps_assertions VALUES ('unset_url_omits_tracking_link_never_broken', true);
END;
$$;

SELECT ok((SELECT ok FROM ps_assertions WHERE key = 'platform_settings_not_directly_client_accessible'), 'platform_settings has no SELECT/UPDATE policy for any client role, even Super Admin — access is RPC-only');
SELECT ok((SELECT ok FROM ps_assertions WHERE key = 'only_super_admin_can_manage_settings'), 'a non-admin is forbidden from admin_list_platform_settings and admin_set_platform_setting');
SELECT ok((SELECT ok FROM ps_assertions WHERE key = 'invalid_key_and_url_rejected'), 'an unknown setting key and a non-https public_app_url are both rejected');
SELECT ok((SELECT ok FROM ps_assertions WHERE key = 'super_admin_can_set_and_read_setting'), 'Super Admin can set public_app_url (trailing slash normalized) and get_platform_setting reads it back');
SELECT ok((SELECT ok FROM ps_assertions WHERE key = 'tracking_sms_includes_configured_url'), 'notify_customer_tracking includes a real tracking link built from the configured public_app_url');
SELECT ok((SELECT ok FROM ps_assertions WHERE key = 'unset_url_omits_tracking_link_never_broken'), 'clearing public_app_url makes notify_customer_tracking omit the tracking link entirely, never a broken or localhost link');

SELECT * FROM finish();
ROLLBACK;
