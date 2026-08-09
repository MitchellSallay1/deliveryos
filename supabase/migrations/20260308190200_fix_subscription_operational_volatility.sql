-- Production readiness audit (C2): assert_subscription_operational was
-- declared STABLE (see 20260308120000_seven_day_free_trial.sql) but performs
-- a direct UPDATE when it lazily expires an elapsed trial. Postgres forbids
-- data-modifying statements inside a function's own body when that function
-- is declared STABLE/IMMUTABLE, so this raised a hard runtime error
-- ("UPDATE is not allowed in a non-volatile function") the first time any
-- company's trial actually expired — reproduced directly against a local
-- instance during this audit.
--
-- Its only caller, create_delivery, has no volatility qualifier and is
-- therefore already VOLATILE (Postgres default), so removing STABLE here
-- does not create a conflict up the call chain. VOLATILE is also the
-- factually correct classification for a function with a side effect.
--
-- Body is otherwise unchanged from the live (seven_day_free_trial.sql)
-- version.

CREATE OR REPLACE FUNCTION public.assert_subscription_operational(p_company_id UUID)
RETURNS VOID
LANGUAGE plpgsql
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
