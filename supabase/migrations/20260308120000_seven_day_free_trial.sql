-- 7-day free trial lifecycle for new companies

CREATE OR REPLACE FUNCTION public.expire_elapsed_company_trials(p_company_id UUID DEFAULT NULL)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  UPDATE public.company_subscriptions cs
  SET
    status = 'expired'::public.company_subscription_status,
    updated_at = now()
  WHERE cs.status = 'trialing'::public.company_subscription_status
    AND cs.trial_ends_at IS NOT NULL
    AND cs.trial_ends_at <= now()
    AND (p_company_id IS NULL OR cs.company_id = p_company_id);

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.expire_elapsed_company_trials(UUID) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.get_active_company_subscription(p_company_id UUID)
RETURNS public.company_subscriptions
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.company_subscriptions;
BEGIN
  PERFORM public.expire_elapsed_company_trials(p_company_id);

  SELECT cs.* INTO v_row
  FROM public.company_subscriptions cs
  WHERE cs.company_id = p_company_id
    AND cs.status IN ('trialing', 'active', 'past_due')
  ORDER BY cs.created_at DESC
  LIMIT 1;

  RETURN v_row;
END;
$$;

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

  PERFORM public.expire_elapsed_company_trials(p_company_id);

  v_existing := public.get_active_company_subscription(p_company_id);
  IF v_existing.id IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.company_subscriptions cs WHERE cs.company_id = p_company_id
  ) THEN
    SELECT cs.* INTO v_row
    FROM public.company_subscriptions cs
    WHERE cs.company_id = p_company_id
    ORDER BY cs.created_at DESC
    LIMIT 1;
    RETURN v_row;
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

  v_trial_end := v_starts + INTERVAL '7 days';

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

CREATE OR REPLACE FUNCTION public.assert_subscription_operational(p_company_id UUID)
RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cs public.company_subscriptions;
BEGIN
  PERFORM public.expire_elapsed_company_trials(p_company_id);

  v_cs := public.get_active_company_subscription(p_company_id);
  IF v_cs.id IS NULL THEN
    IF EXISTS (
      SELECT 1
      FROM public.company_subscriptions cs
      WHERE cs.company_id = p_company_id
        AND cs.status = 'expired'::public.company_subscription_status
    ) THEN
      RAISE EXCEPTION 'trial_expired';
    END IF;
    RAISE EXCEPTION 'subscription_inactive';
  END IF;

  IF v_cs.status IN ('cancelled', 'expired', 'suspended') THEN
    IF v_cs.status = 'expired'::public.company_subscription_status THEN
      RAISE EXCEPTION 'trial_expired';
    END IF;
    RAISE EXCEPTION 'subscription_inactive';
  END IF;

  IF v_cs.status = 'past_due' THEN
    RAISE EXCEPTION 'subscription_past_due';
  END IF;

  IF v_cs.status = 'trialing'::public.company_subscription_status
     AND v_cs.trial_ends_at IS NOT NULL
     AND v_cs.trial_ends_at <= now() THEN
    UPDATE public.company_subscriptions
    SET status = 'expired'::public.company_subscription_status, updated_at = now()
    WHERE id = v_cs.id;
    RAISE EXCEPTION 'trial_expired';
  END IF;

  IF v_cs.current_period_end < now() AND v_cs.status NOT IN ('trialing') THEN
    RAISE EXCEPTION 'subscription_expired';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_company_usage(p_company_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cs public.company_subscriptions;
  v_latest public.company_subscriptions;
  v_plan public.subscriptions;
  v_riders INT;
  v_deliveries INT;
  v_completed INT;
  v_sms INT;
  v_photos BIGINT;
  v_trial JSONB;
  v_days_remaining INT;
BEGIN
  IF NOT (
    public.is_super_admin()
    OR p_company_id IN (SELECT public.user_company_ids())
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  PERFORM public.expire_elapsed_company_trials(p_company_id);

  v_cs := public.get_active_company_subscription(p_company_id);

  IF v_cs.id IS NULL THEN
    SELECT * INTO v_latest
    FROM public.company_subscriptions cs
    WHERE cs.company_id = p_company_id
    ORDER BY cs.created_at DESC
    LIMIT 1;

    SELECT * INTO v_plan FROM public.subscriptions WHERE id = (
      SELECT subscription_id FROM public.companies WHERE id = p_company_id
    );

    IF v_latest.id IS NOT NULL THEN
      SELECT * INTO v_plan FROM public.subscriptions WHERE id = v_latest.plan_id;
      v_days_remaining := GREATEST(
        0,
        CEIL(EXTRACT(EPOCH FROM (v_latest.trial_ends_at - now())) / 86400)::INT
      );
      v_trial := jsonb_build_object(
        'is_free_trial', true,
        'status', v_latest.status,
        'trial_ends_at', v_latest.trial_ends_at,
        'days_remaining', v_days_remaining,
        'expired', v_latest.status = 'expired'::public.company_subscription_status
      );
    ELSE
      v_trial := jsonb_build_object('is_free_trial', false);
    END IF;

    SELECT COUNT(*)::INT INTO v_riders FROM public.riders WHERE company_id = p_company_id;

    RETURN jsonb_build_object(
      'subscription', CASE WHEN v_latest.id IS NULL THEN NULL ELSE to_jsonb(v_latest) END,
      'plan', to_jsonb(v_plan),
      'trial', v_trial,
      'usage', jsonb_build_object(
        'deliveries_created', 0,
        'deliveries_completed', 0,
        'riders', v_riders,
        'sms_consumed', 0,
        'storage_photos', 0
      )
    );
  END IF;

  SELECT * INTO v_plan FROM public.subscriptions WHERE id = v_cs.plan_id;
  SELECT COUNT(*)::INT INTO v_riders FROM public.riders WHERE company_id = p_company_id;
  v_deliveries := public.company_deliveries_in_period(
    p_company_id, v_cs.current_period_start, v_cs.current_period_end
  );
  SELECT COUNT(*)::INT INTO v_completed
  FROM public.deliveries d
  WHERE d.company_id = p_company_id
    AND d.status = 'delivered'
    AND d.delivered_at >= v_cs.current_period_start
    AND d.delivered_at < v_cs.current_period_end;
  v_sms := public.company_sms_consumed_in_period(
    p_company_id, v_cs.current_period_start, v_cs.current_period_end
  );
  SELECT COUNT(*) INTO v_photos FROM public.delivery_photos WHERE company_id = p_company_id;

  v_days_remaining := CASE
    WHEN v_cs.status = 'trialing'::public.company_subscription_status AND v_cs.trial_ends_at IS NOT NULL
      THEN GREATEST(0, CEIL(EXTRACT(EPOCH FROM (v_cs.trial_ends_at - now())) / 86400)::INT)
    ELSE NULL
  END;

  v_trial := jsonb_build_object(
    'is_free_trial', v_cs.status = 'trialing'::public.company_subscription_status,
    'status', v_cs.status,
    'trial_ends_at', v_cs.trial_ends_at,
    'days_remaining', v_days_remaining,
    'expired', false
  );

  RETURN jsonb_build_object(
    'subscription', to_jsonb(v_cs),
    'plan', to_jsonb(v_plan),
    'trial', v_trial,
    'period', jsonb_build_object(
      'start', v_cs.current_period_start,
      'end', v_cs.current_period_end
    ),
    'usage', jsonb_build_object(
      'deliveries_created', v_deliveries,
      'deliveries_completed', v_completed,
      'riders', v_riders,
      'sms_consumed', v_sms,
      'storage_photos', v_photos
    ),
    'limits', jsonb_build_object(
      'max_deliveries_per_month', v_plan.max_deliveries_per_month,
      'max_riders', v_plan.max_riders,
      'monthly_sms_allowance', v_plan.monthly_sms_allowance
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.run_scheduled_maintenance_jobs()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub_past_due INT := 0;
  v_trials_expired INT := 0;
  v_inv_overdue INT := 0;
  v_req_expired INT := 0;
  v_offers_expired INT := 0;
  v_gps_purged BIGINT := 0;
  v_inv_expired INT := 0;
BEGIN
  v_trials_expired := public.expire_elapsed_company_trials(NULL);

  UPDATE public.company_subscriptions cs SET
    status = 'past_due',
    updated_at = now()
  WHERE cs.status = 'active'
    AND cs.current_period_end < now()
    AND NOT EXISTS (
      SELECT 1 FROM public.company_subscriptions cs2
      WHERE cs2.company_id = cs.company_id AND cs2.status IN ('trialing', 'active') AND cs2.id <> cs.id
    );
  GET DIAGNOSTICS v_sub_past_due = ROW_COUNT;

  UPDATE public.invoices SET status = 'overdue', updated_at = now()
  WHERE status = 'issued' AND due_at < now();
  GET DIAGNOSTICS v_inv_overdue = ROW_COUNT;

  SELECT COUNT(*)::INT INTO v_inv_expired
  FROM public.company_invitations
  WHERE expires_at < now() AND accepted_at IS NULL AND revoked_at IS NULL;

  UPDATE public.delivery_requests SET status = 'expired', updated_at = now()
  WHERE status IN ('open', 'offered') AND expires_at IS NOT NULL AND expires_at < now();
  GET DIAGNOSTICS v_req_expired = ROW_COUNT;

  UPDATE public.delivery_offers SET status = 'expired'
  WHERE status = 'pending' AND expires_at IS NOT NULL AND expires_at < now();
  GET DIAGNOSTICS v_offers_expired = ROW_COUNT;

  v_gps_purged := public.purge_old_rider_location_samples(interval '48 hours');

  RETURN jsonb_build_object(
    'trials_expired', v_trials_expired,
    'subscriptions_marked_past_due', v_sub_past_due,
    'invoices_marked_overdue', v_inv_overdue,
    'delivery_requests_expired', v_req_expired,
    'delivery_offers_expired', v_offers_expired,
    'gps_samples_purged', v_gps_purged,
    'invitations_expired_checked', v_inv_expired
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_rider_plan_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max INT;
  v_count INT;
  v_cs public.company_subscriptions;
  v_plan public.subscriptions;
BEGIN
  PERFORM public.assert_company_operational(NEW.company_id);

  PERFORM public.expire_elapsed_company_trials(NEW.company_id);

  v_cs := public.get_active_company_subscription(NEW.company_id);
  IF v_cs.id IS NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.company_subscriptions cs
      WHERE cs.company_id = NEW.company_id
        AND cs.status = 'expired'::public.company_subscription_status
    ) THEN
      RAISE EXCEPTION 'trial_expired';
    END IF;
    RAISE EXCEPTION 'subscription_inactive';
  END IF;

  SELECT * INTO v_plan FROM public.subscriptions WHERE id = v_cs.plan_id;
  v_max := v_plan.max_riders;

  SELECT COUNT(*)::INT INTO v_count FROM public.riders WHERE company_id = NEW.company_id;
  IF v_count >= v_max THEN
    RAISE EXCEPTION 'rider_plan_limit_reached';
  END IF;

  RETURN NEW;
END;
$$;

-- Backfill: companies with no subscription row get a 7-day trial starting now
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
