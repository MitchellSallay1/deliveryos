-- DeliveryOS · Phone-first auth (profiles, invites, workspace, rider link)

-- ---------------------------------------------------------------------------
-- Unified phone normalization (single canonical implementation)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.normalize_phone_lr(p TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_digits TEXT;
BEGIN
  v_digits := regexp_replace(COALESCE(p, ''), '[^0-9]', '', 'g');
  IF v_digits = '' THEN
    RETURN '';
  END IF;
  IF length(v_digits) = 9 THEN
    RETURN '+231' || v_digits;
  ELSIF length(v_digits) = 10 AND left(v_digits, 1) = '0' THEN
    RETURN '+231' || substr(v_digits, 2);
  ELSIF length(v_digits) >= 11 AND left(v_digits, 3) = '231' THEN
    RETURN '+' || v_digits;
  END IF;
  IF left(v_digits, 1) <> '+' THEN
    RETURN '+' || v_digits;
  END IF;
  RETURN v_digits;
END;
$$;

CREATE OR REPLACE FUNCTION public.normalize_phone(p TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT public.normalize_phone_lr(p);
$$;

-- ---------------------------------------------------------------------------
-- Profiles: primary phone identity
-- ---------------------------------------------------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS phone_normalized TEXT;

CREATE INDEX IF NOT EXISTS idx_profiles_phone_normalized
  ON public.profiles (phone_normalized)
  WHERE phone_normalized IS NOT NULL;

CREATE OR REPLACE FUNCTION public.sync_profile_from_auth_user()
RETURNS public.profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_auth_phone TEXT;
  v_meta JSONB;
  v_full TEXT;
  v_row public.profiles;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT phone, raw_user_meta_data INTO v_auth_phone, v_meta
  FROM auth.users WHERE id = v_uid;

  v_full := NULLIF(trim(v_meta ->> 'full_name'), '');

  INSERT INTO public.profiles (id, full_name, phone, phone_normalized)
  VALUES (
    v_uid,
    v_full,
    public.normalize_phone_lr(v_auth_phone),
    public.normalize_phone_lr(v_auth_phone)
  )
  ON CONFLICT (id) DO UPDATE SET
    full_name = COALESCE(EXCLUDED.full_name, profiles.full_name),
    phone = COALESCE(NULLIF(EXCLUDED.phone, ''), profiles.phone),
    phone_normalized = COALESCE(NULLIF(EXCLUDED.phone_normalized, ''), profiles.phone_normalized),
    updated_at = now()
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.sync_profile_from_auth_user TO authenticated;

-- ---------------------------------------------------------------------------
-- Company creation: company email optional (contact); auth is phone-based
-- ---------------------------------------------------------------------------
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
  v_email TEXT;
  v_auth_phone TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT cu.company_id INTO v_company_id
  FROM public.company_users cu
  WHERE cu.user_id = auth.uid() AND cu.is_active = true
  ORDER BY cu.created_at ASC LIMIT 1;

  IF v_company_id IS NOT NULL THEN
    RETURN v_company_id;
  END IF;

  IF p_name IS NULL OR length(trim(p_name)) < 2 THEN
    RAISE EXCEPTION 'invalid company name';
  END IF;

  SELECT phone INTO v_auth_phone FROM auth.users WHERE id = auth.uid();
  IF p_phone IS NULL OR length(trim(p_phone)) < 7 THEN
    p_phone := COALESCE(public.normalize_phone_lr(v_auth_phone), '+2310000000');
  END IF;

  v_email := NULLIF(lower(trim(COALESCE(p_email, ''))), '');
  IF v_email IS NULL OR position('@' in v_email) = 0 THEN
    v_email := replace(public.normalize_phone_lr(p_phone), '+', '') || '@contact.deliveryos.local';
  END IF;

  v_slug := lower(regexp_replace(trim(p_name), '[^a-zA-Z0-9]+', '-', 'g'));
  v_slug := trim(both '-' from v_slug);
  IF v_slug = '' THEN
    RAISE EXCEPTION 'invalid company name';
  END IF;

  SELECT id INTO v_sub_id FROM public.subscriptions WHERE slug = 'starter' LIMIT 1;

  INSERT INTO public.companies (name, slug, phone, email, address, subscription_id, business_type)
  VALUES (trim(p_name), v_slug, public.normalize_phone_lr(p_phone), v_email, p_address, v_sub_id, v_type)
  RETURNING id INTO v_company_id;

  INSERT INTO public.company_users (company_id, user_id, role)
  VALUES (v_company_id, auth.uid(), 'company_owner');

  PERFORM public.ensure_initial_company_subscription(v_company_id);

  IF v_type IN ('logistics_provider', 'hybrid') THEN
    INSERT INTO public.provider_marketplace_profiles (company_id, marketplace_enabled, accepting_jobs)
    VALUES (v_company_id, false, false)
    ON CONFLICT (company_id) DO NOTHING;
  END IF;

  PERFORM public.sync_profile_from_auth_user();

  RETURN v_company_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.finalize_phone_workspace(
  p_full_name TEXT,
  p_company_name TEXT,
  p_business_type public.company_business_type,
  p_company_phone TEXT DEFAULT NULL,
  p_company_email TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_persona TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  IF p_full_name IS NOT NULL AND length(trim(p_full_name)) >= 2 THEN
    UPDATE public.profiles SET full_name = trim(p_full_name), updated_at = now()
    WHERE id = auth.uid();
  END IF;

  v_persona := CASE p_business_type
    WHEN 'merchant' THEN 'merchant'
    ELSE 'company_owner'
  END;

  v_company_id := public.create_company_with_owner(
    p_company_name,
    COALESCE(p_company_phone, public.normalize_phone_lr((SELECT phone FROM auth.users WHERE id = auth.uid()))),
    p_company_email,
    NULL,
    p_business_type
  );

  RETURN jsonb_build_object(
    'company_id', v_company_id,
    'persona', v_persona,
    'status', 'created'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.finalize_phone_workspace TO authenticated;

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
  v_persona TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_uid::text));

  SELECT cu.company_id INTO v_company_id
  FROM public.company_users cu
  WHERE cu.user_id = v_uid AND cu.is_active = true
  ORDER BY cu.created_at ASC LIMIT 1;

  IF v_company_id IS NOT NULL THEN
    RETURN jsonb_build_object('company_id', v_company_id, 'created', false, 'status', 'already_member');
  END IF;

  SELECT u.raw_user_meta_data INTO v_meta FROM auth.users u WHERE u.id = v_uid;
  v_persona := lower(COALESCE(v_meta ->> 'persona', ''));

  IF v_persona = 'rider' THEN
    RETURN jsonb_build_object('company_id', NULL, 'created', false, 'status', 'pending_metadata_missing');
  END IF;

  v_name := NULLIF(trim(v_meta ->> 'pending_company_name'), '');
  v_phone := NULLIF(trim(v_meta ->> 'pending_company_phone'), '');
  v_email := NULLIF(trim(v_meta ->> 'pending_company_email'), '');
  v_btype := COALESCE(NULLIF(trim(v_meta ->> 'pending_business_type'), ''), 'logistics_provider');

  IF v_name IS NULL OR v_phone IS NULL THEN
    RETURN jsonb_build_object('company_id', NULL, 'created', false, 'status', 'pending_metadata_missing');
  END IF;

  IF v_btype NOT IN ('logistics_provider', 'merchant', 'hybrid') THEN
    RAISE EXCEPTION 'invalid business type';
  END IF;

  v_company_id := public.create_company_with_owner(
    v_name, v_phone, v_email, NULL, v_btype::public.company_business_type
  );

  RETURN jsonb_build_object('company_id', v_company_id, 'created', true, 'status', 'created');
END;
$$;

-- ---------------------------------------------------------------------------
-- Team invitations: phone-first (email optional legacy)
-- ---------------------------------------------------------------------------
ALTER TABLE public.company_invitations
  ADD COLUMN IF NOT EXISTS invite_phone TEXT,
  ADD COLUMN IF NOT EXISTS phone_normalized TEXT;

ALTER TABLE public.company_invitations
  ALTER COLUMN email DROP NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_company_invitations_pending_phone
  ON public.company_invitations (company_id, phone_normalized)
  WHERE accepted_at IS NULL AND revoked_at IS NULL AND phone_normalized IS NOT NULL;

DROP FUNCTION IF EXISTS public.create_company_invitation(UUID, TEXT, public.company_role);

CREATE OR REPLACE FUNCTION public.create_company_invitation(
  p_company_id UUID,
  p_role public.company_role,
  p_email TEXT DEFAULT NULL,
  p_phone TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_token TEXT;
  v_row public.company_invitations;
  v_phone_norm TEXT;
  v_email TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  PERFORM public.assert_company_operational(p_company_id);

  IF NOT public.has_company_role(p_company_id, ARRAY['company_owner']::public.company_role[])
    AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF p_role = 'company_owner' AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'cannot_invite_owner';
  END IF;

  v_phone_norm := public.normalize_phone_lr(p_phone);
  v_email := NULLIF(lower(trim(COALESCE(p_email, ''))), '');

  IF (v_phone_norm IS NULL OR v_phone_norm = '') AND v_email IS NULL THEN
    RAISE EXCEPTION 'phone or email required';
  END IF;

  v_token := public.random_token_hex(24);

  INSERT INTO public.company_invitations (
    company_id, email, invite_phone, phone_normalized, role, token, invited_by, expires_at
  ) VALUES (
    p_company_id,
    v_email,
    v_phone_norm,
    v_phone_norm,
    p_role,
    v_token,
    auth.uid(),
    now() + interval '7 days'
  )
  RETURNING * INTO v_row;

  PERFORM public.log_audit_event(
    p_company_id, 'invitation_created', 'company_invitations', v_row.id, to_jsonb(v_row)
  );

  RETURN jsonb_build_object(
    'id', v_row.id,
    'token', v_row.token,
    'email', v_row.email,
    'invite_phone', v_row.invite_phone,
    'role', v_row.role,
    'expires_at', v_row.expires_at
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_company_invitation(UUID, public.company_role, TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.accept_company_invitation(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inv public.company_invitations;
  v_auth_phone TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT phone INTO v_auth_phone FROM auth.users WHERE id = auth.uid();
  v_auth_phone := public.normalize_phone_lr(v_auth_phone);

  SELECT * INTO v_inv
  FROM public.company_invitations
  WHERE token = p_token
    AND revoked_at IS NULL
    AND accepted_at IS NULL
    AND expires_at > now()
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invitation_invalid';
  END IF;

  IF v_inv.phone_normalized IS NOT NULL AND v_inv.phone_normalized <> '' THEN
    IF NOT public.phone_matches_msisdn(v_auth_phone, v_inv.phone_normalized) THEN
      RAISE EXCEPTION 'invitation_phone_mismatch';
    END IF;
  ELSIF v_inv.email IS NOT NULL THEN
    IF lower((SELECT email FROM auth.users WHERE id = auth.uid())) <> lower(v_inv.email) THEN
      RAISE EXCEPTION 'invitation_email_mismatch';
    END IF;
  ELSE
    RAISE EXCEPTION 'invitation_invalid';
  END IF;

  PERFORM public.assert_company_operational(v_inv.company_id);

  INSERT INTO public.company_users (company_id, user_id, role, is_active)
  VALUES (v_inv.company_id, auth.uid(), v_inv.role, true)
  ON CONFLICT (company_id, user_id) DO UPDATE SET
    role = EXCLUDED.role,
    is_active = true;

  UPDATE public.company_invitations SET accepted_at = now() WHERE id = v_inv.id;

  PERFORM public.sync_profile_from_auth_user();

  RETURN jsonb_build_object('company_id', v_inv.company_id, 'role', v_inv.role);
END;
$$;

-- ---------------------------------------------------------------------------
-- Rider link: verified auth phone must match rider MSISDN (invite + phone)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.link_rider_account(
  p_rider_code TEXT DEFAULT NULL,
  p_invite_code TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_profile public.profiles;
  v_auth_phone TEXT;
  v_row public.riders;
  v_company public.companies;
  v_existing public.riders;
  v_code TEXT;
  v_invite TEXT;
  v_verified_phone TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT phone INTO v_auth_phone FROM auth.users WHERE id = v_uid;
  v_verified_phone := public.normalize_phone_lr(v_auth_phone);

  IF v_verified_phone IS NULL OR v_verified_phone = '' THEN
    RAISE EXCEPTION 'verified phone required';
  END IF;

  PERFORM public.sync_profile_from_auth_user();
  SELECT * INTO v_profile FROM public.profiles WHERE id = v_uid;

  v_code := NULLIF(upper(trim(COALESCE(p_rider_code, ''))), '');
  v_invite := NULLIF(upper(trim(COALESCE(p_invite_code, ''))), '');

  IF v_code IS NULL AND v_invite IS NULL THEN
    RAISE EXCEPTION 'rider id or invite code required';
  END IF;

  SELECT * INTO v_existing FROM public.riders WHERE user_id = v_uid LIMIT 1;

  IF v_invite IS NOT NULL THEN
    SELECT * INTO v_row FROM public.riders WHERE upper(invite_code) = v_invite FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'rider not found';
    END IF;
  ELSE
    SELECT * INTO v_row FROM public.riders r
    WHERE upper(r.rider_code) = v_code
      AND public.phone_matches_msisdn(r.phone, v_verified_phone)
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'rider not found for this phone and id';
    END IF;
  END IF;

  IF NOT public.phone_matches_msisdn(v_verified_phone, v_row.phone) THEN
    RAISE EXCEPTION 'verified phone must match rider phone';
  END IF;

  IF v_existing.id IS NOT NULL AND v_existing.id IS DISTINCT FROM v_row.id THEN
    RAISE EXCEPTION 'account already linked to another rider';
  END IF;

  IF v_row.user_id IS NOT NULL AND v_row.user_id <> v_uid THEN
    RAISE EXCEPTION 'rider already linked to another account';
  END IF;

  IF v_row.user_id = v_uid THEN
    SELECT * INTO v_company FROM public.companies WHERE id = v_row.company_id;
    RETURN jsonb_build_object(
      'rider_id', v_row.id, 'rider_code', v_row.rider_code, 'invite_code', v_row.invite_code,
      'company_id', v_row.company_id, 'company_name', v_company.name,
      'linked', true, 'idempotent', true
    );
  END IF;

  IF v_row.status = 'suspended' THEN
    RAISE EXCEPTION 'rider is suspended';
  END IF;

  IF v_row.access_mode = 'button_phone' THEN
    RAISE EXCEPTION 'button-phone riders do not use app login';
  END IF;

  SELECT * INTO v_company FROM public.companies WHERE id = v_row.company_id;
  IF v_company.status <> 'active' THEN
    RAISE EXCEPTION 'company is not active';
  END IF;

  UPDATE public.riders SET user_id = v_uid WHERE id = v_row.id RETURNING * INTO v_row;

  INSERT INTO public.company_users (company_id, user_id, role, is_active)
  VALUES (v_row.company_id, v_uid, 'rider', true)
  ON CONFLICT (company_id, user_id) DO UPDATE SET role = 'rider', is_active = true;

  RETURN jsonb_build_object(
    'rider_id', v_row.id, 'rider_code', v_row.rider_code, 'invite_code', v_row.invite_code,
    'company_id', v_row.company_id, 'company_name', v_company.name, 'linked', true
  );
END;
$$;

-- Invitation list/preview includes phone fields
CREATE OR REPLACE FUNCTION public.list_company_invitations(p_company_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT (
    public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY['company_owner']::public.company_role[])
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  RETURN (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', i.id,
      'email', i.email,
      'invite_phone', i.invite_phone,
      'role', i.role,
      'token', i.token,
      'expires_at', i.expires_at,
      'created_at', i.created_at,
      'revoked_at', i.revoked_at,
      'accepted_at', i.accepted_at
    ) ORDER BY i.created_at DESC), '[]'::JSONB)
    FROM public.company_invitations i
    WHERE i.company_id = p_company_id
      AND i.accepted_at IS NULL
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_invitation_by_token(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inv public.company_invitations;
  v_company_name TEXT;
BEGIN
  SELECT * INTO v_inv
  FROM public.company_invitations
  WHERE token = p_token
    AND revoked_at IS NULL
    AND accepted_at IS NULL
    AND expires_at > now();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invitation_invalid';
  END IF;

  SELECT name INTO v_company_name FROM public.companies WHERE id = v_inv.company_id;

  RETURN jsonb_build_object(
    'email', v_inv.email,
    'invite_phone', v_inv.invite_phone,
    'role', v_inv.role,
    'company_name', v_company_name,
    'expires_at', v_inv.expires_at
  );
END;
$$;
