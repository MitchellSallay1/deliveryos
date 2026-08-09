-- DeliveryOS · SMS credits, outbound queue, inbound keywords, delivery hooks

CREATE TABLE IF NOT EXISTS public.sms_credit_ledger (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  delta INT NOT NULL,
  balance_after INT NOT NULL,
  reason TEXT NOT NULL,
  reference_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sms_credit_ledger_company ON public.sms_credit_ledger (company_id, created_at DESC);

ALTER TABLE public.sms_credit_ledger ENABLE ROW LEVEL SECURITY;

CREATE POLICY sms_ledger_select ON public.sms_credit_ledger
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR company_id IN (SELECT public.user_company_ids())
  );

-- Outbound SMS (stub gateway: mark sent + deduct 1 credit)
CREATE OR REPLACE FUNCTION public.queue_outbound_sms(
  p_company_id UUID,
  p_phone TEXT,
  p_body TEXT,
  p_delivery_id UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_credits INT;
  v_balance INT;
BEGIN
  IF p_phone IS NULL OR p_phone = '' OR p_body IS NULL OR p_body = '' THEN
    RETURN false;
  END IF;

  SELECT sms_credits INTO v_credits FROM public.companies WHERE id = p_company_id FOR UPDATE;
  IF NOT FOUND OR v_credits < 1 THEN
    RETURN false;
  END IF;

  v_balance := v_credits - 1;
  UPDATE public.companies SET sms_credits = v_balance WHERE id = p_company_id;

  INSERT INTO public.sms_credit_ledger (company_id, delta, balance_after, reason, reference_id)
  VALUES (p_company_id, -1, v_balance, 'outbound_sms', p_delivery_id);

  INSERT INTO public.sms_logs (company_id, direction, phone, body, credits_used, delivery_id)
  VALUES (p_company_id, 'outbound', p_phone, p_body, 1, p_delivery_id);

  INSERT INTO public.notification_logs (company_id, channel, recipient, body, status)
  VALUES (p_company_id, 'sms', p_phone, p_body, 'sent');

  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_rider_new_job(p_delivery public.deliveries)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_phone TEXT;
  v_body TEXT;
BEGIN
  IF p_delivery.rider_id IS NULL THEN
    RETURN;
  END IF;
  SELECT phone INTO v_phone FROM public.riders WHERE id = p_delivery.rider_id;
  v_body := format(
    E'New Delivery\nPickup: %s\nCustomer: %s\nReply A Accept, P Picked Up, D Delivered, F Failed',
    p_delivery.pickup_address,
    p_delivery.customer_phone
  );
  PERFORM public.queue_outbound_sms(p_delivery.company_id, v_phone, v_body, p_delivery.id);
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_customer_tracking(
  p_delivery public.deliveries,
  p_status public.delivery_status
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_body TEXT;
  v_track TEXT;
BEGIN
  v_track := coalesce(
    nullif(current_setting('app.public_url', true), ''),
    'http://localhost:5173'
  ) || '/track/' || p_delivery.tracking_code;

  IF p_status IN ('picked_up', 'in_transit') THEN
    v_body := format(
      E'Hello %s\nYour package is on the way.\nStatus: %s\nTrack: %s',
      p_delivery.customer_name,
      replace(p_status::TEXT, '_', ' '),
      v_track
    );
  ELSIF p_status = 'delivered' THEN
    v_body := format(E'Hello %s\nYour package was delivered. Thank you!', p_delivery.customer_name);
  ELSE
    RETURN;
  END IF;

  PERFORM public.queue_outbound_sms(
    p_delivery.company_id,
    p_delivery.customer_phone,
    v_body,
    p_delivery.id
  );
END;
$$;

-- Patch assign + transition to send SMS
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

  PERFORM public.notify_rider_new_job(v_row);

  RETURN v_row;
END;
$$;

-- Shared transition core (no auth — called by RPC + inbound SMS)
CREATE OR REPLACE FUNCTION public.delivery_transition_core(
  p_delivery_id UUID,
  p_to_status public.delivery_status,
  p_note TEXT,
  p_changed_by UUID
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
    p_delivery_id, v_row.company_id, v_from, p_to_status, p_changed_by, COALESCE(p_note, '')
  );

  IF p_to_status = 'delivered' AND v_row.rider_id IS NOT NULL THEN
    UPDATE public.riders SET completed_deliveries = completed_deliveries + 1
    WHERE id = v_row.rider_id;
  END IF;

  IF p_to_status IN ('picked_up', 'in_transit', 'delivered') THEN
    PERFORM public.notify_customer_tracking(v_row, p_to_status);
  END IF;

  RETURN v_row;
END;
$$;

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
  v_company UUID;
BEGIN
  SELECT company_id INTO v_company FROM public.deliveries WHERE id = p_delivery_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'delivery not found';
  END IF;
  PERFORM public.assert_company_dispatcher(v_company);
  RETURN public.delivery_transition_core(p_delivery_id, p_to_status, COALESCE(p_note, ''), auth.uid());
END;
$$;

-- Inbound rider keywords (Edge Function / webhook calls with service role)
CREATE OR REPLACE FUNCTION public.process_inbound_sms(
  p_phone TEXT,
  p_text TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_key TEXT;
  v_rider RECORD;
  v_delivery RECORD;
  v_target public.delivery_status;
  v_from public.delivery_status;
BEGIN
  v_key := upper(trim(left(p_text, 1)));

  IF v_key = 'A' THEN
    v_target := 'accepted';
  ELSIF v_key = 'P' THEN
    v_target := 'picked_up';
  ELSIF v_key = 'D' THEN
    v_target := 'delivered';
  ELSIF v_key = 'F' THEN
    v_target := 'failed';
  ELSE
    RETURN jsonb_build_object('ok', false, 'message', 'unknown keyword');
  END IF;

  FOR v_rider IN
    SELECT id, company_id FROM public.riders
    WHERE phone = p_phone OR right(regexp_replace(phone, '\D', '', 'g'), 9) = right(regexp_replace(p_phone, '\D', '', 'g'), 9)
  LOOP
    SELECT * INTO v_delivery FROM public.deliveries
    WHERE company_id = v_rider.company_id
      AND rider_id = v_rider.id
      AND status IN ('assigned', 'accepted', 'picked_up', 'in_transit')
    ORDER BY created_at DESC
    LIMIT 1;

    IF NOT FOUND THEN
      CONTINUE;
    END IF;

    v_from := v_delivery.status;

    IF v_key = 'D' AND v_from = 'picked_up' THEN
      PERFORM public.delivery_transition_core(v_delivery.id, 'in_transit', 'sms:auto-transit', NULL);
      SELECT * INTO v_delivery FROM public.deliveries WHERE id = v_delivery.id;
      v_from := v_delivery.status;
    END IF;

    IF NOT public.delivery_can_transition(v_from, v_target) THEN
      RETURN jsonb_build_object('ok', false, 'message', format('cannot transition from %s', v_from));
    END IF;

    PERFORM public.delivery_transition_core(v_delivery.id, v_target, 'sms:inbound', NULL);

    INSERT INTO public.sms_logs (company_id, direction, phone, body, credits_used, delivery_id)
    VALUES (v_rider.company_id, 'inbound', p_phone, p_text, 0, v_delivery.id);

    RETURN jsonb_build_object(
      'ok', true,
      'delivery_id', v_delivery.id,
      'status', v_target
    );
  END LOOP;

  RETURN jsonb_build_object('ok', false, 'message', 'no active delivery');
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_inbound_sms TO service_role;

-- Super admin top-up (optional ops)
CREATE OR REPLACE FUNCTION public.admin_add_sms_credits(
  p_company_id UUID,
  p_amount INT,
  p_reason TEXT DEFAULT 'admin_top_up'
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_balance INT;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'amount must be positive';
  END IF;

  UPDATE public.companies SET sms_credits = sms_credits + p_amount
  WHERE id = p_company_id
  RETURNING sms_credits INTO v_balance;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'company not found';
  END IF;

  INSERT INTO public.sms_credit_ledger (company_id, delta, balance_after, reason)
  VALUES (p_company_id, p_amount, v_balance, p_reason);

  RETURN v_balance;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_add_sms_credits TO authenticated;
