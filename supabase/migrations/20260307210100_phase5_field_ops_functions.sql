-- DeliveryOS · Phase 5: field ops functions, RLS, webhooks, analytics, public tracking

-- ---------------------------------------------------------------------------
-- Helpers: GPS privacy blur (~1.1km grid)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.blur_coordinate(p_value DOUBLE PRECISION, p_decimals INT DEFAULT 2)
RETURNS DOUBLE PRECISION
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT round(p_value::NUMERIC, p_decimals)::DOUBLE PRECISION;
$$;

CREATE OR REPLACE FUNCTION public.purge_old_rider_location_samples(p_older_than INTERVAL DEFAULT INTERVAL '48 hours')
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted INT;
BEGIN
  DELETE FROM public.rider_location_samples
  WHERE recorded_at < now() - p_older_than;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

REVOKE ALL ON FUNCTION public.purge_old_rider_location_samples FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- Rider location write (rider only, GPS feature + active delivery when required)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_rider_location(
  p_latitude DOUBLE PRECISION,
  p_longitude DOUBLE PRECISION,
  p_accuracy DOUBLE PRECISION DEFAULT NULL,
  p_heading DOUBLE PRECISION DEFAULT NULL,
  p_speed DOUBLE PRECISION DEFAULT NULL,
  p_tracking_state public.rider_tracking_state DEFAULT 'active_delivery',
  p_delivery_id UUID DEFAULT NULL
)
RETURNS public.rider_locations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rider public.riders;
  v_row public.rider_locations;
  v_active_delivery UUID;
BEGIN
  SELECT * INTO v_rider
  FROM public.riders
  WHERE user_id = auth.uid()
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_a_rider';
  END IF;

  IF NOT public.can_use_feature(v_rider.company_id, 'gps_tracking') THEN
    RAISE EXCEPTION 'gps_not_enabled';
  END IF;

  IF p_tracking_state IN ('active_delivery', 'paused') THEN
    SELECT d.id INTO v_active_delivery
    FROM public.deliveries d
    WHERE d.rider_id = v_rider.id
      AND d.status IN ('assigned', 'accepted', 'picked_up', 'in_transit')
    ORDER BY d.updated_at DESC
    LIMIT 1;

    IF v_active_delivery IS NULL AND p_tracking_state = 'active_delivery' THEN
      p_tracking_state := 'available';
    END IF;
  END IF;

  IF p_tracking_state = 'off' THEN
    DELETE FROM public.rider_locations WHERE rider_id = v_rider.id;
    RETURN NULL;
  END IF;

  INSERT INTO public.rider_locations (
    company_id, rider_id, delivery_id,
    latitude, longitude, accuracy, heading, speed,
    tracking_state, recorded_at
  ) VALUES (
    v_rider.company_id, v_rider.id, COALESCE(p_delivery_id, v_active_delivery),
    p_latitude, p_longitude, p_accuracy, p_heading, p_speed,
    p_tracking_state, now()
  )
  ON CONFLICT (rider_id) DO UPDATE SET
    delivery_id = EXCLUDED.delivery_id,
    latitude = EXCLUDED.latitude,
    longitude = EXCLUDED.longitude,
    accuracy = EXCLUDED.accuracy,
    heading = EXCLUDED.heading,
    speed = EXCLUDED.speed,
    tracking_state = EXCLUDED.tracking_state,
    recorded_at = now(),
    updated_at = now()
  RETURNING * INTO v_row;

  IF p_tracking_state = 'active_delivery' THEN
    INSERT INTO public.rider_location_samples (
      company_id, rider_id, delivery_id, latitude, longitude, recorded_at
    ) VALUES (
      v_rider.company_id, v_rider.id, v_row.delivery_id,
      p_latitude, p_longitude, now()
    );
  END IF;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_rider_location TO authenticated;

CREATE OR REPLACE FUNCTION public.list_company_rider_locations(p_company_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT (
    public.is_super_admin()
    OR (
      p_company_id IN (SELECT public.user_company_ids())
      AND public.has_company_role(
        p_company_id,
        ARRAY['company_owner', 'dispatcher']::public.company_role[]
      )
    )
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF NOT public.can_use_feature(p_company_id, 'gps_tracking') THEN
    RAISE EXCEPTION 'gps_not_enabled';
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'rider_id', rl.rider_id,
      'rider_name', r.full_name,
      'rider_code', r.rider_code,
      'rider_status', r.status,
      'delivery_id', rl.delivery_id,
      'tracking_code', d.tracking_code,
      'delivery_status', d.status,
      'latitude', rl.latitude,
      'longitude', rl.longitude,
      'accuracy', rl.accuracy,
      'heading', rl.heading,
      'speed', rl.speed,
      'tracking_state', rl.tracking_state,
      'recorded_at', rl.recorded_at
    ))
    FROM public.rider_locations rl
    JOIN public.riders r ON r.id = rl.rider_id
    LEFT JOIN public.deliveries d ON d.id = rl.delivery_id
    WHERE rl.company_id = p_company_id
      AND rl.tracking_state <> 'off'
  ), '[]'::JSONB);
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_company_rider_locations TO authenticated;

-- ---------------------------------------------------------------------------
-- Public tracking (privacy-safe + approximate rider when in transit)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_public_delivery_tracking(p_tracking_code TEXT)
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
  SELECT d.* INTO v_d
  FROM public.deliveries d
  WHERE d.tracking_code = p_tracking_code;

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

GRANT EXECUTE ON FUNCTION public.get_public_delivery_tracking TO anon, authenticated;

-- Keep legacy name as wrapper
CREATE OR REPLACE FUNCTION public.get_delivery_tracking(p_tracking_code TEXT)
RETURNS TABLE (
  tracking_code TEXT,
  status public.delivery_status,
  company_name TEXT,
  pickup_area TEXT,
  destination_area TEXT,
  updated_at TIMESTAMPTZ,
  status_timeline JSONB
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    (t ->> 'tracking_code')::TEXT,
    (t ->> 'status')::public.delivery_status,
    (t ->> 'company_name')::TEXT,
    (t ->> 'pickup_area')::TEXT,
    (t ->> 'destination_area')::TEXT,
    (t ->> 'updated_at')::TIMESTAMPTZ,
    (t -> 'status_timeline')::JSONB
  FROM (
    SELECT public.get_public_delivery_tracking(p_tracking_code) AS t
  ) s
  WHERE t IS NOT NULL;
$$;

-- ---------------------------------------------------------------------------
-- Delivery zones CRUD (owner/dispatcher)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.upsert_delivery_zone(p_payload JSONB)
RETURNS public.delivery_zones
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID := (p_payload ->> 'company_id')::UUID;
  v_id UUID := NULLIF(p_payload ->> 'id', '')::UUID;
  v_row public.delivery_zones;
BEGIN
  IF NOT public.has_company_role(
    v_company_id,
    ARRAY['company_owner', 'dispatcher']::public.company_role[]
  ) AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF v_id IS NULL THEN
    INSERT INTO public.delivery_zones (
      company_id, name, area_label, base_fee_cents, currency, is_active, sort_order
    ) VALUES (
      v_company_id,
      p_payload ->> 'name',
      p_payload ->> 'area_label',
      COALESCE((p_payload ->> 'base_fee_cents')::INT, 0),
      COALESCE(p_payload ->> 'currency', 'LRD'),
      COALESCE((p_payload ->> 'is_active')::BOOLEAN, true),
      COALESCE((p_payload ->> 'sort_order')::INT, 0)
    )
    RETURNING * INTO v_row;
  ELSE
    UPDATE public.delivery_zones SET
      name = COALESCE(p_payload ->> 'name', name),
      area_label = COALESCE(p_payload ->> 'area_label', area_label),
      base_fee_cents = COALESCE((p_payload ->> 'base_fee_cents')::INT, base_fee_cents),
      currency = COALESCE(p_payload ->> 'currency', currency),
      is_active = COALESCE((p_payload ->> 'is_active')::BOOLEAN, is_active),
      sort_order = COALESCE((p_payload ->> 'sort_order')::INT, sort_order)
    WHERE id = v_id AND company_id = v_company_id
    RETURNING * INTO v_row;
  END IF;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_delivery_zone TO authenticated;

CREATE OR REPLACE FUNCTION public.list_delivery_zones(p_company_id UUID)
RETURNS SETOF public.delivery_zones
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT z.*
  FROM public.delivery_zones z
  WHERE z.company_id = p_company_id
    AND (
      public.is_super_admin()
      OR p_company_id IN (SELECT public.user_company_ids())
    )
  ORDER BY z.sort_order, z.name;
$$;

GRANT EXECUTE ON FUNCTION public.list_delivery_zones TO authenticated;

CREATE OR REPLACE FUNCTION public.zone_base_fee_cents(p_zone_id UUID)
RETURNS INT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT base_fee_cents FROM public.delivery_zones WHERE id = p_zone_id AND is_active = true;
$$;

-- Patch create_delivery (Phase 3 behavior + zones + webhooks)
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

-- ---------------------------------------------------------------------------
-- API keys (hashed only)
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE OR REPLACE FUNCTION public.create_company_api_key(
  p_company_id UUID,
  p_name TEXT,
  p_permissions JSONB,
  p_expires_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_plain TEXT;
  v_prefix TEXT;
  v_hash TEXT;
  v_id UUID;
BEGIN
  IF NOT public.can_use_feature(p_company_id, 'api_access') THEN
    RAISE EXCEPTION 'api_not_enabled';
  END IF;

  IF NOT public.has_company_role(p_company_id, ARRAY['company_owner']::public.company_role[])
     AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  v_plain := 'dos_' || encode(gen_random_bytes(24), 'hex');
  v_prefix := substr(v_plain, 1, 12);
  v_hash := encode(digest(v_plain, 'sha256'), 'hex');

  INSERT INTO public.api_keys (
    company_id, name, key_prefix, hashed_key, permissions, expires_at, created_by
  ) VALUES (
    p_company_id, p_name, v_prefix, v_hash, COALESCE(p_permissions, '[]'::JSONB), p_expires_at, auth.uid()
  )
  RETURNING id INTO v_id;

  PERFORM public.log_audit_event(
    p_company_id, 'api_key_created', 'api_keys', v_id,
    jsonb_build_object('name', p_name, 'permissions', p_permissions)
  );

  RETURN jsonb_build_object(
    'id', v_id,
    'api_key', v_plain,
    'key_prefix', v_prefix,
    'message', 'Store this key securely; it cannot be retrieved again.'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_company_api_key TO authenticated;

CREATE OR REPLACE FUNCTION public.verify_api_key(p_api_key TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prefix TEXT;
  v_hash TEXT;
  v_row public.api_keys;
BEGIN
  IF p_api_key IS NULL OR length(p_api_key) < 16 THEN
    RETURN NULL;
  END IF;

  v_prefix := substr(p_api_key, 1, 12);
  v_hash := encode(digest(p_api_key, 'sha256'), 'hex');

  SELECT * INTO v_row
  FROM public.api_keys
  WHERE key_prefix = v_prefix
    AND hashed_key = v_hash
    AND is_active = true
    AND (expires_at IS NULL OR expires_at > now())
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  UPDATE public.api_keys SET last_used_at = now() WHERE id = v_row.id;

  RETURN jsonb_build_object(
    'company_id', v_row.company_id,
    'key_id', v_row.id,
    'permissions', v_row.permissions
  );
END;
$$;

REVOKE ALL ON FUNCTION public.verify_api_key FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.verify_api_key TO service_role;

CREATE OR REPLACE FUNCTION public.list_company_api_keys(p_company_id UUID)
RETURNS SETOF public.api_keys
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT k.*
  FROM public.api_keys k
  WHERE k.company_id = p_company_id
    AND (
      public.is_super_admin()
      OR public.has_company_role(p_company_id, ARRAY['company_owner']::public.company_role[])
    )
  ORDER BY k.created_at DESC;
$$;

GRANT EXECUTE ON FUNCTION public.list_company_api_keys TO authenticated;

CREATE OR REPLACE FUNCTION public.revoke_company_api_key(p_key_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.api_keys;
BEGIN
  SELECT * INTO v_row FROM public.api_keys WHERE id = p_key_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;

  IF NOT public.has_company_role(v_row.company_id, ARRAY['company_owner']::public.company_role[])
     AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE public.api_keys SET is_active = false, updated_at = now() WHERE id = p_key_id;
  PERFORM public.log_audit_event(
    v_row.company_id, 'api_key_revoked', 'api_keys', p_key_id, '{}'::JSONB
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.revoke_company_api_key TO authenticated;

-- ---------------------------------------------------------------------------
-- Webhooks
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.upsert_webhook_endpoint(p_payload JSONB)
RETURNS public.webhook_endpoints
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID := (p_payload ->> 'company_id')::UUID;
  v_id UUID := NULLIF(p_payload ->> 'id', '')::UUID;
  v_row public.webhook_endpoints;
  v_secret TEXT;
BEGIN
  IF NOT public.has_company_role(v_company_id, ARRAY['company_owner']::public.company_role[])
     AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  v_secret := COALESCE(p_payload ->> 'secret', encode(gen_random_bytes(32), 'hex'));

  IF v_id IS NULL THEN
    INSERT INTO public.webhook_endpoints (company_id, url, secret, events, is_active)
    VALUES (
      v_company_id,
      p_payload ->> 'url',
      v_secret,
      ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_payload -> 'events', '[]'::JSONB))),
      COALESCE((p_payload ->> 'is_active')::BOOLEAN, true)
    )
    RETURNING * INTO v_row;
  ELSE
    UPDATE public.webhook_endpoints SET
      url = COALESCE(p_payload ->> 'url', url),
      events = CASE
        WHEN p_payload ? 'events' THEN ARRAY(SELECT jsonb_array_elements_text(p_payload -> 'events'))
        ELSE events
      END,
      is_active = COALESCE((p_payload ->> 'is_active')::BOOLEAN, is_active)
    WHERE id = v_id AND company_id = v_company_id
    RETURNING * INTO v_row;
  END IF;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_webhook_endpoint TO authenticated;

CREATE OR REPLACE FUNCTION public.enqueue_webhook_event(
  p_company_id UUID,
  p_event_type TEXT,
  p_entity_id UUID,
  p_payload JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ep public.webhook_endpoints;
  v_body JSONB;
BEGIN
  v_body := jsonb_build_object(
    'event', p_event_type,
    'company_id', p_company_id,
    'entity_id', p_entity_id,
    'data', p_payload,
    'occurred_at', now()
  );

  FOR v_ep IN
    SELECT * FROM public.webhook_endpoints
    WHERE company_id = p_company_id
      AND is_active = true
      AND (cardinality(events) = 0 OR p_event_type = ANY (events))
  LOOP
    INSERT INTO public.webhook_deliveries (
      company_id, webhook_endpoint_id, event_type, payload, status, next_retry_at
    ) VALUES (
      p_company_id, v_ep.id, p_event_type, v_body, 'pending', now()
    );
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.enqueue_webhook_event FROM PUBLIC;

-- Patch delivery transition core (webhooks + existing SMS hooks)
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
  v_event TEXT;
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

-- payment.collected webhook when COD collected (trigger on payments)
CREATE OR REPLACE FUNCTION public.trg_payment_collected_webhook()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'collected' AND (OLD.status IS DISTINCT FROM NEW.status) THEN
    PERFORM public.enqueue_webhook_event(
      NEW.company_id, 'payment.collected', NEW.id, to_jsonb(NEW)
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS payment_collected_webhook ON public.payments;
CREATE TRIGGER payment_collected_webhook
  AFTER UPDATE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.trg_payment_collected_webhook();

-- assign_delivery_rider webhook (patch tail only via replace)
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
  PERFORM public.assert_company_operational(v_row.company_id);

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
    status = 'assigned', rider_id = p_rider_id, assigned_at = now()
  WHERE id = p_delivery_id
  RETURNING * INTO v_row;

  INSERT INTO public.delivery_status_history (
    delivery_id, company_id, from_status, to_status, changed_by, note
  ) VALUES (
    p_delivery_id, v_row.company_id, v_from, 'assigned', auth.uid(), 'rider assigned'
  );

  PERFORM public.notify_rider_new_job(v_row);
  PERFORM public.enqueue_webhook_event(v_row.company_id, 'delivery.assigned', v_row.id, to_jsonb(v_row));

  RETURN v_row;
END;
$$;

-- ---------------------------------------------------------------------------
-- SMS outbox (replace inline send in queue_outbound_sms)
-- ---------------------------------------------------------------------------
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
  IF NOT public.can_use_feature(p_company_id, 'sms_notifications') THEN
    RETURN false;
  END IF;

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

  INSERT INTO public.sms_outbox (company_id, phone, body, delivery_id, provider, status)
  VALUES (
    p_company_id, p_phone, p_body, p_delivery_id,
    COALESCE(current_setting('app.sms_provider', true), 'stub'),
    'pending'
  );

  INSERT INTO public.notification_logs (company_id, channel, recipient, body, status)
  VALUES (p_company_id, 'sms', p_phone, p_body, 'queued');

  RETURN true;
END;
$$;

-- ---------------------------------------------------------------------------
-- Analytics & rider performance
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_operational_analytics(
  p_company_id UUID,
  p_days INT DEFAULT 30
)
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
    OR (
      p_company_id IN (SELECT public.user_company_ids())
      AND public.can_use_feature(p_company_id, 'advanced_reports')
    )
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  RETURN jsonb_build_object(
    'period_days', p_days,
    'summary', (
      SELECT jsonb_build_object(
        'total', COUNT(*),
        'completed', COUNT(*) FILTER (WHERE status = 'delivered'),
        'failed', COUNT(*) FILTER (WHERE status = 'failed'),
        'completion_rate', CASE WHEN COUNT(*) = 0 THEN 0
          ELSE round(100.0 * COUNT(*) FILTER (WHERE status = 'delivered') / COUNT(*), 2) END,
        'failed_rate', CASE WHEN COUNT(*) = 0 THEN 0
          ELSE round(100.0 * COUNT(*) FILTER (WHERE status = 'failed') / COUNT(*), 2) END,
        'avg_delivery_minutes', round(
          (
            AVG(
              EXTRACT(EPOCH FROM (delivered_at - created_at)) / 60
            ) FILTER (
              WHERE status = 'delivered'
              AND delivered_at IS NOT NULL
            )
          )::NUMERIC,
          1
        ),
        'cod_outstanding_cents', COALESCE((
          SELECT SUM(p.amount_lrd_cents)
          FROM public.payments p
          WHERE p.company_id = p_company_id AND p.status IN ('pending', 'collected')
        ), 0)
      )
      FROM public.deliveries d
      WHERE d.company_id = p_company_id AND d.created_at >= v_since
    ),
    'by_zone', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'zone_id', z.id,
        'zone_name', z.name,
        'deliveries', cnt
      ) ORDER BY cnt DESC), '[]'::JSONB)
      FROM (
        SELECT delivery_zone_id, COUNT(*) AS cnt
        FROM public.deliveries
        WHERE company_id = p_company_id AND created_at >= v_since
        GROUP BY delivery_zone_id
      ) x
      LEFT JOIN public.delivery_zones z ON z.id = x.delivery_zone_id
    ),
    'busiest_hours', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'hour', hr,
        'deliveries', cnt
      ) ORDER BY cnt DESC), '[]'::JSONB)
      FROM (
        SELECT EXTRACT(HOUR FROM created_at AT TIME ZONE 'Africa/Monrovia')::INT AS hr, COUNT(*) AS cnt
        FROM public.deliveries
        WHERE company_id = p_company_id AND created_at >= v_since
        GROUP BY 1
        ORDER BY cnt DESC
        LIMIT 8
      ) h
    ),
    'volume_trend', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'day', day::DATE,
        'deliveries', cnt
      ) ORDER BY day), '[]'::JSONB)
      FROM (
        SELECT date_trunc('day', created_at AT TIME ZONE 'Africa/Monrovia') AS day, COUNT(*) AS cnt
        FROM public.deliveries
        WHERE company_id = p_company_id AND created_at >= v_since
        GROUP BY 1
      ) t
    ),
    'top_riders', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'rider_id', r.id,
        'rider_name', r.full_name,
        'completed', COUNT(*) FILTER (WHERE d.status = 'delivered')
      ) ORDER BY COUNT(*) FILTER (WHERE d.status = 'delivered') DESC), '[]'::JSONB)
      FROM public.deliveries d
      JOIN public.riders r ON r.id = d.rider_id
      WHERE d.company_id = p_company_id AND d.created_at >= v_since
      GROUP BY r.id, r.full_name
      LIMIT 10
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_operational_analytics TO authenticated;

CREATE OR REPLACE FUNCTION public.get_rider_performance_metrics(
  p_company_id UUID,
  p_days INT DEFAULT 30
)
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
    OR (
      p_company_id IN (SELECT public.user_company_ids())
      AND public.has_company_role(
        p_company_id,
        ARRAY['company_owner', 'dispatcher']::public.company_role[]
      )
    )
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'rider_id', r.id,
      'rider_name', r.full_name,
      'rider_code', r.rider_code,
      'completed', COUNT(*) FILTER (WHERE d.status = 'delivered'),
      'failed', COUNT(*) FILTER (WHERE d.status = 'failed'),
      'avg_delivery_minutes', round(
        (
          AVG(
            EXTRACT(EPOCH FROM (d.delivered_at - d.created_at)) / 60
          ) FILTER (
            WHERE d.status = 'delivered'
          )
        )::NUMERIC,
        1
      ),
      'cod_outstanding_cents', COALESCE((
        SELECT SUM(p.amount_lrd_cents)
        FROM public.payments p
        JOIN public.deliveries dd ON dd.id = p.delivery_id
        WHERE dd.rider_id = r.id AND p.status IN ('pending', 'collected')
      ), 0)
    ) ORDER BY COUNT(*) FILTER (WHERE d.status = 'delivered') DESC)
    FROM public.riders r
    LEFT JOIN public.deliveries d ON d.rider_id = r.id AND d.created_at >= v_since
    WHERE r.company_id = p_company_id
    GROUP BY r.id, r.full_name, r.rider_code
  ), '[]'::JSONB);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_rider_performance_metrics TO authenticated;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
ALTER TABLE public.rider_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rider_location_samples ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_zones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.api_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_endpoints ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sms_outbox ENABLE ROW LEVEL SECURITY;

CREATE POLICY rider_locations_select ON public.rider_locations
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR (
      company_id IN (SELECT public.user_company_ids())
      AND public.has_company_role(
        company_id,
        ARRAY['company_owner', 'dispatcher']::public.company_role[]
      )
      AND public.can_use_feature(company_id, 'gps_tracking')
    )
  );

CREATE POLICY delivery_zones_select ON public.delivery_zones
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR company_id IN (SELECT public.user_company_ids())
  );

CREATE POLICY delivery_zones_write ON public.delivery_zones
  FOR ALL TO authenticated
  USING (
    public.is_super_admin()
    OR public.has_company_role(
      company_id,
      ARRAY['company_owner', 'dispatcher']::public.company_role[]
    )
  )
  WITH CHECK (
    public.is_super_admin()
    OR public.has_company_role(
      company_id,
      ARRAY['company_owner', 'dispatcher']::public.company_role[]
    )
  );

CREATE POLICY api_keys_select ON public.api_keys
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR public.has_company_role(company_id, ARRAY['company_owner']::public.company_role[])
  );

CREATE POLICY webhook_endpoints_select ON public.webhook_endpoints
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR public.has_company_role(company_id, ARRAY['company_owner']::public.company_role[])
  );

CREATE POLICY webhook_deliveries_select ON public.webhook_deliveries
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR public.has_company_role(company_id, ARRAY['company_owner']::public.company_role[])
  );

CREATE POLICY sms_outbox_select ON public.sms_outbox
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR company_id IN (SELECT public.user_company_ids())
  );

-- No direct writes on rider_location_samples for clients (RPC only)
CREATE POLICY rider_location_samples_deny ON public.rider_location_samples
  FOR ALL TO authenticated
  USING (false);
