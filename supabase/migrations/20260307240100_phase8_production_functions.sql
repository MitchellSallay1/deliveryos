-- DeliveryOS · Phase 8: production RPCs, tracking hardening, scheduled job helpers

-- Stronger tracking codes (~48 bits from 6 random bytes)
CREATE OR REPLACE FUNCTION public.generate_tracking_code()
RETURNS TEXT
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_code TEXT;
BEGIN
  LOOP
    v_code := 'DLV-' || upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 12));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.deliveries d WHERE d.tracking_code = v_code);
  END LOOP;
  RETURN v_code;
END;
$$;

-- Rate-limited public tracking (60 lookups / 5 min / client key)
CREATE OR REPLACE FUNCTION public.check_public_tracking_rate_limit(p_client_key TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.public_tracking_rate_limits;
  v_limit INT := 60;
  v_window INTERVAL := interval '5 minutes';
BEGIN
  IF p_client_key IS NULL OR length(trim(p_client_key)) < 8 THEN
    RETURN false;
  END IF;

  SELECT * INTO v_row FROM public.public_tracking_rate_limits WHERE client_key = p_client_key FOR UPDATE;
  IF NOT FOUND THEN
    INSERT INTO public.public_tracking_rate_limits (client_key, window_start, request_count)
    VALUES (p_client_key, now(), 1);
    RETURN true;
  END IF;

  IF v_row.window_start < now() - v_window THEN
    UPDATE public.public_tracking_rate_limits
    SET window_start = now(), request_count = 1
    WHERE client_key = p_client_key;
    RETURN true;
  END IF;

  IF v_row.request_count >= v_limit THEN
    RETURN false;
  END IF;

  UPDATE public.public_tracking_rate_limits
  SET request_count = request_count + 1
  WHERE client_key = p_client_key;
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.check_public_tracking_rate_limit FROM PUBLIC;

DROP FUNCTION IF EXISTS public.get_public_delivery_tracking(TEXT);

CREATE OR REPLACE FUNCTION public.get_public_delivery_tracking(
  p_tracking_code TEXT,
  p_client_key TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_d public.deliveries;
  v_company_name TEXT;
  v_rider_lat DOUBLE PRECISION;
  v_rider_lng DOUBLE PRECISION;
  v_rider_updated TIMESTAMPTZ;
BEGIN
  IF p_client_key IS NOT NULL AND NOT public.check_public_tracking_rate_limit(p_client_key) THEN
    RAISE EXCEPTION 'rate_limited';
  END IF;

  IF p_tracking_code IS NULL OR length(trim(p_tracking_code)) < 8 THEN
    RETURN NULL;
  END IF;

  SELECT d.* INTO v_d
  FROM public.deliveries d
  WHERE d.tracking_code = trim(p_tracking_code);

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  SELECT c.name INTO v_company_name FROM public.companies c WHERE c.id = v_d.company_id;

  IF v_d.status IN ('picked_up', 'in_transit') AND v_d.rider_id IS NOT NULL THEN
    SELECT
      public.blur_coordinate(rl.latitude, 2),
      public.blur_coordinate(rl.longitude, 2),
      rl.recorded_at
    INTO v_rider_lat, v_rider_lng, v_rider_updated
    FROM public.rider_locations rl
    WHERE rl.rider_id = v_d.rider_id
      AND rl.tracking_state IN ('active_delivery', 'paused')
      AND rl.recorded_at > now() - INTERVAL '30 minutes';
  END IF;

  RETURN jsonb_build_object(
    'tracking_code', v_d.tracking_code,
    'status', v_d.status,
    'company_name', v_company_name,
    'pickup_area', public.generalize_address(v_d.pickup_address),
    'destination_area', public.generalize_address(v_d.destination_address),
    'updated_at', v_d.updated_at,
    'rider_location', CASE
      WHEN v_rider_lat IS NOT NULL THEN jsonb_build_object(
        'latitude', v_rider_lat,
        'longitude', v_rider_lng,
        'recorded_at', v_rider_updated,
        'approximate', true
      )
      ELSE NULL
    END,
    'status_timeline', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'status', h.to_status,
        'at', h.created_at
      ) ORDER BY h.created_at), '[]'::JSONB)
      FROM public.delivery_status_history h
      WHERE h.delivery_id = v_d.id
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_public_delivery_tracking(TEXT, TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.log_api_auth_event(
  p_key_prefix TEXT,
  p_company_id UUID,
  p_success BOOLEAN,
  p_error_code TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  INSERT INTO public.api_auth_events (key_prefix, company_id, success, error_code)
  VALUES (p_key_prefix, p_company_id, p_success, p_error_code);
$$;

REVOKE ALL ON FUNCTION public.log_api_auth_event FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.log_api_auth_event TO service_role;

CREATE OR REPLACE FUNCTION public.queue_email(
  p_to_email TEXT,
  p_template_key TEXT,
  p_subject TEXT,
  p_body_html TEXT,
  p_body_text TEXT DEFAULT NULL,
  p_company_id UUID DEFAULT NULL,
  p_payload JSONB DEFAULT '{}'::JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO public.email_outbox (
    company_id, to_email, template_key, subject, body_html, body_text, payload
  ) VALUES (
    p_company_id, p_to_email, p_template_key, p_subject, p_body_html, p_body_text, COALESCE(p_payload, '{}'::JSONB)
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.queue_email FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.queue_email TO service_role;

CREATE OR REPLACE FUNCTION public.create_company_invitation(
  p_company_id UUID,
  p_email TEXT,
  p_role public.company_role
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_token TEXT;
  v_row public.company_invitations;
  v_company public.companies;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  PERFORM public.assert_company_operational(p_company_id);
  IF NOT public.has_company_role(p_company_id, ARRAY['company_owner']::public.company_role[])
    AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF p_role = 'company_owner' AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'cannot_invite_owner';
  END IF;

  v_token := encode(gen_random_bytes(24), 'hex');

  INSERT INTO public.company_invitations (company_id, email, role, token, invited_by, expires_at)
  VALUES (p_company_id, lower(trim(p_email)), p_role, v_token, auth.uid(), now() + INTERVAL '7 days')
  RETURNING * INTO v_row;

  SELECT * INTO v_company FROM public.companies WHERE id = p_company_id;

  PERFORM public.queue_email(
    lower(trim(p_email)),
    'team_invite',
    format('You are invited to %s on DeliveryOS', v_company.name),
    format(
      '<p>You have been invited to join <strong>%s</strong> on DeliveryOS.</p><p>Use your invitation link to accept.</p>',
      v_company.name
    ),
    format('You have been invited to join %s on DeliveryOS.', v_company.name),
    p_company_id,
    jsonb_build_object('invitation_id', v_row.id, 'token', v_token)
  );

  PERFORM public.log_audit_event(p_company_id, 'invitation_created', 'company_invitations', v_row.id, to_jsonb(v_row));

  RETURN jsonb_build_object(
    'id', v_row.id,
    'token', v_row.token,
    'email', v_row.email,
    'role', v_row.role,
    'expires_at', v_row.expires_at
  );
END;
$$;

-- Subscription & marketplace maintenance (invoke from jobs-scheduler Edge Function / cron)
CREATE OR REPLACE FUNCTION public.run_scheduled_maintenance_jobs()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub_past_due INT := 0;
  v_inv_overdue INT := 0;
  v_req_expired INT := 0;
  v_offers_expired INT := 0;
  v_gps_purged BIGINT := 0;
  v_inv_expired INT := 0;
BEGIN
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
    'subscriptions_marked_past_due', v_sub_past_due,
    'invoices_marked_overdue', v_inv_overdue,
    'delivery_requests_expired', v_req_expired,
    'delivery_offers_expired', v_offers_expired,
    'gps_samples_purged', v_gps_purged,
    'invitations_expired_checked', v_inv_expired
  );
END;
$$;

REVOKE ALL ON FUNCTION public.run_scheduled_maintenance_jobs FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.run_scheduled_maintenance_jobs TO service_role;

CREATE OR REPLACE FUNCTION public.admin_list_webhook_failures(
  p_limit INT DEFAULT 50,
  p_offset INT DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_items JSONB;
  v_total BIGINT;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT COUNT(*) INTO v_total
  FROM public.webhook_deliveries wd
  WHERE wd.status IN ('failed', 'dead');

  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::JSONB) INTO v_items
  FROM (
    SELECT wd.id, wd.status, wd.attempt_count, wd.last_error, wd.next_retry_at,
      wd.response_status, wd.created_at, wd.webhook_endpoint_id
    FROM public.webhook_deliveries wd
    WHERE wd.status IN ('failed', 'dead')
    ORDER BY wd.created_at DESC
    LIMIT LEAST(GREATEST(p_limit, 1), 100)
    OFFSET GREATEST(p_offset, 0)
  ) t;

  RETURN jsonb_build_object('items', v_items, 'total', v_total);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_list_webhook_failures TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_retry_webhook_delivery(p_delivery_id UUID)
RETURNS public.webhook_deliveries
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.webhook_deliveries;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  UPDATE public.webhook_deliveries SET
    status = 'pending',
    next_retry_at = now(),
    last_error = NULL
  WHERE id = p_delivery_id AND status IN ('failed', 'dead')
  RETURNING * INTO v_row;

  IF NOT FOUND THEN RAISE EXCEPTION 'not_found_or_not_retryable'; END IF;
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_retry_webhook_delivery TO authenticated;

CREATE OR REPLACE FUNCTION public.get_company_onboarding_status(p_company_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type public.company_business_type;
  v_has_rider BOOLEAN;
  v_has_delivery BOOLEAN;
  v_has_customer BOOLEAN;
  v_has_zone BOOLEAN;
  v_has_request BOOLEAN;
BEGIN
  IF NOT public.has_company_role(p_company_id, ARRAY['company_owner', 'dispatcher', 'support_staff']::public.company_role[])
     AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT business_type INTO v_type FROM public.companies WHERE id = p_company_id;

  SELECT EXISTS (SELECT 1 FROM public.riders r WHERE r.company_id = p_company_id) INTO v_has_rider;
  SELECT EXISTS (SELECT 1 FROM public.deliveries d WHERE d.company_id = p_company_id) INTO v_has_delivery;
  SELECT EXISTS (SELECT 1 FROM public.customers c WHERE c.company_id = p_company_id) INTO v_has_customer;
  SELECT EXISTS (SELECT 1 FROM public.delivery_zones z WHERE z.company_id = p_company_id) INTO v_has_zone;
  SELECT EXISTS (
    SELECT 1 FROM public.delivery_requests dr WHERE dr.merchant_company_id = p_company_id
  ) INTO v_has_request;

  RETURN jsonb_build_object(
    'business_type', v_type,
    'has_rider', v_has_rider,
    'has_delivery', v_has_delivery,
    'has_customer', v_has_customer,
    'has_zone', v_has_zone,
    'has_marketplace_request', v_has_request,
    'steps', CASE v_type
      WHEN 'merchant' THEN jsonb_build_array(
        jsonb_build_object('key', 'customer', 'done', v_has_customer, 'href', '/customers'),
        jsonb_build_object('key', 'request', 'done', v_has_request, 'href', '/merchant/requests')
      )
      WHEN 'hybrid' THEN jsonb_build_array(
        jsonb_build_object('key', 'zone', 'done', v_has_zone, 'href', '/settings'),
        jsonb_build_object('key', 'rider', 'done', v_has_rider, 'href', '/riders'),
        jsonb_build_object('key', 'delivery', 'done', v_has_delivery, 'href', '/deliveries'),
        jsonb_build_object('key', 'request', 'done', v_has_request, 'href', '/merchant/requests')
      )
      ELSE jsonb_build_array(
        jsonb_build_object('key', 'zone', 'done', v_has_zone, 'href', '/settings'),
        jsonb_build_object('key', 'rider', 'done', v_has_rider, 'href', '/riders'),
        jsonb_build_object('key', 'delivery', 'done', v_has_delivery, 'href', '/deliveries')
      )
    END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_company_onboarding_status TO authenticated;

CREATE OR REPLACE FUNCTION public.get_platform_health_snapshot()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  RETURN jsonb_build_object(
    'sms_pending', (SELECT COUNT(*) FROM public.sms_outbox WHERE status IN ('pending', 'failed')),
    'email_pending', (SELECT COUNT(*) FROM public.email_outbox WHERE status IN ('pending', 'failed')),
    'webhooks_pending', (SELECT COUNT(*) FROM public.webhook_deliveries WHERE status IN ('pending', 'failed')),
    'webhooks_dead', (SELECT COUNT(*) FROM public.webhook_deliveries WHERE status = 'dead'),
    'api_auth_failures_24h', (
      SELECT COUNT(*) FROM public.api_auth_events
      WHERE success = false AND created_at > now() - interval '24 hours'
    ),
    'checked_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_platform_health_snapshot TO authenticated;

-- Operational subscription guard for new mutations (read/history still allowed via RLS)
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
  v_cs := public.get_active_company_subscription(p_company_id);
  IF v_cs.id IS NULL THEN
    RAISE EXCEPTION 'subscription_inactive';
  END IF;
  IF v_cs.status IN ('cancelled', 'expired', 'suspended') THEN
    RAISE EXCEPTION 'subscription_inactive';
  END IF;
  IF v_cs.status = 'past_due' THEN
    RAISE EXCEPTION 'subscription_past_due';
  END IF;
  IF v_cs.current_period_end < now() AND v_cs.status NOT IN ('trialing') THEN
    RAISE EXCEPTION 'subscription_expired';
  END IF;
END;
$$;

-- Patch create_delivery to enforce subscription operational state
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
  p_customer_id UUID DEFAULT NULL,
  p_delivery_zone_id UUID DEFAULT NULL,
  p_fee_manual_override BOOLEAN DEFAULT false
)
RETURNS public.deliveries
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.deliveries;
  v_customer_id UUID := p_customer_id;
  v_fee INT;
  v_zone_fee INT;
BEGIN
  PERFORM public.assert_company_dispatcher(p_company_id);
  PERFORM public.assert_company_operational(p_company_id);
  PERFORM public.assert_subscription_operational(p_company_id);
  PERFORM public.assert_subscription_delivery_limit(p_company_id);

  v_fee := COALESCE(p_delivery_fee_lrd_cents, 0);
  IF p_delivery_zone_id IS NOT NULL AND NOT COALESCE(p_fee_manual_override, false) THEN
    v_zone_fee := public.zone_base_fee_cents(p_delivery_zone_id);
    IF v_zone_fee IS NOT NULL THEN
      v_fee := v_zone_fee;
    END IF;
  END IF;

  IF v_customer_id IS NULL AND p_customer_phone IS NOT NULL THEN
    INSERT INTO public.customers (company_id, full_name, phone, address)
    VALUES (p_company_id, p_customer_name, p_customer_phone, p_destination_address)
    ON CONFLICT (company_id, phone) DO UPDATE SET
      full_name = EXCLUDED.full_name,
      address = COALESCE(EXCLUDED.address, public.customers.address)
    RETURNING id INTO v_customer_id;
  END IF;

  INSERT INTO public.deliveries (
    company_id, tracking_code, pickup_business_name, pickup_address,
    customer_id, customer_name, customer_phone, destination_address,
    package_description, amount_to_collect_lrd_cents, delivery_fee_lrd_cents,
    delivery_zone_id, delivery_fee_manual_override,
    status, created_by
  ) VALUES (
    p_company_id, public.generate_tracking_code(),
    p_pickup_business_name, p_pickup_address, v_customer_id,
    p_customer_name, p_customer_phone, p_destination_address,
    p_package_description, COALESCE(p_amount_to_collect_lrd_cents, 0),
    v_fee, p_delivery_zone_id, COALESCE(p_fee_manual_override, false),
    'pending', auth.uid()
  )
  RETURNING * INTO v_row;

  INSERT INTO public.delivery_status_history (
    delivery_id, company_id, from_status, to_status, changed_by, note
  ) VALUES (
    v_row.id, p_company_id, NULL, 'pending', auth.uid(), 'created'
  );

  PERFORM public.enqueue_webhook_event(p_company_id, 'delivery.created', v_row.id, to_jsonb(v_row));
  RETURN v_row;
END;
$$;
