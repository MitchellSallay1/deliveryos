-- DeliveryOS · deliveries business logic (RPC + audit trigger + realtime)

-- ---------------------------------------------------------------------------
-- Status transition rules (mirrors application domain)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delivery_can_transition(
  p_from public.delivery_status,
  p_to public.delivery_status
)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_from = 'pending' AND p_to IN ('assigned', 'cancelled') THEN true
    WHEN p_from = 'assigned' AND p_to IN ('accepted', 'cancelled', 'pending') THEN true
    WHEN p_from = 'accepted' AND p_to IN ('picked_up', 'cancelled', 'failed') THEN true
    WHEN p_from = 'picked_up' AND p_to IN ('in_transit', 'failed') THEN true
    WHEN p_from = 'in_transit' AND p_to IN ('delivered', 'failed') THEN true
    ELSE false
  END;
$$;

CREATE OR REPLACE FUNCTION public.generate_tracking_code()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  v_code TEXT;
BEGIN
  LOOP
    v_code := 'DLV-' || upper(substr(encode(gen_random_bytes(4), 'hex'), 1, 8));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.deliveries d WHERE d.tracking_code = v_code);
  END LOOP;
  RETURN v_code;
END;
$$;

CREATE OR REPLACE FUNCTION public.assert_company_dispatcher(p_company_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT (
    public.is_super_admin()
    OR public.has_company_role(
      p_company_id,
      ARRAY['company_owner', 'dispatcher']::public.company_role[]
    )
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Create delivery (+ optional upsert customer by phone)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_delivery(
  p_company_id UUID,
  p_pickup_business_name TEXT,
  p_pickup_address TEXT,
  p_customer_name TEXT,
  p_customer_phone TEXT,
  p_destination_address TEXT,
  p_package_description TEXT DEFAULT NULL,
  p_amount_to_collect_lrd_cents INT DEFAULT 0,
  p_delivery_fee_lrd_cents INT DEFAULT 0,
  p_customer_id UUID DEFAULT NULL
)
RETURNS public.deliveries
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.deliveries;
  v_customer_id UUID := p_customer_id;
BEGIN
  PERFORM public.assert_company_dispatcher(p_company_id);

  IF v_customer_id IS NULL AND p_customer_phone IS NOT NULL THEN
    INSERT INTO public.customers (company_id, full_name, phone, address)
    VALUES (p_company_id, p_customer_name, p_customer_phone, p_destination_address)
    ON CONFLICT (company_id, phone) DO UPDATE SET
      full_name = EXCLUDED.full_name,
      address = COALESCE(EXCLUDED.address, public.customers.address)
    RETURNING id INTO v_customer_id;
  END IF;

  INSERT INTO public.deliveries (
    company_id,
    tracking_code,
    pickup_business_name,
    pickup_address,
    customer_id,
    customer_name,
    customer_phone,
    destination_address,
    package_description,
    amount_to_collect_lrd_cents,
    delivery_fee_lrd_cents,
    status,
    created_by
  ) VALUES (
    p_company_id,
    public.generate_tracking_code(),
    p_pickup_business_name,
    p_pickup_address,
    v_customer_id,
    p_customer_name,
    p_customer_phone,
    p_destination_address,
    p_package_description,
    COALESCE(p_amount_to_collect_lrd_cents, 0),
    COALESCE(p_delivery_fee_lrd_cents, 0),
    'pending',
    auth.uid()
  )
  RETURNING * INTO v_row;

  INSERT INTO public.delivery_status_history (
    delivery_id, company_id, from_status, to_status, changed_by, note
  ) VALUES (
    v_row.id, p_company_id, NULL, 'pending', auth.uid(), 'created'
  );

  RETURN v_row;
END;
$$;

-- ---------------------------------------------------------------------------
-- Assign rider
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assign_delivery_rider(
  p_delivery_id UUID,
  p_rider_id UUID
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
  SELECT * INTO v_row FROM public.deliveries WHERE id = p_delivery_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'delivery not found';
  END IF;

  PERFORM public.assert_company_dispatcher(v_row.company_id);

  IF v_row.status NOT IN ('pending', 'assigned') THEN
    RAISE EXCEPTION 'cannot assign from status %', v_row.status;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.riders r
    WHERE r.id = p_rider_id AND r.company_id = v_row.company_id AND r.status <> 'suspended'
  ) THEN
    RAISE EXCEPTION 'invalid rider';
  END IF;

  v_from := v_row.status;

  UPDATE public.deliveries SET
    status = 'assigned',
    rider_id = p_rider_id,
    assigned_at = now()
  WHERE id = p_delivery_id
  RETURNING * INTO v_row;

  INSERT INTO public.delivery_status_history (
    delivery_id, company_id, from_status, to_status, changed_by, note
  ) VALUES (
    p_delivery_id, v_row.company_id, v_from, 'assigned', auth.uid(), 'rider assigned'
  );

  RETURN v_row;
END;
$$;

-- ---------------------------------------------------------------------------
-- Transition status
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.transition_delivery_status(
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
  SELECT * INTO v_row FROM public.deliveries WHERE id = p_delivery_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'delivery not found';
  END IF;

  PERFORM public.assert_company_dispatcher(v_row.company_id);

  v_from := v_row.status;

  IF NOT public.delivery_can_transition(v_from, p_to_status) THEN
    RAISE EXCEPTION 'invalid transition from % to %', v_from, p_to_status;
  END IF;

  UPDATE public.deliveries SET
    status = p_to_status,
    accepted_at = CASE WHEN p_to_status = 'accepted' THEN now() ELSE accepted_at END,
    picked_up_at = CASE WHEN p_to_status = 'picked_up' THEN now() ELSE picked_up_at END,
    in_transit_at = CASE WHEN p_to_status = 'in_transit' THEN now() ELSE in_transit_at END,
    delivered_at = CASE WHEN p_to_status = 'delivered' THEN now() ELSE delivered_at END,
    failed_at = CASE WHEN p_to_status = 'failed' THEN now() ELSE failed_at END,
    cancelled_at = CASE WHEN p_to_status = 'cancelled' THEN now() ELSE cancelled_at END
  WHERE id = p_delivery_id
  RETURNING * INTO v_row;

  INSERT INTO public.delivery_status_history (
    delivery_id, company_id, from_status, to_status, changed_by, note
  ) VALUES (
    p_delivery_id, v_row.company_id, v_from, p_to_status, auth.uid(), COALESCE(p_note, '')
  );

  IF p_to_status = 'delivered' AND v_row.rider_id IS NOT NULL THEN
    UPDATE public.riders SET completed_deliveries = completed_deliveries + 1
    WHERE id = v_row.rider_id;
  END IF;

  RETURN v_row;
END;
$$;

-- ---------------------------------------------------------------------------
-- Public tracking (no tenant data leak)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_delivery_tracking(p_tracking_code TEXT)
RETURNS TABLE (
  tracking_code TEXT,
  status public.delivery_status,
  customer_name TEXT,
  pickup_address TEXT,
  destination_address TEXT,
  updated_at TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT
    d.tracking_code,
    d.status,
    d.customer_name,
    d.pickup_address,
    d.destination_address,
    d.updated_at
  FROM public.deliveries d
  WHERE d.tracking_code = p_tracking_code;
$$;

GRANT EXECUTE ON FUNCTION public.create_delivery TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_delivery_rider TO authenticated;
GRANT EXECUTE ON FUNCTION public.transition_delivery_status TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_delivery_tracking TO anon, authenticated;

-- Tighten direct table writes: mutations go through RPC
DROP POLICY IF EXISTS deliveries_write ON public.deliveries;

CREATE POLICY deliveries_insert ON public.deliveries
  FOR INSERT TO authenticated
  WITH CHECK (
    public.is_super_admin()
    OR public.has_company_role(company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[])
  );

-- Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.deliveries;
