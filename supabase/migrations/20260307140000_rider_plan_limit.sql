-- Enforce subscription rider cap on insert (server-side, not UI-only)

CREATE OR REPLACE FUNCTION public.enforce_rider_plan_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max INT;
  v_count INT;
BEGIN
  SELECT s.max_riders INTO v_max
  FROM public.companies c
  JOIN public.subscriptions s ON s.id = c.subscription_id
  WHERE c.id = NEW.company_id;

  SELECT COUNT(*)::INT INTO v_count
  FROM public.riders WHERE company_id = NEW.company_id;

  IF v_count >= v_max THEN
    RAISE EXCEPTION 'plan rider limit reached (max %)', v_max;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER riders_plan_limit
  BEFORE INSERT ON public.riders
  FOR EACH ROW EXECUTE FUNCTION public.enforce_rider_plan_limit();
