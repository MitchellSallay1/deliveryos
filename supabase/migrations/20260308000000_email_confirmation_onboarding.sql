-- Email-confirmation onboarding: idempotent company creation + pending metadata RPC

CREATE OR REPLACE FUNCTION public.create_company_with_owner(
  p_name TEXT,
  p_phone TEXT,
  p_email TEXT,
  p_address TEXT DEFAULT NULL,
  p_business_type public.company_business_type DEFAULT 'logistics_provider'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_sub_id UUID;
  v_slug TEXT;
  v_type public.company_business_type := COALESCE(p_business_type, 'logistics_provider');
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT cu.company_id INTO v_company_id
  FROM public.company_users cu
  WHERE cu.user_id = auth.uid()
    AND cu.is_active = true
  ORDER BY cu.created_at ASC
  LIMIT 1;

  IF v_company_id IS NOT NULL THEN
    RETURN v_company_id;
  END IF;

  IF p_name IS NULL OR length(trim(p_name)) < 2 THEN
    RAISE EXCEPTION 'invalid company name';
  END IF;

  IF p_phone IS NULL OR length(trim(p_phone)) < 7 THEN
    RAISE EXCEPTION 'invalid company phone';
  END IF;

  IF p_email IS NULL OR length(trim(p_email)) < 3 OR position('@' in trim(p_email)) = 0 THEN
    RAISE EXCEPTION 'invalid company email';
  END IF;

  v_slug := lower(regexp_replace(trim(p_name), '[^a-zA-Z0-9]+', '-', 'g'));
  v_slug := trim(both '-' from v_slug);
  IF v_slug = '' THEN
    RAISE EXCEPTION 'invalid company name';
  END IF;

  SELECT id INTO v_sub_id FROM public.subscriptions WHERE slug = 'starter' LIMIT 1;

  INSERT INTO public.companies (name, slug, phone, email, address, subscription_id, business_type)
  VALUES (trim(p_name), v_slug, trim(p_phone), lower(trim(p_email)), p_address, v_sub_id, v_type)
  RETURNING id INTO v_company_id;

  INSERT INTO public.company_users (company_id, user_id, role)
  VALUES (v_company_id, auth.uid(), 'company_owner');

  IF v_type IN ('logistics_provider', 'hybrid') THEN
    INSERT INTO public.provider_marketplace_profiles (company_id, marketplace_enabled, accepting_jobs)
    VALUES (v_company_id, false, false)
    ON CONFLICT (company_id) DO NOTHING;
  END IF;

  RETURN v_company_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_pending_onboarding()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_meta JSONB;
  v_name TEXT;
  v_phone TEXT;
  v_email TEXT;
  v_btype TEXT;
  v_company_id UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_uid::text));

  SELECT cu.company_id INTO v_company_id
  FROM public.company_users cu
  WHERE cu.user_id = v_uid
    AND cu.is_active = true
  ORDER BY cu.created_at ASC
  LIMIT 1;

  IF v_company_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'company_id', v_company_id,
      'created', false,
      'status', 'already_member'
    );
  END IF;

  SELECT u.raw_user_meta_data INTO v_meta
  FROM auth.users u
  WHERE u.id = v_uid;

  v_name := NULLIF(trim(v_meta ->> 'pending_company_name'), '');
  v_phone := NULLIF(trim(v_meta ->> 'pending_company_phone'), '');
  v_email := NULLIF(trim(v_meta ->> 'pending_company_email'), '');
  v_btype := COALESCE(NULLIF(trim(v_meta ->> 'pending_business_type'), ''), 'logistics_provider');

  IF v_name IS NULL OR v_phone IS NULL OR v_email IS NULL THEN
    RETURN jsonb_build_object(
      'company_id', NULL,
      'created', false,
      'status', 'pending_metadata_missing'
    );
  END IF;

  IF v_btype NOT IN ('logistics_provider', 'merchant', 'hybrid') THEN
    RAISE EXCEPTION 'invalid business type';
  END IF;

  v_company_id := public.create_company_with_owner(
    v_name,
    v_phone,
    v_email,
    NULL,
    v_btype::public.company_business_type
  );

  RETURN jsonb_build_object(
    'company_id', v_company_id,
    'created', true,
    'status', 'created'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.complete_pending_onboarding() TO authenticated;
