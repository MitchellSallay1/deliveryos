-- Foundation fix: self-service company/merchant registration must activate
-- immediately, not sit in 'pending' forever.
--
-- Root cause: companies.status defaults to 'pending' (initial_schema.sql)
-- and is never transitioned anywhere automatically. The only place that
-- ever UPDATEs companies.status at all is the super-admin
-- activate/suspend RPC (admin_set_company_status,
-- 20260308180000_super_admin_control_tower.sql). assert_company_operational
-- rejects any non-'active' company, so every self-served company — despite
-- getting a working 7-day trialing subscription from
-- ensure_initial_company_subscription — could never create a rider,
-- customer, or delivery until a super admin manually activated it.
--
-- This exact fix existed once: 20260308100000_ensure_company_subscription_onboarding.sql
-- inserted new companies with `status = 'active'`. The very next migration
-- that redefined create_company_with_owner
-- (20260308160000_phone_auth.sql, to add phone normalization / email
-- defaulting) rewrote the INSERT column list without carrying that column
-- forward, silently reverting to the implicit 'pending' default. This
-- migration restores it on top of the current (phone_auth.sql) body,
-- unchanged otherwise.
--
-- create_company_with_owner is the single source of truth for company
-- creation — both self-service entry points delegate to it and nothing
-- else in this schema inserts into public.companies:
--   finalize_phone_workspace      (phone OTP company/merchant registration)
--   complete_pending_onboarding   (legacy email-confirmation registration)
-- Fixing it here covers both, including merchant business_type, uniformly.
--
-- This is a CREATE OR REPLACE FUNCTION only — it changes behavior for
-- companies created AFTER this migration runs. It does not UPDATE any
-- existing row, so it cannot reactivate an existing pending or suspended
-- company; that stays exclusively under admin_set_company_status's control,
-- which this migration does not touch. RLS, RBAC, phone/OTP/SMS provider
-- logic, and MoMo are untouched.

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

  -- New self-service companies are operational immediately — the phone
  -- OTP session already establishes who the owner is, and RLS + the
  -- 7-day trial (ensure_initial_company_subscription, called below) are
  -- the real gates on what they can do. Only admin_set_company_status
  -- (super admin) can ever move a company OUT of 'active' afterward.
  INSERT INTO public.companies (name, slug, phone, email, address, subscription_id, business_type, status)
  VALUES (
    trim(p_name), v_slug, public.normalize_phone_lr(p_phone), v_email, p_address, v_sub_id, v_type,
    'active'::public.company_status
  )
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
