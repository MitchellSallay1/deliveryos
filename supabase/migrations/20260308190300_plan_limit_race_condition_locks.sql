-- Production readiness audit (H1): both plan-limit guards read a COUNT(*)
-- with no lock before allowing the insert, so two concurrent requests near a
-- company's cap can both pass the check and both commit — the company ends
-- up over its paid plan limit. Fix: lock the company's own row for the
-- duration of the check + insert, so concurrent attempts for the SAME
-- company serialize. Locking is scoped with `FOR UPDATE OF c` (companies
-- only) so unrelated companies sharing the same subscriptions/plan catalog
-- row are never blocked by each other.

CREATE OR REPLACE FUNCTION public.enforce_rider_plan_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max INT;
  v_count INT;
  v_status public.company_status;
BEGIN
  -- Locks the company row so a concurrent rider insert for the same company
  -- must wait here, closing the TOCTOU gap on the count below.
  SELECT c.status INTO v_status FROM public.companies c WHERE c.id = NEW.company_id FOR UPDATE;
  IF v_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'company_not_operational';
  END IF;

  SELECT s.max_riders INTO v_max
  FROM public.companies c
  JOIN public.subscriptions s ON s.id = c.subscription_id
  WHERE c.id = NEW.company_id;

  SELECT COUNT(*)::INT INTO v_count FROM public.riders WHERE company_id = NEW.company_id;

  IF v_count >= v_max THEN
    RAISE EXCEPTION 'rider_plan_limit_reached';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.assert_subscription_delivery_limit(p_company_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max INT;
  v_count INT;
BEGIN
  -- Locks the company row (not the shared subscriptions/plan row) so a
  -- concurrent delivery create for the same company must wait here.
  SELECT s.max_deliveries_per_month INTO v_max
  FROM public.companies c
  JOIN public.subscriptions s ON s.id = c.subscription_id
  WHERE c.id = p_company_id
  FOR UPDATE OF c;

  IF v_max IS NULL THEN
    RETURN;
  END IF;

  v_count := public.company_deliveries_in_billing_month(p_company_id);
  IF v_count >= v_max THEN
    RAISE EXCEPTION 'delivery_monthly_limit_reached';
  END IF;
END;
$$;
