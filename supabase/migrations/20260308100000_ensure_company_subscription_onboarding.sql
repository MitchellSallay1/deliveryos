-- Ensure every company has an initial Starter subscription (onboarding + backfill)

CREATE OR REPLACE FUNCTION public.ensure_initial_company_subscription(p_company_id UUID)
RETURNS public.company_subscriptions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing public.company_subscriptions;
  v_row public.company_subscriptions;
  v_plan_id UUID;
  v_starts TIMESTAMPTZ := now();
  v_trial_end TIMESTAMPTZ;
BEGIN
  IF p_company_id IS NULL THEN
    RAISE EXCEPTION 'invalid company';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.companies c WHERE c.id = p_company_id) THEN
    RAISE EXCEPTION 'company_not_found';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('company_sub:' || p_company_id::text));

  v_existing := public.get_active_company_subscription(p_company_id);
  IF v_existing.id IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  SELECT COALESCE(
    (SELECT c.subscription_id FROM public.companies c WHERE c.id = p_company_id),
    (SELECT s.id FROM public.subscriptions s WHERE s.slug = 'starter' AND s.is_active = true LIMIT 1)
  ) INTO v_plan_id;

  IF v_plan_id IS NULL THEN
    SELECT id INTO v_plan_id FROM public.subscriptions WHERE slug = 'starter' LIMIT 1;
  END IF;

  IF v_plan_id IS NULL THEN
    RAISE EXCEPTION 'starter plan not configured';
  END IF;

  v_trial_end := v_starts + INTERVAL '14 days';

  INSERT INTO public.company_subscriptions (
    company_id,
    plan_id,
    status,
    starts_at,
    current_period_start,
    current_period_end,
    trial_ends_at
  ) VALUES (
    p_company_id,
    v_plan_id,
    'trialing'::public.company_subscription_status,
    v_starts,
    v_starts,
    v_trial_end,
    v_trial_end
  )
  RETURNING * INTO v_row;

  UPDATE public.companies
  SET subscription_id = v_plan_id, updated_at = now()
  WHERE id = p_company_id;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_initial_company_subscription(UUID) FROM PUBLIC;

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
    PERFORM public.ensure_initial_company_subscription(v_company_id);
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

  INSERT INTO public.companies (name, slug, phone, email, address, subscription_id, business_type, status)
  VALUES (
    trim(p_name),
    v_slug,
    trim(p_phone),
    lower(trim(p_email)),
    p_address,
    v_sub_id,
    v_type,
    'active'::public.company_status
  )
  RETURNING id INTO v_company_id;

  INSERT INTO public.company_users (company_id, user_id, role)
  VALUES (v_company_id, auth.uid(), 'company_owner');

  IF v_type IN ('logistics_provider', 'hybrid') THEN
    INSERT INTO public.provider_marketplace_profiles (company_id, marketplace_enabled, accepting_jobs)
    VALUES (v_company_id, false, false)
    ON CONFLICT (company_id) DO NOTHING;
  END IF;

  PERFORM public.ensure_initial_company_subscription(v_company_id);

  RETURN v_company_id;
END;
$$;

-- Backfill companies missing any subscription lifecycle row
DO $$
DECLARE
  v_company_id UUID;
BEGIN
  FOR v_company_id IN
    SELECT c.id
    FROM public.companies c
    WHERE NOT EXISTS (
      SELECT 1 FROM public.company_subscriptions cs WHERE cs.company_id = c.id
    )
  LOOP
    PERFORM public.ensure_initial_company_subscription(v_company_id);
  END LOOP;
END;
$$;
