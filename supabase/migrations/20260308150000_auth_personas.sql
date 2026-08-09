-- DeliveryOS · Multi-persona auth: rider invite codes + link_rider_account

ALTER TABLE public.riders
  ADD COLUMN IF NOT EXISTS invite_code TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_riders_invite_code_unique
  ON public.riders (upper(invite_code))
  WHERE invite_code IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Invite codes (RDR-XXXX)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.generate_rider_invite_code()
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code TEXT;
  v_try INT := 0;
BEGIN
  LOOP
    v_try := v_try + 1;
    IF v_try > 50 THEN
      RAISE EXCEPTION 'could not generate invite code';
    END IF;
    v_code := 'RDR-' || upper(public.random_token_hex(2));
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM public.riders r WHERE upper(r.invite_code) = v_code
    );
  END LOOP;
  RETURN v_code;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_riders_assign_invite_code()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.invite_code IS NULL OR NEW.invite_code = '' THEN
    NEW.invite_code := public.generate_rider_invite_code();
  END IF;
  NEW.invite_code := upper(trim(NEW.invite_code));
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS riders_assign_invite_code ON public.riders;
CREATE TRIGGER riders_assign_invite_code
  BEFORE INSERT ON public.riders
  FOR EACH ROW EXECUTE FUNCTION public.trg_riders_assign_invite_code();

UPDATE public.riders
SET invite_code = public.generate_rider_invite_code()
WHERE invite_code IS NULL OR invite_code = '';

-- ---------------------------------------------------------------------------
-- Skip company auto-provision for rider persona accounts
-- ---------------------------------------------------------------------------
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

  v_persona := lower(COALESCE(v_meta ->> 'persona', ''));

  IF v_persona = 'rider' THEN
    RETURN jsonb_build_object(
      'company_id', NULL,
      'created', false,
      'status', 'pending_metadata_missing'
    );
  END IF;

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

-- ---------------------------------------------------------------------------
-- link_rider_account (smartphone / both riders only)
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
  v_row public.riders;
  v_company public.companies;
  v_existing public.riders;
  v_code TEXT;
  v_invite TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  v_code := NULLIF(upper(trim(COALESCE(p_rider_code, ''))), '');
  v_invite := NULLIF(upper(trim(COALESCE(p_invite_code, ''))), '');

  IF v_code IS NULL AND v_invite IS NULL THEN
    RAISE EXCEPTION 'rider id or invite code required';
  END IF;

  SELECT * INTO v_profile FROM public.profiles WHERE id = v_uid;

  SELECT * INTO v_existing
  FROM public.riders
  WHERE user_id = v_uid
  LIMIT 1;

  IF v_invite IS NOT NULL THEN
    SELECT * INTO v_row
    FROM public.riders
    WHERE upper(invite_code) = v_invite
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'rider not found';
    END IF;
  ELSE
    IF v_profile.phone IS NULL OR trim(v_profile.phone) = '' THEN
      RAISE EXCEPTION 'add your phone to your profile or use an invite code';
    END IF;

    SELECT * INTO v_row
    FROM public.riders r
    WHERE upper(r.rider_code) = v_code
      AND public.phone_matches_msisdn(r.phone, v_profile.phone)
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'rider not found for this phone and id';
    END IF;
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
      'rider_id', v_row.id,
      'rider_code', v_row.rider_code,
      'invite_code', v_row.invite_code,
      'company_id', v_row.company_id,
      'company_name', v_company.name,
      'linked', true,
      'idempotent', true
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

  IF v_profile.phone IS NOT NULL
     AND trim(v_profile.phone) <> ''
     AND NOT public.phone_matches_msisdn(v_profile.phone, v_row.phone) THEN
    RAISE EXCEPTION 'profile phone must match rider phone';
  END IF;

  UPDATE public.riders
  SET user_id = v_uid
  WHERE id = v_row.id
  RETURNING * INTO v_row;

  INSERT INTO public.company_users (company_id, user_id, role, is_active)
  VALUES (v_row.company_id, v_uid, 'rider', true)
  ON CONFLICT (company_id, user_id) DO UPDATE SET
    role = 'rider',
    is_active = true;

  RETURN jsonb_build_object(
    'rider_id', v_row.id,
    'rider_code', v_row.rider_code,
    'invite_code', v_row.invite_code,
    'company_id', v_row.company_id,
    'company_name', v_company.name,
    'linked', true,
    'idempotent', v_existing.id = v_row.id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.link_rider_account(TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.regenerate_rider_invite_code(p_rider_id UUID)
RETURNS public.riders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.riders;
BEGIN
  SELECT * INTO v_row FROM public.riders WHERE id = p_rider_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'rider not found';
  END IF;

  IF NOT (
    public.is_super_admin()
    OR public.has_company_role(
      v_row.company_id,
      ARRAY['company_owner', 'dispatcher']::public.company_role[]
    )
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE public.riders
  SET invite_code = public.generate_rider_invite_code()
  WHERE id = p_rider_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.regenerate_rider_invite_code TO authenticated;

CREATE OR REPLACE FUNCTION public.get_rider_invite_preview(p_invite_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.riders;
  v_company public.companies;
  v_code TEXT := upper(trim(COALESCE(p_invite_code, '')));
BEGIN
  IF v_code = '' THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_row FROM public.riders WHERE upper(invite_code) = v_code;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_company FROM public.companies WHERE id = v_row.company_id;

  RETURN jsonb_build_object(
    'invite_code', v_row.invite_code,
    'rider_code', v_row.rider_code,
    'company_name', v_company.name,
    'access_mode', v_row.access_mode
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_rider_invite_preview TO anon, authenticated;
