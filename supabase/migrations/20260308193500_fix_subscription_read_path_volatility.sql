-- ---------------------------------------------------------------------------
-- Root cause of the production 25006 errors on get_workspace_report,
-- get_company_usage, and list_company_rider_locations:
--
--   "cannot execute UPDATE in a read-only transaction"
--
-- Confirmed from the live function definitions (20260308120000_seven_day_
-- free_trial.sql):
--
--   get_active_company_subscription(...) is declared STABLE, but its first
--   statement is `PERFORM public.expire_elapsed_company_trials(p_company_id)`
--   — a function with no volatility qualifier (VOLATILE by default) whose
--   entire body is an UPDATE. PostgREST routes STABLE-marked RPCs through a
--   read-only transaction; the nested UPDATE then fails with SQLSTATE 25006.
--
-- All three broken RPCs reach this same call, all three via chains that are
-- themselves correctly marked STABLE (they only ever read):
--
--   get_workspace_report('day')     -> can_use_feature('advanced_reports')
--                                       (called unconditionally regardless
--                                       of period, see phase4_billing_
--                                       functions.sql) -> get_active_company_
--                                       subscription
--   list_company_rider_locations    -> can_use_feature('gps_tracking')
--                                       -> get_active_company_subscription
--   get_company_usage               -> get_active_company_subscription
--                                       (AND its own separate, independent
--                                       `PERFORM expire_elapsed_company_
--                                       trials` call — a second instance of
--                                       the same anti-pattern, not merely
--                                       inherited transitively; both must be
--                                       removed for get_company_usage to
--                                       actually stop throwing 25006)
--
-- Also transitively affected, same root cause, not reported yet but fixed
-- here as a byproduct: get_company_admin_360, get_company_health_score
-- (both STABLE, both call get_active_company_subscription).
--
-- Fix (per the requested architecture — do NOT mark every read RPC
-- VOLATILE as a blanket workaround):
--
--   1. get_active_company_subscription stays STABLE and becomes a genuine
--      pure read: no PERFORM, no UPDATE anywhere in its body. It now
--      logically excludes an elapsed trial in its WHERE clause
--      (trial_ends_at > now()) instead of relying on the status column
--      having already been physically flipped to 'expired'. A trial whose
--      time is up is treated as "no active subscription" by every read
--      caller the instant it elapses — not after the next scheduled sweep.
--   2. get_company_usage stays STABLE, loses its own direct
--      `PERFORM expire_elapsed_company_trials` call, and its "no active
--      subscription" fallback branch (which shows the most recent
--      historical subscription row for display purposes) now computes its
--      `expired` flag logically (status = 'expired' OR trial_ends_at has
--      passed) instead of only trusting the physical status column, so the
--      UI doesn't show a stale "not expired" trial banner.
--   3. Actual physical status mutation (trialing -> expired) is untouched
--      and stays exactly where it already correctly lives: the standalone
--      expire_elapsed_company_trials() write function, invoked by
--      run_scheduled_maintenance_jobs() (platform-wide sweep every 5 min
--      via jobs-scheduler) and by assert_subscription_operational() /
--      ensure_initial_company_subscription() / enforce_rider_plan_limit()
--      (each of which already explicitly PERFORMs the expiry themselves,
--      before calling get_active_company_subscription — none of them
--      relied on get_active_company_subscription's now-removed side
--      effect, verified by reading every one of their bodies).
--
-- No RLS, tenant isolation, or business-rule change. No callers'
-- signatures change. assert_subscription_operational is untouched (it is
-- already correctly VOLATILE/write-capable per 20260308190200_fix_
-- subscription_operational_volatility.sql and is explicitly allowed to
-- keep expiring inline).
-- ---------------------------------------------------------------------------

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
  SELECT cs.* INTO v_row
  FROM public.company_subscriptions cs
  WHERE cs.company_id = p_company_id
    AND (
      cs.status IN ('active', 'past_due')
      OR (
        cs.status = 'trialing'::public.company_subscription_status
        AND (cs.trial_ends_at IS NULL OR cs.trial_ends_at > now())
      )
    )
  ORDER BY cs.created_at DESC
  LIMIT 1;

  RETURN v_row;
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
  v_latest_expired BOOLEAN;
BEGIN
  IF NOT (
    public.is_super_admin()
    OR p_company_id IN (SELECT public.user_company_ids())
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

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
      v_latest_expired := (v_latest.status = 'expired'::public.company_subscription_status)
        OR (
          v_latest.status = 'trialing'::public.company_subscription_status
          AND v_latest.trial_ends_at IS NOT NULL
          AND v_latest.trial_ends_at <= now()
        );
      v_trial := jsonb_build_object(
        'is_free_trial', true,
        'status', v_latest.status,
        'trial_ends_at', v_latest.trial_ends_at,
        'days_remaining', v_days_remaining,
        'expired', v_latest_expired
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
