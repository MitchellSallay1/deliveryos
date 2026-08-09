-- DeliveryOS · Rider channels (smartphone + button phone via SMS/USSD)

-- ---------------------------------------------------------------------------
-- Types & columns
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'rider_access_mode') THEN
    CREATE TYPE public.rider_access_mode AS ENUM ('smartphone', 'button_phone', 'both');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'delivery_proof_method') THEN
    CREATE TYPE public.delivery_proof_method AS ENUM (
      'photo',
      'customer_otp',
      'dispatcher_confirmation',
      'none'
    );
  END IF;
END $$;

ALTER TABLE public.riders
  ADD COLUMN IF NOT EXISTS access_mode public.rider_access_mode NOT NULL DEFAULT 'smartphone',
  ADD COLUMN IF NOT EXISTS phone_normalized TEXT,
  ADD COLUMN IF NOT EXISTS sms_channel_enabled BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS ussd_channel_enabled BOOLEAN NOT NULL DEFAULT true;

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS allow_smartphone_riders BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS allow_button_phone_riders BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS enable_rider_sms BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS enable_rider_ussd BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS require_otp_button_phone_delivery BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE public.deliveries
  ADD COLUMN IF NOT EXISTS proof_method public.delivery_proof_method NOT NULL DEFAULT 'photo',
  ADD COLUMN IF NOT EXISTS rider_job_sms_status TEXT,
  ADD COLUMN IF NOT EXISTS rider_job_sms_sent_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_completion_channel TEXT;

ALTER TABLE public.delivery_status_history
  ADD COLUMN IF NOT EXISTS transition_source TEXT;

CREATE INDEX IF NOT EXISTS idx_riders_phone_normalized
  ON public.riders (phone_normalized)
  WHERE phone_normalized IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Phone helpers (Liberia MSISDN)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.normalize_phone_lr(p TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_digits TEXT;
BEGIN
  v_digits := regexp_replace(COALESCE(p, ''), '[^0-9]', '', 'g');
  IF v_digits = '' THEN
    RETURN '';
  END IF;
  IF length(v_digits) = 9 THEN
    RETURN '+231' || v_digits;
  ELSIF length(v_digits) = 10 AND left(v_digits, 1) = '0' THEN
    RETURN '+231' || substr(v_digits, 2);
  ELSIF length(v_digits) >= 11 AND left(v_digits, 3) = '231' THEN
    RETURN '+' || v_digits;
  END IF;
  IF left(v_digits, 1) <> '+' THEN
    RETURN '+' || v_digits;
  END IF;
  RETURN v_digits;
END;
$$;

CREATE OR REPLACE FUNCTION public.phone_matches_msisdn(p_a TEXT, p_b TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT right(regexp_replace(COALESCE(p_a, ''), '[^0-9]', '', 'g'), 9)
       = right(regexp_replace(COALESCE(p_b, ''), '[^0-9]', '', 'g'), 9)
     AND length(regexp_replace(COALESCE(p_a, ''), '[^0-9]', '', 'g')) >= 9
     AND length(regexp_replace(COALESCE(p_b, ''), '[^0-9]', '', 'g')) >= 9;
$$;

CREATE OR REPLACE FUNCTION public.trg_riders_normalize_phone()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.phone_normalized := public.normalize_phone_lr(NEW.phone);
  NEW.phone := COALESCE(NULLIF(public.normalize_phone_lr(NEW.phone), ''), NEW.phone);
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS riders_normalize_phone ON public.riders;
CREATE TRIGGER riders_normalize_phone
  BEFORE INSERT OR UPDATE OF phone ON public.riders
  FOR EACH ROW EXECUTE FUNCTION public.trg_riders_normalize_phone();

UPDATE public.riders
SET phone = phone
WHERE phone_normalized IS NULL;

-- ---------------------------------------------------------------------------
-- OTP + USSD sessions + channel audit
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.delivery_verification_otps (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  delivery_id UUID NOT NULL REFERENCES public.deliveries (id) ON DELETE CASCADE,
  otp_code TEXT NOT NULL,
  purpose TEXT NOT NULL DEFAULT 'delivery',
  expires_at TIMESTAMPTZ NOT NULL,
  verified_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_delivery_otps_delivery
  ON public.delivery_verification_otps (delivery_id, created_at DESC);

ALTER TABLE public.delivery_verification_otps ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.ussd_sessions (
  session_id TEXT PRIMARY KEY,
  phone TEXT NOT NULL,
  rider_id UUID REFERENCES public.riders (id) ON DELETE SET NULL,
  state TEXT NOT NULL DEFAULT 'main',
  context JSONB NOT NULL DEFAULT '{}',
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ussd_sessions_expires ON public.ussd_sessions (expires_at);

ALTER TABLE public.ussd_sessions ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.rider_channel_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  rider_id UUID REFERENCES public.riders (id) ON DELETE SET NULL,
  delivery_id UUID REFERENCES public.deliveries (id) ON DELETE SET NULL,
  channel TEXT NOT NULL,
  command_text TEXT,
  success BOOLEAN NOT NULL,
  response_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_rider_channel_events_company
  ON public.rider_channel_events (company_id, created_at DESC);

ALTER TABLE public.rider_channel_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY rider_channel_events_tenant ON public.rider_channel_events
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR company_id IN (SELECT public.user_company_ids())
  );

-- ---------------------------------------------------------------------------
-- Feature flags (plan JSON fallback)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.can_use_feature(p_company_id UUID, p_feature_key TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cs public.company_subscriptions;
  v_plan public.subscriptions;
  v_ok BOOLEAN := false;
BEGIN
  v_cs := public.get_active_company_subscription(p_company_id);
  IF v_cs.id IS NULL OR v_cs.status NOT IN ('trialing', 'active') THEN
    RETURN false;
  END IF;
  IF v_cs.current_period_end < now() THEN
    RETURN false;
  END IF;

  SELECT * INTO v_plan FROM public.subscriptions WHERE id = v_cs.plan_id AND is_active = true;
  IF NOT FOUND THEN
    RETURN false;
  END IF;

  v_ok := CASE p_feature_key
    WHEN 'proof_of_delivery' THEN v_plan.proof_of_delivery
    WHEN 'advanced_reports' THEN v_plan.advanced_reports
    WHEN 'api_access' THEN v_plan.api_access
    WHEN 'gps_tracking' THEN v_plan.gps_tracking
    WHEN 'custom_branding' THEN v_plan.custom_branding
    WHEN 'sms_notifications' THEN v_plan.monthly_sms_allowance > 0
    WHEN 'rider_sms' THEN v_plan.monthly_sms_allowance > 0
      OR COALESCE((v_plan.features ->> 'rider_sms')::BOOLEAN, false)
    WHEN 'rider_ussd' THEN COALESCE((v_plan.features ->> 'rider_ussd')::BOOLEAN, true)
    WHEN 'customer_otp' THEN COALESCE((v_plan.features ->> 'customer_otp')::BOOLEAN, true)
    WHEN 'multi_branch' THEN v_plan.multi_branch
    WHEN 'fleet_management' THEN v_plan.fleet_management
    WHEN 'inventory' THEN v_plan.inventory
    WHEN 'warehouse_management' THEN v_plan.warehouse_management
    WHEN 'cod_reconciliation' THEN v_plan.cod_reconciliation
    WHEN 'profitability_reports' THEN v_plan.profitability_reports
    WHEN 'marketplace_access' THEN v_plan.marketplace_access
    WHEN 'merchant_portal' THEN v_plan.merchant_portal
    WHEN 'provider_network' THEN v_plan.provider_network
    WHEN 'marketplace_api' THEN v_plan.marketplace_api
    WHEN 'sms' THEN v_cs.status IN ('trialing', 'active')
    ELSE COALESCE((v_plan.features ->> p_feature_key)::BOOLEAN, false)
  END;

  RETURN COALESCE(v_ok, false);
END;
$$;

-- ---------------------------------------------------------------------------
-- Transition core (+ source metadata)
-- Prior version: 4-arg, RETURNS deliveries. New version adds p_transition_source.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.delivery_transition_core(
  UUID,
  public.delivery_status,
  TEXT,
  UUID
);

CREATE OR REPLACE FUNCTION public.delivery_transition_core(
  p_delivery_id UUID,
  p_to_status public.delivery_status,
  p_note TEXT,
  p_changed_by UUID,
  p_transition_source TEXT DEFAULT 'api'
)
RETURNS public.deliveries
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.deliveries;
  v_from public.delivery_status;
  v_event TEXT;
  v_source TEXT := COALESCE(NULLIF(trim(p_transition_source), ''), 'api');
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
    cancelled_at = CASE WHEN p_to_status = 'cancelled' THEN now() ELSE cancelled_at END,
    last_completion_channel = CASE
      WHEN p_to_status IN ('delivered', 'failed') THEN v_source
      ELSE last_completion_channel
    END
  WHERE id = p_delivery_id
  RETURNING * INTO v_row;

  INSERT INTO public.delivery_status_history (
    delivery_id, company_id, from_status, to_status, changed_by, note, transition_source
  ) VALUES (
    p_delivery_id, v_row.company_id, v_from, p_to_status, p_changed_by,
    COALESCE(p_note, ''), v_source
  );

  IF p_to_status = 'delivered' AND v_row.rider_id IS NOT NULL THEN
    UPDATE public.riders SET completed_deliveries = completed_deliveries + 1
    WHERE id = v_row.rider_id;
  END IF;

  IF p_to_status IN ('picked_up', 'in_transit', 'delivered') THEN
    PERFORM public.notify_customer_tracking(v_row, p_to_status);
  END IF;

  IF p_to_status = 'in_transit' THEN
    PERFORM public.maybe_issue_delivery_otp(v_row);
  END IF;

  v_event := CASE p_to_status
    WHEN 'assigned' THEN 'delivery.assigned'
    WHEN 'picked_up' THEN 'delivery.picked_up'
    WHEN 'in_transit' THEN 'delivery.in_transit'
    WHEN 'delivered' THEN 'delivery.delivered'
    WHEN 'failed' THEN 'delivery.failed'
    ELSE NULL
  END;

  IF v_event IS NOT NULL THEN
    PERFORM public.enqueue_webhook_event(v_row.company_id, v_event, v_row.id, to_jsonb(v_row));
  END IF;

  RETURN v_row;
END;
$$;

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

  PERFORM public.assert_company_operational(v_row.company_id);

  IF NOT EXISTS (
    SELECT 1 FROM public.riders r
    WHERE r.id = v_row.rider_id AND r.user_id = auth.uid() AND r.company_id = v_row.company_id
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
    p_delivery_id, p_to_status, COALESCE(p_note, 'rider app'), auth.uid(), 'pwa'
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- Customer OTP for button-phone delivery proof
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.maybe_issue_delivery_otp(p_delivery public.deliveries)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company public.companies;
  v_rider public.riders;
  v_code TEXT;
  v_body TEXT;
BEGIN
  IF p_delivery.rider_id IS NULL THEN
    RETURN;
  END IF;

  SELECT * INTO v_company FROM public.companies WHERE id = p_delivery.company_id;
  SELECT * INTO v_rider FROM public.riders WHERE id = p_delivery.rider_id;

  IF NOT v_company.require_otp_button_phone_delivery THEN
    RETURN;
  END IF;
  IF NOT public.can_use_feature(p_delivery.company_id, 'customer_otp') THEN
    RETURN;
  END IF;
  IF v_rider.access_mode = 'smartphone' AND p_delivery.proof_method <> 'customer_otp' THEN
    RETURN;
  END IF;
  IF p_delivery.proof_method NOT IN ('customer_otp') THEN
    RETURN;
  END IF;

  v_code := lpad((floor(random() * 10000))::INT::TEXT, 4, '0');

  INSERT INTO public.delivery_verification_otps (
    company_id, delivery_id, otp_code, purpose, expires_at
  ) VALUES (
    p_delivery.company_id, p_delivery.id, v_code, 'delivery', now() + interval '24 hours'
  );

  v_body := format(
    'Your DeliveryOS delivery verification code is %s.',
    v_code
  );
  PERFORM public.queue_outbound_sms(p_delivery.company_id, p_delivery.customer_phone, v_body, p_delivery.id);
END;
$$;

CREATE OR REPLACE FUNCTION public.verify_delivery_otp(
  p_delivery_id UUID,
  p_otp TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.delivery_verification_otps;
BEGIN
  IF p_otp IS NULL OR length(trim(p_otp)) < 4 THEN
    RETURN false;
  END IF;

  SELECT * INTO v_row
  FROM public.delivery_verification_otps
  WHERE delivery_id = p_delivery_id
    AND otp_code = trim(p_otp)
    AND verified_at IS NULL
    AND expires_at > now()
  ORDER BY created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  UPDATE public.delivery_verification_otps
  SET verified_at = now()
  WHERE id = v_row.id;

  RETURN true;
END;
$$;

-- ---------------------------------------------------------------------------
-- Outbound job SMS (button phone template)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delivery_short_address(p TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p IS NULL OR p = '' THEN '—'
    WHEN length(p) <= 24 THEN p
    ELSE left(p, 21) || '...'
  END;
$$;

CREATE OR REPLACE FUNCTION public.tracking_suffix(p_code TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT upper(right(regexp_replace(COALESCE(p_code, ''), '[^A-Za-z0-9]', '', 'g'), 4));
$$;

-- Prior version (20260307160000): RETURNS VOID
DROP FUNCTION IF EXISTS public.notify_rider_new_job(public.deliveries);

CREATE OR REPLACE FUNCTION public.notify_rider_new_job(p_delivery public.deliveries)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rider public.riders;
  v_company public.companies;
  v_phone TEXT;
  v_body TEXT;
  v_sent BOOLEAN := false;
  v_suffix TEXT;
BEGIN
  IF p_delivery.rider_id IS NULL THEN
    RETURN false;
  END IF;

  SELECT * INTO v_rider FROM public.riders WHERE id = p_delivery.rider_id;
  SELECT * INTO v_company FROM public.companies WHERE id = p_delivery.company_id;

  IF v_rider.access_mode NOT IN ('button_phone', 'both') THEN
    UPDATE public.deliveries SET
      rider_job_sms_status = 'skipped',
      rider_job_sms_sent_at = now()
    WHERE id = p_delivery.id;
    RETURN false;
  END IF;

  IF NOT v_company.enable_rider_sms OR NOT v_rider.sms_channel_enabled THEN
    UPDATE public.deliveries SET rider_job_sms_status = 'skipped', rider_job_sms_sent_at = now()
    WHERE id = p_delivery.id;
    RETURN false;
  END IF;

  IF NOT public.can_use_feature(p_delivery.company_id, 'rider_sms') THEN
    UPDATE public.deliveries SET rider_job_sms_status = 'failed', rider_job_sms_sent_at = now()
    WHERE id = p_delivery.id;
    RETURN false;
  END IF;

  v_phone := v_rider.phone;
  v_suffix := public.tracking_suffix(p_delivery.tracking_code);

  v_body := format(
    E'DeliveryOS\nNew job: %s\nPickup: %s\nDrop: %s\n\nReply:\nA = Accept\nP = Picked Up\nT = In Transit\nD = Delivered\nF = Failed',
    p_delivery.tracking_code,
    public.delivery_short_address(p_delivery.pickup_address),
    public.delivery_short_address(p_delivery.destination_address)
  );

  v_sent := public.queue_outbound_sms(p_delivery.company_id, v_phone, v_body, p_delivery.id);

  UPDATE public.deliveries SET
    rider_job_sms_status = CASE WHEN v_sent THEN 'sent' ELSE 'failed' END,
    rider_job_sms_sent_at = now()
  WHERE id = p_delivery.id;

  RETURN v_sent;
END;
$$;

CREATE OR REPLACE FUNCTION public.resend_rider_job_sms(p_delivery_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.deliveries;
BEGIN
  SELECT * INTO v_row FROM public.deliveries WHERE id = p_delivery_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'delivery not found';
  END IF;

  PERFORM public.assert_company_dispatcher(v_row.company_id);

  IF v_row.rider_id IS NULL THEN
    RAISE EXCEPTION 'no rider assigned';
  END IF;

  RETURN public.notify_rider_new_job(v_row);
END;
$$;

GRANT EXECUTE ON FUNCTION public.resend_rider_job_sms TO authenticated;

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
  v_rider public.riders;
  v_company public.companies;
  v_proof public.delivery_proof_method := 'photo';
BEGIN
  SELECT * INTO v_row FROM public.deliveries WHERE id = p_delivery_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'delivery not found';
  END IF;

  PERFORM public.assert_company_dispatcher(v_row.company_id);
  PERFORM public.assert_company_operational(v_row.company_id);

  IF v_row.status NOT IN ('pending', 'assigned') THEN
    RAISE EXCEPTION 'cannot assign from status %', v_row.status;
  END IF;

  SELECT * INTO v_rider FROM public.riders
  WHERE id = p_rider_id AND company_id = v_row.company_id AND status <> 'suspended';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid rider';
  END IF;

  SELECT * INTO v_company FROM public.companies WHERE id = v_row.company_id;

  IF v_rider.access_mode = 'smartphone' AND NOT v_company.allow_smartphone_riders THEN
    RAISE EXCEPTION 'smartphone riders disabled for this company';
  END IF;
  IF v_rider.access_mode = 'button_phone' AND NOT v_company.allow_button_phone_riders THEN
    RAISE EXCEPTION 'button phone riders disabled for this company';
  END IF;

  v_proof := CASE
    WHEN v_rider.access_mode = 'smartphone' THEN 'photo'::public.delivery_proof_method
    WHEN v_company.require_otp_button_phone_delivery THEN 'customer_otp'::public.delivery_proof_method
    ELSE 'none'::public.delivery_proof_method
  END;

  v_from := v_row.status;

  UPDATE public.deliveries SET
    status = 'assigned',
    rider_id = p_rider_id,
    assigned_at = now(),
    proof_method = v_proof,
    rider_job_sms_status = NULL,
    rider_job_sms_sent_at = NULL
  WHERE id = p_delivery_id
  RETURNING * INTO v_row;

  INSERT INTO public.delivery_status_history (
    delivery_id, company_id, from_status, to_status, changed_by, note, transition_source
  ) VALUES (
    p_delivery_id, v_row.company_id, v_from, 'assigned', auth.uid(), 'rider assigned', 'dispatcher'
  );

  PERFORM public.notify_rider_new_job(v_row);
  PERFORM public.enqueue_webhook_event(v_row.company_id, 'delivery.assigned', v_row.id, to_jsonb(v_row));

  RETURN v_row;
END;
$$;

-- ---------------------------------------------------------------------------
-- Rider channel command core (SMS + USSD actions)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rider_sms_failure_reason(p_code INT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_code
    WHEN 1 THEN 'Customer unavailable'
    WHEN 2 THEN 'Wrong address'
    WHEN 3 THEN 'Customer refused'
    WHEN 4 THEN 'Other'
    ELSE 'Failed via SMS'
  END;
$$;

CREATE OR REPLACE FUNCTION public.assert_rider_channel_rate_limit(
  p_phone TEXT,
  p_channel TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  SELECT COUNT(*)::INT INTO v_count
  FROM public.rider_channel_events
  WHERE created_at > now() - interval '1 minute'
    AND channel = p_channel
    AND command_text IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.riders r
      WHERE public.phone_matches_msisdn(r.phone, p_phone)
        AND r.id = rider_channel_events.rider_id
    );

  IF v_count > 30 THEN
    RAISE EXCEPTION 'rate_limited';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.apply_rider_channel_command(
  p_phone TEXT,
  p_text TEXT,
  p_channel TEXT DEFAULT 'sms'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rider public.riders;
  v_company public.companies;
  v_delivery public.deliveries;
  v_cmd TEXT;
  v_suffix TEXT;
  v_otp TEXT;
  v_fail_code INT;
  v_target public.delivery_status;
  v_from public.delivery_status;
  v_parts TEXT[];
  v_active UUID[];
  v_match_count INT;
  v_note TEXT;
  v_reply TEXT;
  v_ok BOOLEAN := false;
  v_rider_found BOOLEAN := false;
BEGIN
  BEGIN
    PERFORM public.assert_rider_channel_rate_limit(p_phone, p_channel);
  EXCEPTION
    WHEN OTHERS THEN
      RETURN jsonb_build_object(
        'ok', false,
        'reply_message', 'Too many requests. Wait a minute and try again.',
        'reply_phone', public.normalize_phone_lr(p_phone)
      );
  END;

  v_parts := regexp_split_to_array(trim(COALESCE(p_text, '')), '\s+');
  IF array_length(v_parts, 1) IS NULL OR v_parts[1] = '' THEN
    RETURN jsonb_build_object(
      'ok', false,
      'reply_message',
      'Reply A Accept, P Picked Up, T In Transit, D Delivered, F Failed. Example: A 69B9',
      'reply_phone', public.normalize_phone_lr(p_phone)
    );
  END IF;

  v_cmd := upper(left(v_parts[1], 1));
  v_suffix := CASE WHEN array_length(v_parts, 1) >= 2 THEN upper(v_parts[2]) ELSE NULL END;
  v_otp := CASE WHEN array_length(v_parts, 1) >= 3 THEN v_parts[3] ELSE NULL END;

  IF v_cmd = 'A' THEN v_target := 'accepted';
  ELSIF v_cmd = 'P' THEN v_target := 'picked_up';
  ELSIF v_cmd = 'T' THEN v_target := 'in_transit';
  ELSIF v_cmd = 'D' THEN v_target := 'delivered';
  ELSIF v_cmd = 'F' THEN v_target := 'failed';
  ELSE
    RETURN jsonb_build_object(
      'ok', false,
      'reply_message', 'Unknown command. Use A P T D F.',
      'reply_phone', public.normalize_phone_lr(p_phone)
    );
  END IF;

  IF v_cmd = 'F' AND array_length(v_parts, 1) >= 3 AND v_otp ~ '^[0-9]+$' AND length(v_otp) <= 2 THEN
    v_fail_code := v_otp::INT;
    v_otp := NULL;
  ELSIF v_cmd = 'F' AND array_length(v_parts, 1) >= 3 THEN
    v_fail_code := NULL;
  ELSIF v_cmd = 'F' AND v_suffix ~ '^[0-9]+$' AND length(v_suffix) <= 2 AND length(v_suffix) < 4 THEN
    v_fail_code := v_suffix::INT;
    v_suffix := NULL;
  END IF;

  FOR v_rider IN
    SELECT r.*
    FROM public.riders r
    WHERE public.phone_matches_msisdn(r.phone, p_phone)
      AND r.status <> 'suspended'
  LOOP
    v_rider_found := true;
    SELECT * INTO v_company FROM public.companies WHERE id = v_rider.company_id;

    IF p_channel = 'sms' THEN
      IF NOT v_company.enable_rider_sms OR NOT v_rider.sms_channel_enabled THEN
        CONTINUE;
      END IF;
      IF NOT public.can_use_feature(v_rider.company_id, 'rider_sms') THEN
        CONTINUE;
      END IF;
    ELSIF p_channel = 'ussd' THEN
      IF NOT v_company.enable_rider_ussd OR NOT v_rider.ussd_channel_enabled THEN
        CONTINUE;
      END IF;
      IF NOT public.can_use_feature(v_rider.company_id, 'rider_ussd') THEN
        CONTINUE;
      END IF;
    END IF;

    IF v_rider.access_mode = 'smartphone' AND p_channel IN ('sms', 'ussd') THEN
      CONTINUE;
    END IF;

    BEGIN
      PERFORM public.assert_company_operational(v_rider.company_id);
    EXCEPTION
      WHEN OTHERS THEN
        CONTINUE;
    END;

    SELECT array_agg(d.id ORDER BY d.created_at DESC) INTO v_active
    FROM public.deliveries d
    WHERE d.company_id = v_rider.company_id
      AND d.rider_id = v_rider.id
      AND d.status IN ('assigned', 'accepted', 'picked_up', 'in_transit');

    IF v_active IS NULL THEN
      CONTINUE;
    END IF;

    IF v_suffix IS NOT NULL AND length(v_suffix) = 4 THEN
      SELECT * INTO v_delivery
      FROM public.deliveries d
      WHERE d.id = ANY (v_active)
        AND public.tracking_suffix(d.tracking_code) = v_suffix
      LIMIT 1;

      IF NOT FOUND THEN
        INSERT INTO public.rider_channel_events (
          company_id, rider_id, channel, command_text, success, response_message
        ) VALUES (
          v_rider.company_id, v_rider.id, p_channel, p_text, false, 'job not found'
        );
        RETURN jsonb_build_object(
          'ok', false,
          'reply_message', format('No job matching %s.', v_suffix),
          'reply_phone', v_rider.phone,
          'company_id', v_rider.company_id
        );
      END IF;
    ELSE
      v_match_count := cardinality(v_active);
      IF v_match_count = 1 THEN
        SELECT * INTO v_delivery FROM public.deliveries WHERE id = v_active[1];
      ELSE
        SELECT string_agg(
          format('%s %s → %s', public.tracking_suffix(d.tracking_code),
            public.delivery_short_address(d.pickup_address),
            public.delivery_short_address(d.destination_address)),
          E'\n'
        ) INTO v_reply
        FROM public.deliveries d
        WHERE d.id = ANY (v_active);

        INSERT INTO public.rider_channel_events (
          company_id, rider_id, channel, command_text, success, response_message
        ) VALUES (
          v_rider.company_id, v_rider.id, p_channel, p_text, false, 'multiple jobs'
        );

        RETURN jsonb_build_object(
          'ok', false,
          'reply_message',
          format(E'You have multiple jobs:\n%s\n\nReply:\n%s %s', v_reply, v_cmd, public.tracking_suffix(
            (SELECT tracking_code FROM public.deliveries WHERE id = v_active[1])
          )),
          'reply_phone', v_rider.phone,
          'company_id', v_rider.company_id
        );
      END IF;
    END IF;

    IF v_delivery.rider_id <> v_rider.id THEN
      CONTINUE;
    END IF;

    v_from := v_delivery.status;

    IF v_cmd = 'D' AND v_delivery.proof_method = 'customer_otp'
       AND v_company.require_otp_button_phone_delivery THEN
      IF v_otp IS NULL THEN
        RETURN jsonb_build_object(
          'ok', false,
          'reply_message',
          format('Enter OTP: D %s ####', public.tracking_suffix(v_delivery.tracking_code)),
          'reply_phone', v_rider.phone,
          'company_id', v_rider.company_id
        );
      END IF;
      IF NOT public.verify_delivery_otp(v_delivery.id, v_otp) THEN
        INSERT INTO public.rider_channel_events (
          company_id, rider_id, delivery_id, channel, command_text, success, response_message
        ) VALUES (
          v_rider.company_id, v_rider.id, v_delivery.id, p_channel, p_text, false, 'bad otp'
        );
        RETURN jsonb_build_object(
          'ok', false,
          'reply_message', 'Invalid verification code.',
          'reply_phone', v_rider.phone,
          'company_id', v_rider.company_id
        );
      END IF;
    END IF;

    IF NOT public.delivery_can_transition(v_from, v_target) THEN
      INSERT INTO public.rider_channel_events (
        company_id, rider_id, delivery_id, channel, command_text, success, response_message
      ) VALUES (
        v_rider.company_id, v_rider.id, v_delivery.id, p_channel, p_text, false,
        format('invalid transition %s', v_from)
      );
      RETURN jsonb_build_object(
        'ok', false,
        'reply_message', format('Cannot %s from status %s.', lower(replace(v_target::TEXT, '_', ' ')), v_from),
        'reply_phone', v_rider.phone,
        'company_id', v_rider.company_id
      );
    END IF;

    v_note := format('%s:%s', p_channel, v_cmd);
    IF v_cmd = 'F' AND v_fail_code IS NOT NULL THEN
      v_note := v_note || ' ' || public.rider_sms_failure_reason(v_fail_code);
      UPDATE public.deliveries SET failure_reason = public.rider_sms_failure_reason(v_fail_code)
      WHERE id = v_delivery.id;
    END IF;

    PERFORM public.delivery_transition_core(
      v_delivery.id, v_target, v_note, NULL, p_channel
    );

    v_reply := CASE v_target
      WHEN 'accepted' THEN format('%s accepted.', v_delivery.tracking_code)
      WHEN 'picked_up' THEN format('%s marked picked up.', v_delivery.tracking_code)
      WHEN 'in_transit' THEN format('%s is now in transit.', v_delivery.tracking_code)
      WHEN 'delivered' THEN format('%s delivered.', v_delivery.tracking_code)
      WHEN 'failed' THEN format('%s marked failed.', v_delivery.tracking_code)
      ELSE format('%s updated.', v_delivery.tracking_code)
    END;

    INSERT INTO public.rider_channel_events (
      company_id, rider_id, delivery_id, channel, command_text, success, response_message
    ) VALUES (
      v_rider.company_id, v_rider.id, v_delivery.id, p_channel, p_text, true, v_reply
    );

    INSERT INTO public.sms_logs (company_id, direction, phone, body, credits_used, delivery_id)
    VALUES (v_rider.company_id, 'inbound', p_phone, p_text, 0, v_delivery.id);

    RETURN jsonb_build_object(
      'ok', true,
      'delivery_id', v_delivery.id,
      'status', v_target,
      'reply_message', v_reply,
      'reply_phone', v_rider.phone,
      'company_id', v_rider.company_id
    );
  END LOOP;

  IF NOT v_rider_found THEN
    RETURN jsonb_build_object(
      'ok', false,
      'reply_message', 'Rider phone not recognized.',
      'reply_phone', public.normalize_phone_lr(p_phone)
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', false,
    'reply_message', 'No active delivery for this rider.',
    'reply_phone', public.normalize_phone_lr(p_phone)
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'ok', false,
      'reply_message', 'Could not process command. Check status and try again.',
      'reply_phone', public.normalize_phone_lr(p_phone)
    );
END;
$$;

REVOKE ALL ON FUNCTION public.apply_rider_channel_command FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.apply_rider_channel_command TO service_role;

CREATE OR REPLACE FUNCTION public.process_inbound_sms(
  p_phone TEXT,
  p_text TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.apply_rider_channel_command(p_phone, p_text, 'sms');
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_inbound_sms TO service_role;

-- ---------------------------------------------------------------------------
-- USSD (provider-neutral)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ussd_menu_main()
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT E'DeliveryOS Rider\n1. My jobs\n2. Accept\n3. Picked up\n4. In transit\n5. Delivered\n6. Failed\n7. Jobs today';
$$;

CREATE OR REPLACE FUNCTION public.handle_ussd_request(
  p_phone TEXT,
  p_session_id TEXT,
  p_text TEXT,
  p_network TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.ussd_sessions;
  v_rider public.riders;
  v_parts TEXT[];
  v_choice TEXT;
  v_reply TEXT;
  v_continue BOOLEAN := true;
  v_cmd TEXT;
  v_result JSONB;
  v_jobs TEXT;
  v_idx INT;
  v_delivery_id UUID;
  v_ids UUID[];
  v_count INT;
BEGIN
  DELETE FROM public.ussd_sessions WHERE expires_at < now();

  SELECT * INTO v_session FROM public.ussd_sessions WHERE session_id = p_session_id;

  IF NOT FOUND THEN
    INSERT INTO public.ussd_sessions (session_id, phone, state, context, expires_at)
    VALUES (
      p_session_id,
      public.normalize_phone_lr(p_phone),
      'main',
      '{}'::JSONB,
      now() + interval '5 minutes'
    )
    RETURNING * INTO v_session;
  ELSE
    UPDATE public.ussd_sessions SET
      phone = public.normalize_phone_lr(p_phone),
      expires_at = now() + interval '5 minutes',
      updated_at = now()
    WHERE session_id = p_session_id
    RETURNING * INTO v_session;
  END IF;

  SELECT r.* INTO v_rider
  FROM public.riders r
  WHERE public.phone_matches_msisdn(r.phone, p_phone)
    AND r.status <> 'suspended'
    AND r.access_mode IN ('button_phone', 'both')
    AND r.ussd_channel_enabled
  ORDER BY r.created_at
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'continue_session', false,
      'message', 'Phone not registered as a button-phone rider.'
    );
  END IF;

  UPDATE public.ussd_sessions SET rider_id = v_rider.id WHERE session_id = p_session_id;

  v_parts := string_to_array(COALESCE(p_text, ''), '*');
  v_choice := v_parts[array_length(v_parts, 1)];

  IF v_session.state = 'main' AND (p_text IS NULL OR p_text = '') THEN
    RETURN jsonb_build_object('continue_session', true, 'message', public.ussd_menu_main());
  END IF;

  IF v_session.state = 'main' THEN
    IF v_choice = '1' THEN
      SELECT array_agg(d.id ORDER BY d.created_at DESC), COUNT(*)::INT
      INTO v_ids, v_count
      FROM public.deliveries d
      WHERE d.rider_id = v_rider.id
        AND d.status IN ('assigned', 'accepted', 'picked_up', 'in_transit');

      IF v_count IS NULL OR v_count = 0 THEN
        RETURN jsonb_build_object('continue_session', false, 'message', 'No active jobs.');
      END IF;

      SELECT string_agg(
        format('%s. %s %s→%s', ord, public.tracking_suffix(d.tracking_code),
          public.delivery_short_address(d.pickup_address),
          public.delivery_short_address(d.destination_address)),
        E'\n'
      ) INTO v_jobs
      FROM (
        SELECT d.*, row_number() OVER (ORDER BY d.created_at DESC) AS ord
        FROM public.deliveries d
        WHERE d.id = ANY (v_ids)
      ) d;

      UPDATE public.ussd_sessions SET
        state = 'pick_job',
        context = jsonb_build_object('delivery_ids', v_ids),
        updated_at = now()
      WHERE session_id = p_session_id;

      RETURN jsonb_build_object(
        'continue_session', true,
        'message', format(E'My Jobs\n%s\nSelect job number.', v_jobs)
      );
    ELSIF v_choice IN ('2', '3', '4', '5', '6') THEN
      v_cmd := CASE v_choice
        WHEN '2' THEN 'A'
        WHEN '3' THEN 'P'
        WHEN '4' THEN 'T'
        WHEN '5' THEN 'D'
        WHEN '6' THEN 'F'
      END;
      v_result := public.apply_rider_channel_command(p_phone, v_cmd, 'ussd');
      v_continue := NOT COALESCE((v_result ->> 'ok')::BOOLEAN, false);
      RETURN jsonb_build_object(
        'continue_session', v_continue,
        'message', COALESCE(v_result ->> 'reply_message', 'Done.')
      );
    ELSIF v_choice = '7' THEN
      SELECT COUNT(*)::INT INTO v_count
      FROM public.deliveries d
      WHERE d.rider_id = v_rider.id
        AND d.created_at >= date_trunc('day', now());

      RETURN jsonb_build_object(
        'continue_session', false,
        'message', format('Jobs today: %s', COALESCE(v_count, 0))
      );
    ELSE
      RETURN jsonb_build_object('continue_session', true, 'message', public.ussd_menu_main());
    END IF;
  ELSIF v_session.state = 'pick_job' THEN
    v_idx := v_choice::INT;
    v_ids := ARRAY(
      SELECT jsonb_array_elements_text(v_session.context -> 'delivery_ids')::UUID
    );
    IF v_idx < 1 OR v_idx > cardinality(v_ids) THEN
      RETURN jsonb_build_object('continue_session', true, 'message', 'Invalid selection.');
    END IF;
    v_delivery_id := v_ids[v_idx];

    UPDATE public.ussd_sessions SET
      state = 'job_action',
      context = jsonb_build_object('delivery_id', v_delivery_id),
      updated_at = now()
    WHERE session_id = p_session_id;

    RETURN jsonb_build_object(
      'continue_session', true,
      'message', E'1 Accept\n2 Picked up\n3 In transit\n4 Delivered\n5 Failed'
    );
  ELSIF v_session.state = 'job_action' THEN
    v_delivery_id := (v_session.context ->> 'delivery_id')::UUID;
    v_cmd := CASE v_choice
      WHEN '1' THEN 'A'
      WHEN '2' THEN 'P'
      WHEN '3' THEN 'T'
      WHEN '4' THEN 'D'
      WHEN '5' THEN 'F'
      ELSE NULL
    END;

    IF v_cmd IS NULL THEN
      RETURN jsonb_build_object('continue_session', true, 'message', 'Pick 1-5.');
    END IF;

    v_result := public.apply_rider_channel_command(
      p_phone,
      format('%s %s', v_cmd, public.tracking_suffix(
        (SELECT tracking_code FROM public.deliveries WHERE id = v_delivery_id)
      )),
      'ussd'
    );

    DELETE FROM public.ussd_sessions WHERE session_id = p_session_id;

    RETURN jsonb_build_object(
      'continue_session', false,
      'message', COALESCE(v_result ->> 'reply_message', 'Done.')
    );
  END IF;

  RETURN jsonb_build_object('continue_session', false, 'message', 'Session ended.');
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'continue_session', false,
      'message', 'Request failed. Try again later.'
    );
END;
$$;

REVOKE ALL ON FUNCTION public.handle_ussd_request FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.handle_ussd_request TO service_role;

CREATE OR REPLACE FUNCTION public.update_company_rider_channel_settings(
  p_company_id UUID,
  p_settings JSONB
)
RETURNS public.companies
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.companies;
BEGIN
  IF NOT (
    public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY['company_owner']::public.company_role[])
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE public.companies SET
    allow_smartphone_riders = COALESCE((p_settings ->> 'allow_smartphone_riders')::BOOLEAN, allow_smartphone_riders),
    allow_button_phone_riders = COALESCE((p_settings ->> 'allow_button_phone_riders')::BOOLEAN, allow_button_phone_riders),
    enable_rider_sms = COALESCE((p_settings ->> 'enable_rider_sms')::BOOLEAN, enable_rider_sms),
    enable_rider_ussd = COALESCE((p_settings ->> 'enable_rider_ussd')::BOOLEAN, enable_rider_ussd),
    require_otp_button_phone_delivery = COALESCE(
      (p_settings ->> 'require_otp_button_phone_delivery')::BOOLEAN,
      require_otp_button_phone_delivery
    ),
    updated_at = now()
  WHERE id = p_company_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_company_rider_channel_settings TO authenticated;

CREATE OR REPLACE FUNCTION public.get_rider_channel_analytics(p_company_id UUID, p_days INT DEFAULT 30)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_since TIMESTAMPTZ := now() - make_interval(days => p_days);
BEGIN
  IF NOT (
    public.is_super_admin()
    OR p_company_id IN (SELECT public.user_company_ids())
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  RETURN jsonb_build_object(
    'completed_pwa', (
      SELECT COUNT(*) FROM public.delivery_status_history h
      WHERE h.company_id = p_company_id
        AND h.to_status = 'delivered'
        AND h.transition_source = 'pwa'
        AND h.created_at >= v_since
    ),
    'completed_sms', (
      SELECT COUNT(*) FROM public.delivery_status_history h
      WHERE h.company_id = p_company_id
        AND h.to_status = 'delivered'
        AND h.transition_source = 'sms'
        AND h.created_at >= v_since
    ),
    'completed_ussd', (
      SELECT COUNT(*) FROM public.delivery_status_history h
      WHERE h.company_id = p_company_id
        AND h.to_status = 'delivered'
        AND h.transition_source = 'ussd'
        AND h.created_at >= v_since
    ),
    'sms_command_failures', (
      SELECT COUNT(*) FROM public.rider_channel_events e
      WHERE e.company_id = p_company_id AND e.channel = 'sms' AND NOT e.success
        AND e.created_at >= v_since
    ),
    'ussd_command_failures', (
      SELECT COUNT(*) FROM public.rider_channel_events e
      WHERE e.company_id = p_company_id AND e.channel = 'ussd' AND NOT e.success
        AND e.created_at >= v_since
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_rider_channel_analytics TO authenticated;

GRANT EXECUTE ON FUNCTION public.queue_outbound_sms(UUID, TEXT, TEXT, UUID) TO service_role;

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
  PERFORM public.assert_company_operational(v_company);
  PERFORM public.assert_company_dispatcher(v_company);
  RETURN public.delivery_transition_core(
    p_delivery_id, p_to_status, COALESCE(p_note, ''), auth.uid(), 'dispatcher'
  );
END;
$$;
