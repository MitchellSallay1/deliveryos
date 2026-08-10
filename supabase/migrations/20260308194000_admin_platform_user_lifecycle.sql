-- Phone auth lifecycle audit follow-up: signInWithOtp's default
-- shouldCreateUser=true (unchanged, correct Supabase Auth behavior) creates
-- an auth.users row at OTP-request time, before verification, and
-- handle_new_user() mirrors every such insert into public.profiles
-- unconditionally. Super Admin's "Platform users" page and any future
-- "total users" metric must therefore never treat a public.profiles row by
-- itself as a registered DeliveryOS user. This migration adds two
-- SECURITY DEFINER, super-admin-only RPCs that derive the real lifecycle
-- state server-side (joining auth.users' verification/sign-in fields and
-- company/rider membership) so the definition lives in one canonical place
-- instead of being re-guessed in the frontend.
--
-- Lifecycle states (mutually exclusive, evaluated in this order):
--   super_admin         — profiles.is_super_admin = true
--   unverified           — auth.users.phone_confirmed_at IS NULL
--                           (OTP requested, never verified)
--   active                — phone verified AND has an active company_users
--                           membership OR a linked rider account
--   verified_incomplete   — phone verified, no workspace/rider link yet
--                           (abandoned between OTP verification and
--                           finishing onboarding)
--
-- Neither RPC touches auth.users — read-only, STABLE, no mutation of Auth
-- state. Only id, full_name, phone, created_at, phone_confirmed_at,
-- last_sign_in_at, and the single 'persona' metadata key are read from
-- auth.users — no password/token/OTP fields, no raw_user_meta_data blob.

CREATE OR REPLACE FUNCTION public.admin_list_platform_users(
  p_search TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_limit INT DEFAULT 25,
  p_offset INT DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_q TEXT := NULLIF(trim(p_search), '');
  v_status TEXT := NULLIF(trim(lower(COALESCE(p_status, ''))), '');
  v_limit INT := LEAST(GREATEST(COALESCE(p_limit, 25), 1), 100);
  v_offset INT := GREATEST(COALESCE(p_offset, 0), 0);
  v_total INT;
  v_rows JSONB;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF v_status IS NOT NULL AND v_status NOT IN ('unverified', 'verified_incomplete', 'active', 'super_admin') THEN
    RAISE EXCEPTION 'invalid status filter';
  END IF;

  SELECT COUNT(*)::INT INTO v_total
  FROM (
    SELECT
      p.full_name,
      COALESCE(p.phone, u.phone) AS phone,
      CASE
        WHEN p.is_super_admin THEN 'super_admin'
        WHEN u.phone_confirmed_at IS NULL THEN 'unverified'
        WHEN EXISTS (SELECT 1 FROM public.company_users cu WHERE cu.user_id = p.id AND cu.is_active)
          OR EXISTS (SELECT 1 FROM public.riders r WHERE r.user_id = p.id) THEN 'active'
        ELSE 'verified_incomplete'
      END AS lifecycle_status
    FROM public.profiles p
    JOIN auth.users u ON u.id = p.id
  ) base
  WHERE (v_q IS NULL OR base.full_name ILIKE '%' || v_q || '%' OR base.phone ILIKE '%' || v_q || '%')
    AND (v_status IS NULL OR base.lifecycle_status = v_status);

  SELECT COALESCE(jsonb_agg(to_jsonb(paged)), '[]'::JSONB) INTO v_rows
  FROM (
    SELECT
      base.id,
      base.full_name,
      base.phone,
      base.created_at,
      base.phone_confirmed_at,
      base.last_sign_in_at,
      base.persona,
      base.is_super_admin,
      base.has_company_membership,
      base.is_rider_linked,
      base.lifecycle_status
    FROM (
      SELECT
        p.id,
        p.full_name,
        COALESCE(p.phone, u.phone) AS phone,
        u.created_at,
        u.phone_confirmed_at,
        u.last_sign_in_at,
        NULLIF(u.raw_user_meta_data ->> 'persona', '') AS persona,
        p.is_super_admin,
        EXISTS (SELECT 1 FROM public.company_users cu WHERE cu.user_id = p.id AND cu.is_active) AS has_company_membership,
        EXISTS (SELECT 1 FROM public.riders r WHERE r.user_id = p.id) AS is_rider_linked,
        CASE
          WHEN p.is_super_admin THEN 'super_admin'
          WHEN u.phone_confirmed_at IS NULL THEN 'unverified'
          WHEN EXISTS (SELECT 1 FROM public.company_users cu WHERE cu.user_id = p.id AND cu.is_active)
            OR EXISTS (SELECT 1 FROM public.riders r WHERE r.user_id = p.id) THEN 'active'
          ELSE 'verified_incomplete'
        END AS lifecycle_status
      FROM public.profiles p
      JOIN auth.users u ON u.id = p.id
    ) base
    WHERE (v_q IS NULL OR base.full_name ILIKE '%' || v_q || '%' OR base.phone ILIKE '%' || v_q || '%')
      AND (v_status IS NULL OR base.lifecycle_status = v_status)
    ORDER BY base.created_at DESC
    LIMIT v_limit OFFSET v_offset
  ) paged;

  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_list_platform_users(TEXT, TEXT, INT, INT) TO authenticated;

-- ---------------------------------------------------------------------------
-- Authentication funnel: identities -> verified -> active, plus a visible
-- (not deleted, not acted on) count of stale unverified ghosts so the scale
-- of abandonment can be measured before any retention policy is decided.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_platform_user_funnel()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_identities BIGINT;
  v_verified BIGINT;
  v_active BIGINT;
  v_unverified_over_30d BIGINT;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT
    COUNT(*),
    COUNT(*) FILTER (WHERE u.phone_confirmed_at IS NOT NULL),
    COUNT(*) FILTER (
      WHERE u.phone_confirmed_at IS NOT NULL
        AND (
          EXISTS (SELECT 1 FROM public.company_users cu WHERE cu.user_id = p.id AND cu.is_active)
          OR EXISTS (SELECT 1 FROM public.riders r WHERE r.user_id = p.id)
        )
    ),
    COUNT(*) FILTER (WHERE u.phone_confirmed_at IS NULL AND u.created_at < now() - INTERVAL '30 days')
  INTO v_identities, v_verified, v_active, v_unverified_over_30d
  FROM public.profiles p
  JOIN auth.users u ON u.id = p.id;

  RETURN jsonb_build_object(
    'identities', v_identities,
    'verified', v_verified,
    'active', v_active,
    'unverified_over_30d', v_unverified_over_30d
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_platform_user_funnel() TO authenticated;
