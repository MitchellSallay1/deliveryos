-- DeliveryOS · Rider portal (link account + rider-safe transitions)

CREATE OR REPLACE FUNCTION public.normalize_phone(p TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT regexp_replace(COALESCE(p, ''), '[^0-9+]', '', 'g');
$$;

CREATE OR REPLACE FUNCTION public.claim_rider_profile(
  p_company_id UUID,
  p_rider_code TEXT
)
RETURNS public.riders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.riders;
  v_profile public.profiles;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  IF NOT public.has_company_role(
    p_company_id,
    ARRAY['rider', 'company_owner', 'dispatcher']::public.company_role[]
  ) AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT * INTO v_profile FROM public.profiles WHERE id = auth.uid();

  SELECT * INTO v_row
  FROM public.riders
  WHERE company_id = p_company_id
    AND rider_code = upper(trim(p_rider_code))
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'rider not found';
  END IF;

  IF v_row.user_id IS NOT NULL AND v_row.user_id <> auth.uid() THEN
    RAISE EXCEPTION 'rider already linked to another account';
  END IF;

  IF v_profile.phone IS NOT NULL
    AND public.normalize_phone(v_profile.phone) <> public.normalize_phone(v_row.phone) THEN
    RAISE EXCEPTION 'profile phone must match rider phone';
  END IF;

  UPDATE public.riders
  SET user_id = auth.uid()
  WHERE id = v_row.id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_rider_profile TO authenticated;

CREATE OR REPLACE FUNCTION public.set_rider_user_id(
  p_rider_id UUID,
  p_user_id UUID
)
RETURNS public.riders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.riders;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

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

  UPDATE public.riders SET user_id = p_user_id WHERE id = p_rider_id RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_rider_user_id TO authenticated;

CREATE OR REPLACE FUNCTION public.rider_transition_delivery_status(
  p_delivery_id UUID,
  p_to_status public.delivery_status,
  p_note TEXT DEFAULT NULL
)
RETURNS public.deliveries
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.deliveries;
  v_from public.delivery_status;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT * INTO v_row FROM public.deliveries WHERE id = p_delivery_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'delivery not found';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.riders r
    WHERE r.id = v_row.rider_id
      AND r.user_id = auth.uid()
      AND r.company_id = v_row.company_id
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  v_from := v_row.status;

  IF p_to_status IN ('pending', 'assigned', 'cancelled') THEN
    RAISE EXCEPTION 'rider cannot set status to %', p_to_status;
  END IF;

  IF NOT public.delivery_can_transition(v_from, p_to_status) THEN
    RAISE EXCEPTION 'invalid transition from % to %', v_from, p_to_status;
  END IF;

  RETURN public.delivery_transition_core(
    p_delivery_id,
    p_to_status,
    COALESCE(p_note, 'rider app'),
    auth.uid()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rider_transition_delivery_status TO authenticated;

-- Auto-create COD payment row when delivery is marked delivered
CREATE OR REPLACE FUNCTION public.ensure_cod_payment_on_delivered()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'delivered' AND (OLD.status IS DISTINCT FROM NEW.status) THEN
    INSERT INTO public.payments (
      company_id,
      delivery_id,
      amount_lrd_cents,
      status,
      collected_by,
      collected_at
    )
    VALUES (
      NEW.company_id,
      NEW.id,
      NEW.amount_to_collect_lrd_cents,
      CASE WHEN NEW.amount_to_collect_lrd_cents > 0 THEN 'collected'::public.payment_status ELSE 'reconciled'::public.payment_status END,
      NEW.rider_id,
      now()
    )
    ON CONFLICT (delivery_id) DO UPDATE SET
      amount_lrd_cents = EXCLUDED.amount_lrd_cents,
      status = EXCLUDED.status,
      collected_by = EXCLUDED.collected_by,
      collected_at = EXCLUDED.collected_at;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS deliveries_cod_payment ON public.deliveries;
CREATE TRIGGER deliveries_cod_payment
  AFTER UPDATE OF status ON public.deliveries
  FOR EACH ROW
  EXECUTE FUNCTION public.ensure_cod_payment_on_delivered();

CREATE OR REPLACE FUNCTION public.mark_payment_deposited(p_payment_id UUID)
RETURNS public.payments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.payments;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT * INTO v_row FROM public.payments WHERE id = p_payment_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'payment not found';
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

  UPDATE public.payments
  SET
    status = 'deposited',
    deposited_at = now()
  WHERE id = p_payment_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_payment_deposited TO authenticated;
