-- DeliveryOS · Phase 7: marketplace RPCs, RLS, analytics

-- ---------------------------------------------------------------------------
-- Patch can_use_feature (Phase 7)
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
-- Onboarding: business type
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_company_with_owner(
  p_name TEXT,
  p_phone TEXT,
  p_email TEXT,
  p_address TEXT DEFAULT NULL,
  p_business_type public.company_business_type DEFAULT 'logistics_provider'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_sub_id UUID;
  v_slug TEXT;
  v_type public.company_business_type := COALESCE(p_business_type, 'logistics_provider');
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  v_slug := lower(regexp_replace(trim(p_name), '[^a-zA-Z0-9]+', '-', 'g'));
  v_slug := trim(both '-' from v_slug);
  IF v_slug = '' THEN
    RAISE EXCEPTION 'invalid company name';
  END IF;

  SELECT id INTO v_sub_id FROM public.subscriptions WHERE slug = 'starter' LIMIT 1;

  INSERT INTO public.companies (name, slug, phone, email, address, subscription_id, business_type)
  VALUES (p_name, v_slug, p_phone, p_email, p_address, v_sub_id, v_type)
  RETURNING id INTO v_company_id;

  INSERT INTO public.company_users (company_id, user_id, role)
  VALUES (v_company_id, auth.uid(), 'company_owner');

  IF v_type IN ('logistics_provider', 'hybrid') THEN
    INSERT INTO public.provider_marketplace_profiles (company_id, marketplace_enabled, accepting_jobs)
    VALUES (v_company_id, false, false)
    ON CONFLICT (company_id) DO NOTHING;
  END IF;

  RETURN v_company_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- Marketplace helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assert_merchant_marketplace(p_company_id UUID)
RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type public.company_business_type;
BEGIN
  PERFORM public.assert_company_operational(p_company_id);
  IF NOT public.can_use_feature(p_company_id, 'marketplace_access')
     AND NOT public.can_use_feature(p_company_id, 'merchant_portal') THEN
    RAISE EXCEPTION 'marketplace_not_enabled';
  END IF;
  SELECT business_type INTO v_type FROM public.companies WHERE id = p_company_id;
  IF v_type NOT IN ('merchant', 'hybrid') THEN
    RAISE EXCEPTION 'not_a_merchant_company';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.companies c
    WHERE c.id = p_company_id AND c.marketplace_suspended = true
  ) THEN
    RAISE EXCEPTION 'marketplace_suspended';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.assert_provider_marketplace(p_company_id UUID)
RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type public.company_business_type;
  v_profile public.provider_marketplace_profiles;
BEGIN
  PERFORM public.assert_company_operational(p_company_id);
  IF NOT public.can_use_feature(p_company_id, 'provider_network') THEN
    RAISE EXCEPTION 'provider_network_not_enabled';
  END IF;
  SELECT business_type INTO v_type FROM public.companies WHERE id = p_company_id;
  IF v_type NOT IN ('logistics_provider', 'hybrid') THEN
    RAISE EXCEPTION 'not_a_provider_company';
  END IF;
  SELECT * INTO v_profile FROM public.provider_marketplace_profiles WHERE company_id = p_company_id;
  IF v_profile.company_id IS NULL OR NOT v_profile.marketplace_enabled OR v_profile.admin_marketplace_disabled THEN
    RAISE EXCEPTION 'marketplace_profile_not_enabled';
  END IF;
  IF NOT v_profile.accepting_jobs THEN
    RAISE EXCEPTION 'provider_not_accepting_jobs';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.compute_marketplace_fee_split(
  p_gross_lrd_cents INT,
  p_merchant_company_id UUID,
  p_provider_company_id UUID
)
RETURNS TABLE (
  platform_fee_lrd_cents INT,
  provider_amount_lrd_cents INT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rule public.marketplace_fee_rules;
  v_gross INT := GREATEST(COALESCE(p_gross_lrd_cents, 0), 0);
  v_fee INT := 0;
BEGIN
  SELECT * INTO v_rule
  FROM public.marketplace_fee_rules r
  WHERE r.is_active = true
    AND (
      r.applies_to_merchant_company_id = p_merchant_company_id
      OR r.applies_to_provider_company_id = p_provider_company_id
      OR r.is_platform_default = true
    )
  ORDER BY
    (r.applies_to_merchant_company_id IS NOT NULL)::INT DESC,
    (r.applies_to_provider_company_id IS NOT NULL)::INT DESC,
    r.is_platform_default DESC
  LIMIT 1;

  IF NOT FOUND THEN
    platform_fee_lrd_cents := 0;
    provider_amount_lrd_cents := v_gross;
    RETURN NEXT;
    RETURN;
  END IF;

  v_fee := CASE v_rule.fee_model
    WHEN 'fixed' THEN v_rule.fixed_fee_lrd_cents
    WHEN 'percentage' THEN (v_gross * v_rule.percentage_bps / 10000)::INT
    WHEN 'subscription_only' THEN 0
    WHEN 'zero_commission' THEN 0
    ELSE 0
  END;

  v_fee := LEAST(GREATEST(v_fee, 0), v_gross);
  platform_fee_lrd_cents := v_fee;
  provider_amount_lrd_cents := v_gross - v_fee;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.provider_matches_delivery_request(
  p_provider_company_id UUID,
  p_request public.delivery_requests
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.provider_marketplace_profiles p
    JOIN public.companies c ON c.id = p.company_id
    WHERE p.company_id = p_provider_company_id
      AND p.marketplace_enabled = true
      AND p.accepting_jobs = true
      AND p.admin_marketplace_disabled = false
      AND c.status = 'active'
      AND c.marketplace_suspended = false
      AND c.business_type IN ('logistics_provider', 'hybrid')
      AND public.can_use_feature(p.company_id, 'provider_network')
      AND (
        p_request.zone_id IS NULL
        OR EXISTS (
          SELECT 1 FROM public.provider_marketplace_zones pmz
          WHERE pmz.provider_company_id = p_provider_company_id
            AND pmz.delivery_zone_id = p_request.zone_id
        )
        OR p.service_regions = '[]'::JSONB
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.merchant_provider_relationships r
        WHERE r.merchant_company_id = p_request.merchant_company_id
          AND r.provider_company_id = p_provider_company_id
          AND r.relationship_type = 'blocked'
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.upsert_provider_marketplace_profile(p_payload JSONB)
RETURNS public.provider_marketplace_profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID := (p_payload ->> 'company_id')::UUID;
  v_row public.provider_marketplace_profiles;
BEGIN
  IF NOT public.has_company_role(v_company_id, ARRAY['company_owner']::public.company_role[])
     AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  INSERT INTO public.provider_marketplace_profiles (
    company_id, marketplace_enabled, service_description, service_phone, service_email,
    service_regions, accepting_jobs, minimum_delivery_fee_lrd_cents,
    maximum_service_distance_km, rating_visible, business_hours
  ) VALUES (
    v_company_id,
    COALESCE((p_payload ->> 'marketplace_enabled')::BOOLEAN, false),
    p_payload ->> 'service_description',
    p_payload ->> 'service_phone',
    p_payload ->> 'service_email',
    COALESCE(p_payload -> 'service_regions', '[]'::JSONB),
    COALESCE((p_payload ->> 'accepting_jobs')::BOOLEAN, false),
    COALESCE((p_payload ->> 'minimum_delivery_fee_lrd_cents')::INT, 0),
    NULLIF(p_payload ->> 'maximum_service_distance_km', '')::NUMERIC,
    COALESCE((p_payload ->> 'rating_visible')::BOOLEAN, true),
    COALESCE(p_payload -> 'business_hours', '{}'::JSONB)
  )
  ON CONFLICT (company_id) DO UPDATE SET
    marketplace_enabled = COALESCE((p_payload ->> 'marketplace_enabled')::BOOLEAN, provider_marketplace_profiles.marketplace_enabled),
    service_description = COALESCE(p_payload ->> 'service_description', provider_marketplace_profiles.service_description),
    service_phone = COALESCE(p_payload ->> 'service_phone', provider_marketplace_profiles.service_phone),
    service_email = COALESCE(p_payload ->> 'service_email', provider_marketplace_profiles.service_email),
    service_regions = COALESCE(p_payload -> 'service_regions', provider_marketplace_profiles.service_regions),
    accepting_jobs = COALESCE((p_payload ->> 'accepting_jobs')::BOOLEAN, provider_marketplace_profiles.accepting_jobs),
    minimum_delivery_fee_lrd_cents = COALESCE((p_payload ->> 'minimum_delivery_fee_lrd_cents')::INT, provider_marketplace_profiles.minimum_delivery_fee_lrd_cents),
    maximum_service_distance_km = COALESCE(NULLIF(p_payload ->> 'maximum_service_distance_km', '')::NUMERIC, provider_marketplace_profiles.maximum_service_distance_km),
    rating_visible = COALESCE((p_payload ->> 'rating_visible')::BOOLEAN, provider_marketplace_profiles.rating_visible),
    business_hours = COALESCE(p_payload -> 'business_hours', provider_marketplace_profiles.business_hours),
    updated_at = now()
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_provider_marketplace_profile TO authenticated;

CREATE OR REPLACE FUNCTION public.set_provider_marketplace_zones(
  p_company_id UUID,
  p_zone_ids UUID[]
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.has_company_role(p_company_id, ARRAY['company_owner']::public.company_role[])
     AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  DELETE FROM public.provider_marketplace_zones pmz
  WHERE pmz.provider_company_id = p_company_id
    AND (p_zone_ids IS NULL OR NOT (pmz.delivery_zone_id = ANY (p_zone_ids)));

  IF p_zone_ids IS NOT NULL THEN
    INSERT INTO public.provider_marketplace_zones (provider_company_id, delivery_zone_id)
    SELECT p_company_id, zid
    FROM unnest(p_zone_ids) AS zid
    WHERE EXISTS (
      SELECT 1 FROM public.delivery_zones dz
      WHERE dz.id = zid AND dz.company_id = p_company_id
    )
    ON CONFLICT DO NOTHING;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_provider_marketplace_zones TO authenticated;

CREATE OR REPLACE FUNCTION public.upsert_merchant_provider_relationship(p_payload JSONB)
RETURNS public.merchant_provider_relationships
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_merchant UUID := (p_payload ->> 'merchant_company_id')::UUID;
  v_provider UUID := (p_payload ->> 'provider_company_id')::UUID;
  v_row public.merchant_provider_relationships;
BEGIN
  PERFORM public.assert_merchant_marketplace(v_merchant);
  IF NOT public.has_company_role(v_merchant, ARRAY['company_owner', 'dispatcher']::public.company_role[])
     AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  INSERT INTO public.merchant_provider_relationships (
    merchant_company_id, provider_company_id, relationship_type, notes, created_by
  ) VALUES (
    v_merchant,
    v_provider,
    COALESCE((p_payload ->> 'relationship_type')::public.merchant_provider_relationship_type, 'marketplace'),
    p_payload ->> 'notes',
    auth.uid()
  )
  ON CONFLICT (merchant_company_id, provider_company_id) DO UPDATE SET
    relationship_type = EXCLUDED.relationship_type,
    notes = COALESCE(EXCLUDED.notes, merchant_provider_relationships.notes),
    updated_at = now()
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_merchant_provider_relationship TO authenticated;

-- ---------------------------------------------------------------------------
-- Delivery requests (merchant)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_delivery_request(p_payload JSONB)
RETURNS public.delivery_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_merchant UUID := (p_payload ->> 'merchant_company_id')::UUID;
  v_row public.delivery_requests;
  v_mode TEXT := COALESCE(p_payload ->> 'fulfillment_mode', 'external');
BEGIN
  PERFORM public.assert_merchant_marketplace(v_merchant);
  IF NOT public.has_company_role(v_merchant, ARRAY['company_owner', 'dispatcher']::public.company_role[])
     AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF v_mode = 'own_team' THEN
    IF (SELECT business_type FROM public.companies WHERE id = v_merchant) = 'merchant' THEN
      RAISE EXCEPTION 'merchant_cannot_use_own_team';
    END IF;
  END IF;

  INSERT INTO public.delivery_requests (
    merchant_company_id, pickup_branch_id, customer_id,
    pickup_address, pickup_latitude, pickup_longitude, pickup_area_summary,
    destination_address, destination_latitude, destination_longitude, destination_area_summary,
    zone_id, package_count, weight_kg, fragile,
    cod_amount_lrd_cents, delivery_notes, customer_name, customer_phone, package_description,
    status, selected_provider_id, quoted_amount_lrd_cents, expires_at, created_by
  ) VALUES (
    v_merchant,
    NULLIF(p_payload ->> 'pickup_branch_id', '')::UUID,
    NULLIF(p_payload ->> 'customer_id', '')::UUID,
    p_payload ->> 'pickup_address',
    NULLIF(p_payload ->> 'pickup_latitude', '')::DOUBLE PRECISION,
    NULLIF(p_payload ->> 'pickup_longitude', '')::DOUBLE PRECISION,
    p_payload ->> 'pickup_area_summary',
    p_payload ->> 'destination_address',
    NULLIF(p_payload ->> 'destination_latitude', '')::DOUBLE PRECISION,
    NULLIF(p_payload ->> 'destination_longitude', '')::DOUBLE PRECISION,
    p_payload ->> 'destination_area_summary',
    NULLIF(p_payload ->> 'zone_id', '')::UUID,
    COALESCE((p_payload ->> 'package_count')::INT, 1),
    NULLIF(p_payload ->> 'weight_kg', '')::NUMERIC,
    COALESCE((p_payload ->> 'fragile')::BOOLEAN, false),
    COALESCE((p_payload ->> 'cod_amount_lrd_cents')::INT, 0),
    p_payload ->> 'delivery_notes',
    p_payload ->> 'customer_name',
    p_payload ->> 'customer_phone',
    p_payload ->> 'package_description',
    COALESCE((p_payload ->> 'status')::public.delivery_request_status, 'draft'),
    NULLIF(p_payload ->> 'selected_provider_id', '')::UUID,
    NULLIF(p_payload ->> 'quoted_amount_lrd_cents', '')::INT,
    NULLIF(p_payload ->> 'expires_at', '')::TIMESTAMPTZ,
    auth.uid()
  )
  RETURNING * INTO v_row;

  PERFORM public.enqueue_webhook_event(
    v_merchant, 'delivery_request.created', v_row.id, to_jsonb(v_row)
  );
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_delivery_request TO authenticated;

CREATE OR REPLACE FUNCTION public.publish_delivery_request(
  p_request_id UUID,
  p_merchant_company_id UUID
)
RETURNS public.delivery_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req public.delivery_requests;
  v_provider UUID;
  v_quote INT;
  v_pref UUID;
BEGIN
  PERFORM public.assert_merchant_marketplace(p_merchant_company_id);
  IF NOT public.has_company_role(p_merchant_company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[]) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT * INTO v_req
  FROM public.delivery_requests dr
  WHERE dr.id = p_request_id AND dr.merchant_company_id = p_merchant_company_id
  FOR UPDATE;

  IF NOT FOUND OR v_req.status NOT IN ('draft', 'open') THEN
    RAISE EXCEPTION 'invalid_request_state';
  END IF;

  v_quote := COALESCE(v_req.quoted_amount_lrd_cents, 0);

  UPDATE public.delivery_requests SET
    status = 'open',
    requested_at = now(),
    expires_at = COALESCE(expires_at, now() + interval '24 hours')
  WHERE id = p_request_id
  RETURNING * INTO v_req;

  PERFORM public.enqueue_webhook_event(
    p_merchant_company_id, 'marketplace.request.created', v_req.id, to_jsonb(v_req)
  );

  SELECT provider_company_id INTO v_pref
  FROM public.merchant_provider_relationships
  WHERE merchant_company_id = p_merchant_company_id
    AND relationship_type = 'preferred'
  ORDER BY updated_at DESC
  LIMIT 1;

  IF v_req.selected_provider_id IS NOT NULL THEN
    IF public.provider_matches_delivery_request(v_req.selected_provider_id, v_req) THEN
      INSERT INTO public.delivery_offers (
        delivery_request_id, provider_company_id, quoted_amount_lrd_cents, expires_at
      ) VALUES (
        v_req.id, v_req.selected_provider_id, GREATEST(v_quote, 0), v_req.expires_at
      )
      ON CONFLICT (delivery_request_id, provider_company_id) DO NOTHING;
    END IF;
  ELSIF v_pref IS NOT NULL AND public.provider_matches_delivery_request(v_pref, v_req) THEN
    INSERT INTO public.delivery_offers (
      delivery_request_id, provider_company_id, quoted_amount_lrd_cents, expires_at
    ) VALUES (v_req.id, v_pref, GREATEST(v_quote, 0), v_req.expires_at)
    ON CONFLICT DO NOTHING;
  ELSE
    FOR v_provider IN
      SELECT c.id
      FROM public.companies c
      JOIN public.provider_marketplace_profiles p ON p.company_id = c.id
      WHERE c.business_type IN ('logistics_provider', 'hybrid')
        AND public.provider_matches_delivery_request(c.id, v_req)
      LIMIT 50
    LOOP
      INSERT INTO public.delivery_offers (
        delivery_request_id, provider_company_id, quoted_amount_lrd_cents, expires_at
      ) VALUES (
        v_req.id, v_provider, GREATEST(v_quote, 0), v_req.expires_at
      )
      ON CONFLICT DO NOTHING;

      PERFORM public.enqueue_webhook_event(
        v_provider, 'marketplace_job.available', v_req.id,
        jsonb_build_object('delivery_request_id', v_req.id, 'pickup_area', v_req.pickup_area_summary,
          'destination_area', v_req.destination_area_summary, 'quoted_amount_lrd_cents', GREATEST(v_quote, 0))
      );
    END LOOP;
  END IF;

  UPDATE public.delivery_requests SET status = 'offered' WHERE id = v_req.id AND status = 'open'
  RETURNING * INTO v_req;

  RETURN v_req;
END;
$$;

GRANT EXECUTE ON FUNCTION public.publish_delivery_request TO authenticated;

CREATE OR REPLACE FUNCTION public.accept_marketplace_offer(
  p_offer_id UUID,
  p_provider_company_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_offer public.delivery_offers;
  v_req public.delivery_requests;
  v_delivery public.deliveries;
  v_merchant_name TEXT;
  v_fee RECORD;
  v_tx public.marketplace_transactions;
BEGIN
  PERFORM public.assert_provider_marketplace(p_provider_company_id);
  IF NOT public.has_company_role(p_provider_company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[]) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT * INTO v_offer FROM public.delivery_offers
  WHERE id = p_offer_id AND provider_company_id = p_provider_company_id
  FOR UPDATE;

  IF NOT FOUND OR v_offer.status <> 'pending' THEN
    RAISE EXCEPTION 'invalid_offer';
  END IF;

  SELECT * INTO v_req FROM public.delivery_requests WHERE id = v_offer.delivery_request_id FOR UPDATE;
  IF v_req.status NOT IN ('open', 'offered') THEN
    RAISE EXCEPTION 'request_not_available';
  END IF;

  UPDATE public.delivery_offers SET
    status = 'accepted', accepted_at = now()
  WHERE id = p_offer_id;

  UPDATE public.delivery_offers SET status = 'expired'
  WHERE delivery_request_id = v_req.id AND id <> p_offer_id AND status = 'pending';

  UPDATE public.delivery_requests SET
    status = 'accepted',
    selected_provider_id = p_provider_company_id,
    quoted_amount_lrd_cents = v_offer.quoted_amount_lrd_cents,
    accepted_at = now()
  WHERE id = v_req.id
  RETURNING * INTO v_req;

  SELECT name INTO v_merchant_name FROM public.companies WHERE id = v_req.merchant_company_id;

  INSERT INTO public.deliveries (
    company_id, merchant_company_id, delivery_request_id,
    tracking_code, pickup_business_name, pickup_address,
    customer_id, customer_name, customer_phone, destination_address,
    package_description, amount_to_collect_lrd_cents, delivery_fee_lrd_cents,
    delivery_zone_id, status, created_by
  ) VALUES (
    p_provider_company_id, v_req.merchant_company_id, v_req.id,
    public.generate_tracking_code(),
    COALESCE(v_merchant_name, 'Merchant pickup'),
    v_req.pickup_address,
    v_req.customer_id,
    COALESCE(v_req.customer_name, 'Customer'),
    COALESCE(v_req.customer_phone, ''),
    v_req.destination_address,
    v_req.package_description,
    v_req.cod_amount_lrd_cents,
    v_offer.quoted_amount_lrd_cents,
    v_req.zone_id,
    'pending',
    auth.uid()
  )
  RETURNING * INTO v_delivery;

  UPDATE public.delivery_requests SET
    status = 'converted',
    converted_delivery_id = v_delivery.id
  WHERE id = v_req.id;

  SELECT * INTO v_fee FROM public.compute_marketplace_fee_split(
    v_offer.quoted_amount_lrd_cents, v_req.merchant_company_id, p_provider_company_id
  );

  INSERT INTO public.marketplace_transactions (
    delivery_request_id, merchant_company_id, provider_company_id, delivery_id,
    gross_amount_lrd_cents, platform_fee_lrd_cents, provider_amount_lrd_cents, status
  ) VALUES (
    v_req.id, v_req.merchant_company_id, p_provider_company_id, v_delivery.id,
    v_offer.quoted_amount_lrd_cents, v_fee.platform_fee_lrd_cents, v_fee.provider_amount_lrd_cents, 'pending'
  )
  RETURNING * INTO v_tx;

  INSERT INTO public.marketplace_ledger_entries (company_id, account_type, marketplace_transaction_id, amount_lrd_cents, description)
  VALUES
    (v_req.merchant_company_id, 'merchant_payable', v_tx.id, v_offer.quoted_amount_lrd_cents, 'Marketplace delivery accepted'),
    (p_provider_company_id, 'provider_receivable', v_tx.id, v_fee.provider_amount_lrd_cents, 'Provider earnings'),
    (NULL, 'platform_revenue', v_tx.id, v_fee.platform_fee_lrd_cents, 'Platform fee');

  PERFORM public.enqueue_webhook_event(
    v_req.merchant_company_id, 'delivery_request.accepted', v_req.id,
    jsonb_build_object('request', to_jsonb(v_req), 'delivery_id', v_delivery.id)
  );
  PERFORM public.enqueue_webhook_event(
    p_provider_company_id, 'marketplace_job.accepted', v_req.id,
    jsonb_build_object('delivery_id', v_delivery.id)
  );
  PERFORM public.enqueue_webhook_event(
    v_req.merchant_company_id, 'marketplace.offer.accepted', v_offer.id, to_jsonb(v_offer)
  );

  RETURN jsonb_build_object(
    'delivery_request', to_jsonb(v_req),
    'delivery', to_jsonb(v_delivery),
    'transaction', to_jsonb(v_tx)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.accept_marketplace_offer TO authenticated;

CREATE OR REPLACE FUNCTION public.cancel_delivery_request(
  p_request_id UUID,
  p_merchant_company_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS public.delivery_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req public.delivery_requests;
BEGIN
  PERFORM public.assert_merchant_marketplace(p_merchant_company_id);
  IF NOT public.has_company_role(p_merchant_company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[]) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT * INTO v_req FROM public.delivery_requests
  WHERE id = p_request_id AND merchant_company_id = p_merchant_company_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  IF v_req.status IN ('converted', 'cancelled') THEN
    RAISE EXCEPTION 'cannot_cancel';
  END IF;
  IF v_req.status = 'accepted' AND v_req.converted_delivery_id IS NOT NULL THEN
    RAISE EXCEPTION 'requires_manual_intervention';
  END IF;

  UPDATE public.delivery_offers SET status = 'withdrawn'
  WHERE delivery_request_id = v_req.id AND status = 'pending';

  UPDATE public.delivery_requests SET
    status = 'cancelled',
    cancellation_reason = p_reason,
    cancelled_at = now()
  WHERE id = v_req.id
  RETURNING * INTO v_req;

  PERFORM public.enqueue_webhook_event(
    p_merchant_company_id, 'delivery_request.cancelled', v_req.id, to_jsonb(v_req)
  );
  RETURN v_req;
END;
$$;

GRANT EXECUTE ON FUNCTION public.cancel_delivery_request TO authenticated;

CREATE OR REPLACE FUNCTION public.reject_marketplace_offer(
  p_offer_id UUID,
  p_provider_company_id UUID
)
RETURNS public.delivery_offers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_offer public.delivery_offers;
BEGIN
  PERFORM public.assert_provider_marketplace(p_provider_company_id);
  SELECT * INTO v_offer FROM public.delivery_offers
  WHERE id = p_offer_id AND provider_company_id = p_provider_company_id
  FOR UPDATE;
  IF NOT FOUND OR v_offer.status <> 'pending' THEN
    RAISE EXCEPTION 'invalid_offer';
  END IF;
  UPDATE public.delivery_offers SET status = 'rejected', rejected_at = now()
  WHERE id = p_offer_id
  RETURNING * INTO v_offer;

  PERFORM public.enqueue_webhook_event(
    p_provider_company_id, 'marketplace.offer.rejected', v_offer.id, to_jsonb(v_offer)
  );
  RETURN v_offer;
END;
$$;

GRANT EXECUTE ON FUNCTION public.reject_marketplace_offer TO authenticated;

-- Paginated lists
CREATE OR REPLACE FUNCTION public.list_delivery_requests_page(
  p_merchant_company_id UUID,
  p_status TEXT DEFAULT NULL,
  p_limit INT DEFAULT 25,
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
  IF NOT public.has_company_role(p_merchant_company_id, ARRAY['company_owner', 'dispatcher', 'support_staff']::public.company_role[])
     AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT COUNT(*) INTO v_total
  FROM public.delivery_requests dr
  WHERE dr.merchant_company_id = p_merchant_company_id
    AND (p_status IS NULL OR dr.status::TEXT = p_status);

  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::JSONB) INTO v_items
  FROM (
    SELECT dr.*
    FROM public.delivery_requests dr
    WHERE dr.merchant_company_id = p_merchant_company_id
      AND (p_status IS NULL OR dr.status::TEXT = p_status)
    ORDER BY dr.created_at DESC
    LIMIT LEAST(GREATEST(p_limit, 1), 100)
    OFFSET GREATEST(p_offset, 0)
  ) t;

  RETURN jsonb_build_object('items', v_items, 'total', v_total, 'limit', p_limit, 'offset', p_offset);
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_delivery_requests_page TO authenticated;

CREATE OR REPLACE FUNCTION public.list_marketplace_jobs_page(
  p_provider_company_id UUID,
  p_status TEXT DEFAULT 'pending',
  p_limit INT DEFAULT 25,
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
  IF NOT public.has_company_role(p_provider_company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[])
     AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT COUNT(*) INTO v_total
  FROM public.delivery_offers o
  WHERE o.provider_company_id = p_provider_company_id
    AND (p_status IS NULL OR o.status::TEXT = p_status);

  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::JSONB) INTO v_items
  FROM (
    SELECT
      o.id AS offer_id,
      o.status AS offer_status,
      o.quoted_amount_lrd_cents,
      o.offered_at,
      o.expires_at,
      dr.id AS delivery_request_id,
      dr.status AS request_status,
      dr.pickup_area_summary,
      dr.destination_area_summary,
      dr.package_count,
      dr.fragile,
      dr.cod_amount_lrd_cents,
      CASE WHEN o.status = 'accepted' THEN dr.pickup_address ELSE NULL END AS pickup_address,
      CASE WHEN o.status = 'accepted' THEN dr.destination_address ELSE NULL END AS destination_address,
      CASE WHEN o.status = 'accepted' THEN dr.customer_name ELSE NULL END AS customer_name,
      CASE WHEN o.status = 'accepted' THEN dr.customer_phone ELSE NULL END AS customer_phone
    FROM public.delivery_offers o
    JOIN public.delivery_requests dr ON dr.id = o.delivery_request_id
    WHERE o.provider_company_id = p_provider_company_id
      AND (p_status IS NULL OR o.status::TEXT = p_status)
    ORDER BY o.offered_at DESC
    LIMIT LEAST(GREATEST(p_limit, 1), 100)
    OFFSET GREATEST(p_offset, 0)
  ) t;

  RETURN jsonb_build_object('items', v_items, 'total', v_total, 'limit', p_limit, 'offset', p_offset);
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_marketplace_jobs_page TO authenticated;

CREATE OR REPLACE FUNCTION public.list_marketplace_providers_page(
  p_merchant_company_id UUID,
  p_limit INT DEFAULT 25,
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
  IF NOT public.has_company_role(p_merchant_company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[]) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT COUNT(*) INTO v_total
  FROM public.provider_marketplace_profiles p
  JOIN public.companies c ON c.id = p.company_id
  WHERE p.marketplace_enabled = true
    AND p.admin_marketplace_disabled = false
    AND c.status = 'active';

  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::JSONB) INTO v_items
  FROM (
    SELECT c.id, c.name, p.service_description, p.minimum_delivery_fee_lrd_cents, p.accepting_jobs,
      (
        SELECT ROUND(AVG(r.rating)::NUMERIC, 2)
        FROM public.provider_reviews r WHERE r.provider_company_id = c.id
      ) AS avg_rating
    FROM public.provider_marketplace_profiles p
    JOIN public.companies c ON c.id = p.company_id
    WHERE p.marketplace_enabled = true
      AND p.admin_marketplace_disabled = false
      AND c.status = 'active'
      AND NOT EXISTS (
        SELECT 1 FROM public.merchant_provider_relationships rel
        WHERE rel.merchant_company_id = p_merchant_company_id
          AND rel.provider_company_id = c.id
          AND rel.relationship_type = 'blocked'
      )
    ORDER BY c.name
    LIMIT LEAST(GREATEST(p_limit, 1), 100)
    OFFSET GREATEST(p_offset, 0)
  ) t;

  RETURN jsonb_build_object('items', v_items, 'total', v_total, 'limit', p_limit, 'offset', p_offset);
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_marketplace_providers_page TO authenticated;

-- Settlement (manual, idempotent)
CREATE OR REPLACE FUNCTION public.record_marketplace_settlement(p_payload JSONB)
RETURNS public.marketplace_settlements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tx_id UUID := (p_payload ->> 'marketplace_transaction_id')::UUID;
  v_tx public.marketplace_transactions;
  v_row public.marketplace_settlements;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT * INTO v_tx FROM public.marketplace_transactions WHERE id = v_tx_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'transaction_not_found'; END IF;
  IF v_tx.status = 'settled' THEN
    RAISE EXCEPTION 'already_settled';
  END IF;

  INSERT INTO public.marketplace_settlements (
    marketplace_transaction_id,
    merchant_paid_platform,
    platform_paid_provider,
    provider_collected_cod,
    net_settlement_notes,
    recorded_by
  ) VALUES (
    v_tx_id,
    COALESCE((p_payload ->> 'merchant_paid_platform')::BOOLEAN, false),
    COALESCE((p_payload ->> 'platform_paid_provider')::BOOLEAN, false),
    COALESCE((p_payload ->> 'provider_collected_cod')::BOOLEAN, false),
    p_payload ->> 'net_settlement_notes',
    auth.uid()
  )
  RETURNING * INTO v_row;

  UPDATE public.marketplace_transactions SET
    status = 'settled',
    settled_at = now(),
    settlement_id = v_row.id
  WHERE id = v_tx_id;

  PERFORM public.enqueue_webhook_event(
    v_tx.merchant_company_id, 'marketplace.payment.recorded', v_tx.id, to_jsonb(v_row)
  );

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_marketplace_settlement TO authenticated;

CREATE OR REPLACE FUNCTION public.create_provider_review(p_payload JSONB)
RETURNS public.provider_reviews
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_merchant UUID := (p_payload ->> 'merchant_company_id')::UUID;
  v_delivery UUID := (p_payload ->> 'delivery_id')::UUID;
  v_row public.provider_reviews;
  v_del public.deliveries;
BEGIN
  IF NOT public.has_company_role(v_merchant, ARRAY['company_owner', 'dispatcher']::public.company_role[]) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT * INTO v_del FROM public.deliveries
  WHERE id = v_delivery AND merchant_company_id = v_merchant AND status = 'delivered';

  IF NOT FOUND OR v_del.delivery_request_id IS NULL THEN
    RAISE EXCEPTION 'delivery_not_reviewable';
  END IF;

  INSERT INTO public.provider_reviews (
    merchant_company_id, provider_company_id, delivery_id, delivery_request_id,
    rating, comment, created_by
  ) VALUES (
    v_merchant, v_del.company_id, v_delivery, v_del.delivery_request_id,
    (p_payload ->> 'rating')::SMALLINT,
    p_payload ->> 'comment',
    auth.uid()
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_provider_review TO authenticated;

CREATE OR REPLACE FUNCTION public.create_marketplace_dispute(p_payload JSONB)
RETURNS public.marketplace_disputes
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_merchant UUID := (p_payload ->> 'merchant_company_id')::UUID;
  v_req UUID := (p_payload ->> 'delivery_request_id')::UUID;
  v_row public.marketplace_disputes;
  v_req_row public.delivery_requests;
BEGIN
  IF NOT public.has_company_role(v_merchant, ARRAY['company_owner', 'dispatcher']::public.company_role[]) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT * INTO v_req_row FROM public.delivery_requests
  WHERE id = v_req AND merchant_company_id = v_merchant;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;

  INSERT INTO public.marketplace_disputes (
    delivery_request_id, marketplace_transaction_id,
    merchant_company_id, provider_company_id,
    reason, description, created_by
  ) VALUES (
    v_req,
    (SELECT id FROM public.marketplace_transactions WHERE delivery_request_id = v_req LIMIT 1),
    v_merchant,
    COALESCE(v_req_row.selected_provider_id, (p_payload ->> 'provider_company_id')::UUID),
    (p_payload ->> 'reason')::public.marketplace_dispute_reason,
    p_payload ->> 'description',
    auth.uid()
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_marketplace_dispute TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_marketplace_suspension(
  p_company_id UUID,
  p_suspended BOOLEAN,
  p_disable_provider BOOLEAN DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  UPDATE public.companies SET marketplace_suspended = COALESCE(p_suspended, false)
  WHERE id = p_company_id;

  IF p_disable_provider IS NOT NULL THEN
    UPDATE public.provider_marketplace_profiles SET admin_marketplace_disabled = p_disable_provider
    WHERE company_id = p_company_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_set_marketplace_suspension TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_upsert_marketplace_fee_rule(p_payload JSONB)
RETURNS public.marketplace_fee_rules
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.marketplace_fee_rules;
  v_id UUID := NULLIF(p_payload ->> 'id', '')::UUID;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  IF COALESCE((p_payload ->> 'is_platform_default')::BOOLEAN, false) THEN
    UPDATE public.marketplace_fee_rules SET is_platform_default = false WHERE is_platform_default = true;
  END IF;

  IF v_id IS NULL THEN
    INSERT INTO public.marketplace_fee_rules (
      name, fee_model, fixed_fee_lrd_cents, percentage_bps, is_active, is_platform_default,
      applies_to_merchant_company_id, applies_to_provider_company_id, created_by
    ) VALUES (
      p_payload ->> 'name',
      COALESCE((p_payload ->> 'fee_model')::public.marketplace_fee_model, 'percentage'),
      COALESCE((p_payload ->> 'fixed_fee_lrd_cents')::INT, 0),
      COALESCE((p_payload ->> 'percentage_bps')::INT, 0),
      COALESCE((p_payload ->> 'is_active')::BOOLEAN, true),
      COALESCE((p_payload ->> 'is_platform_default')::BOOLEAN, false),
      NULLIF(p_payload ->> 'applies_to_merchant_company_id', '')::UUID,
      NULLIF(p_payload ->> 'applies_to_provider_company_id', '')::UUID,
      auth.uid()
    )
    RETURNING * INTO v_row;
  ELSE
    UPDATE public.marketplace_fee_rules SET
      name = COALESCE(p_payload ->> 'name', name),
      fee_model = COALESCE((p_payload ->> 'fee_model')::public.marketplace_fee_model, fee_model),
      fixed_fee_lrd_cents = COALESCE((p_payload ->> 'fixed_fee_lrd_cents')::INT, fixed_fee_lrd_cents),
      percentage_bps = COALESCE((p_payload ->> 'percentage_bps')::INT, percentage_bps),
      is_active = COALESCE((p_payload ->> 'is_active')::BOOLEAN, is_active),
      is_platform_default = COALESCE((p_payload ->> 'is_platform_default')::BOOLEAN, is_platform_default)
    WHERE id = v_id
    RETURNING * INTO v_row;
  END IF;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_upsert_marketplace_fee_rule TO authenticated;

CREATE OR REPLACE FUNCTION public.get_marketplace_analytics(
  p_company_id UUID DEFAULT NULL,
  p_scope TEXT DEFAULT 'platform'
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gmv BIGINT;
  v_fees BIGINT;
  v_completed BIGINT;
  v_open BIGINT;
  v_cancelled BIGINT;
  v_accepted BIGINT;
BEGIN
  IF p_scope = 'platform' AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF p_scope = 'merchant' THEN
    PERFORM public.assert_merchant_marketplace(p_company_id);
    SELECT COALESCE(SUM(gross_amount_lrd_cents), 0) INTO v_gmv
    FROM public.marketplace_transactions WHERE merchant_company_id = p_company_id;
    SELECT COALESCE(SUM(platform_fee_lrd_cents), 0) INTO v_fees
    FROM public.marketplace_transactions WHERE merchant_company_id = p_company_id;
  ELSIF p_scope = 'provider' THEN
    IF NOT public.has_company_role(p_company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[]) THEN
      RAISE EXCEPTION 'forbidden';
    END IF;
    SELECT COALESCE(SUM(provider_amount_lrd_cents), 0) INTO v_gmv
    FROM public.marketplace_transactions WHERE provider_company_id = p_company_id;
    SELECT COALESCE(SUM(platform_fee_lrd_cents), 0) INTO v_fees
    FROM public.marketplace_transactions WHERE provider_company_id = p_company_id;
  ELSE
    SELECT COALESCE(SUM(gross_amount_lrd_cents), 0) INTO v_gmv FROM public.marketplace_transactions;
    SELECT COALESCE(SUM(platform_fee_lrd_cents), 0) INTO v_fees FROM public.marketplace_transactions;
  END IF;

  SELECT COUNT(*) INTO v_completed
  FROM public.delivery_requests dr
  WHERE dr.status = 'converted'
    AND (p_scope <> 'merchant' OR dr.merchant_company_id = p_company_id)
    AND (p_scope <> 'provider' OR dr.selected_provider_id = p_company_id);

  SELECT COUNT(*) INTO v_open
  FROM public.delivery_requests dr
  WHERE dr.status IN ('open', 'offered')
    AND (p_scope <> 'merchant' OR dr.merchant_company_id = p_company_id);

  SELECT COUNT(*) INTO v_cancelled
  FROM public.delivery_requests dr
  WHERE dr.status = 'cancelled'
    AND (p_scope <> 'merchant' OR dr.merchant_company_id = p_company_id);

  SELECT COUNT(*) INTO v_accepted
  FROM public.delivery_requests dr
  WHERE dr.status IN ('accepted', 'converted')
    AND (p_scope <> 'merchant' OR dr.merchant_company_id = p_company_id)
    AND (p_scope <> 'provider' OR dr.selected_provider_id = p_company_id);

  RETURN jsonb_build_object(
    'gmv_lrd_cents', v_gmv,
    'platform_fees_lrd_cents', v_fees,
    'completed_conversions', v_completed,
    'open_requests', v_open,
    'cancelled_requests', v_cancelled,
    'accepted_requests', v_accepted,
    'acceptance_rate',
      CASE WHEN (v_accepted + v_cancelled) > 0
        THEN ROUND(v_accepted::NUMERIC / (v_accepted + v_cancelled), 4)
        ELSE NULL END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_marketplace_analytics TO authenticated;

-- Patch admin_upsert_plan Phase 7 flags
CREATE OR REPLACE FUNCTION public.admin_upsert_plan(p_payload JSONB)
RETURNS public.subscriptions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.subscriptions;
  v_id UUID := (p_payload ->> 'id')::UUID;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  IF v_id IS NULL THEN
    INSERT INTO public.subscriptions (
      slug, name, max_riders, max_deliveries_per_month, price_lrd_cents, currency,
      monthly_sms_allowance, proof_of_delivery, advanced_reports, api_access,
      gps_tracking, custom_branding, is_active, features,
      multi_branch, fleet_management, inventory, warehouse_management,
      cod_reconciliation, profitability_reports,
      marketplace_access, merchant_portal, provider_network, marketplace_api
    ) VALUES (
      p_payload ->> 'slug', p_payload ->> 'name',
      (p_payload ->> 'max_riders')::INT,
      NULLIF(p_payload ->> 'max_deliveries_per_month', '')::INT,
      (p_payload ->> 'price_lrd_cents')::INT,
      COALESCE(p_payload ->> 'currency', 'LRD'),
      COALESCE((p_payload ->> 'monthly_sms_allowance')::INT, 0),
      COALESCE((p_payload ->> 'proof_of_delivery')::BOOLEAN, true),
      COALESCE((p_payload ->> 'advanced_reports')::BOOLEAN, false),
      COALESCE((p_payload ->> 'api_access')::BOOLEAN, false),
      COALESCE((p_payload ->> 'gps_tracking')::BOOLEAN, false),
      COALESCE((p_payload ->> 'custom_branding')::BOOLEAN, false),
      COALESCE((p_payload ->> 'is_active')::BOOLEAN, true),
      COALESCE(p_payload -> 'features', '{}'::JSONB),
      COALESCE((p_payload ->> 'multi_branch')::BOOLEAN, false),
      COALESCE((p_payload ->> 'fleet_management')::BOOLEAN, false),
      COALESCE((p_payload ->> 'inventory')::BOOLEAN, false),
      COALESCE((p_payload ->> 'warehouse_management')::BOOLEAN, false),
      COALESCE((p_payload ->> 'cod_reconciliation')::BOOLEAN, false),
      COALESCE((p_payload ->> 'profitability_reports')::BOOLEAN, false),
      COALESCE((p_payload ->> 'marketplace_access')::BOOLEAN, false),
      COALESCE((p_payload ->> 'merchant_portal')::BOOLEAN, false),
      COALESCE((p_payload ->> 'provider_network')::BOOLEAN, false),
      COALESCE((p_payload ->> 'marketplace_api')::BOOLEAN, false)
    )
    RETURNING * INTO v_row;
  ELSE
    UPDATE public.subscriptions SET
      slug = COALESCE(p_payload ->> 'slug', slug),
      name = COALESCE(p_payload ->> 'name', name),
      max_riders = COALESCE((p_payload ->> 'max_riders')::INT, max_riders),
      max_deliveries_per_month = CASE
        WHEN p_payload ? 'max_deliveries_per_month' THEN NULLIF(p_payload ->> 'max_deliveries_per_month', '')::INT
        ELSE max_deliveries_per_month
      END,
      price_lrd_cents = COALESCE((p_payload ->> 'price_lrd_cents')::INT, price_lrd_cents),
      multi_branch = COALESCE((p_payload ->> 'multi_branch')::BOOLEAN, multi_branch),
      fleet_management = COALESCE((p_payload ->> 'fleet_management')::BOOLEAN, fleet_management),
      inventory = COALESCE((p_payload ->> 'inventory')::BOOLEAN, inventory),
      warehouse_management = COALESCE((p_payload ->> 'warehouse_management')::BOOLEAN, warehouse_management),
      cod_reconciliation = COALESCE((p_payload ->> 'cod_reconciliation')::BOOLEAN, cod_reconciliation),
      profitability_reports = COALESCE((p_payload ->> 'profitability_reports')::BOOLEAN, profitability_reports),
      marketplace_access = COALESCE((p_payload ->> 'marketplace_access')::BOOLEAN, marketplace_access),
      merchant_portal = COALESCE((p_payload ->> 'merchant_portal')::BOOLEAN, merchant_portal),
      provider_network = COALESCE((p_payload ->> 'provider_network')::BOOLEAN, provider_network),
      marketplace_api = COALESCE((p_payload ->> 'marketplace_api')::BOOLEAN, marketplace_api),
      is_active = COALESCE((p_payload ->> 'is_active')::BOOLEAN, is_active)
    WHERE id = v_id
    RETURNING * INTO v_row;
  END IF;

  PERFORM public.log_audit_event(NULL, 'plan_upserted', 'subscriptions', v_row.id, to_jsonb(v_row));
  RETURN v_row;
END;
$$;

-- ---------------------------------------------------------------------------
-- RLS policies (tenant isolation)
-- ---------------------------------------------------------------------------
CREATE POLICY provider_marketplace_profiles_select ON public.provider_marketplace_profiles
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR company_id IN (SELECT public.user_company_ids())
    OR (marketplace_enabled = true AND admin_marketplace_disabled = false)
  );

CREATE POLICY provider_marketplace_profiles_write ON public.provider_marketplace_profiles
  FOR ALL TO authenticated
  USING (
    public.is_super_admin()
    OR public.has_company_role(company_id, ARRAY['company_owner']::public.company_role[])
  )
  WITH CHECK (
    public.is_super_admin()
    OR public.has_company_role(company_id, ARRAY['company_owner']::public.company_role[])
  );

CREATE POLICY provider_marketplace_zones_tenant ON public.provider_marketplace_zones
  FOR ALL TO authenticated
  USING (
    public.is_super_admin()
    OR provider_company_id IN (SELECT public.user_company_ids())
  )
  WITH CHECK (
    public.is_super_admin()
    OR public.has_company_role(provider_company_id, ARRAY['company_owner']::public.company_role[])
  );

CREATE POLICY delivery_requests_merchant ON public.delivery_requests
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR merchant_company_id IN (SELECT public.user_company_ids())
    OR selected_provider_id IN (SELECT public.user_company_ids())
  );

CREATE POLICY delivery_requests_merchant_write ON public.delivery_requests
  FOR INSERT TO authenticated
  WITH CHECK (merchant_company_id IN (SELECT public.user_company_ids()));

CREATE POLICY delivery_offers_provider ON public.delivery_offers
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR provider_company_id IN (SELECT public.user_company_ids())
    OR delivery_request_id IN (
      SELECT id FROM public.delivery_requests
      WHERE merchant_company_id IN (SELECT public.user_company_ids())
    )
  );

CREATE POLICY merchant_provider_relationships_tenant ON public.merchant_provider_relationships
  FOR ALL TO authenticated
  USING (
    public.is_super_admin()
    OR merchant_company_id IN (SELECT public.user_company_ids())
  )
  WITH CHECK (merchant_company_id IN (SELECT public.user_company_ids()));

CREATE POLICY marketplace_fee_rules_read ON public.marketplace_fee_rules
  FOR SELECT TO authenticated
  USING (public.is_super_admin() OR is_active = true);

CREATE POLICY marketplace_fee_rules_admin ON public.marketplace_fee_rules
  FOR ALL TO authenticated
  USING (public.is_super_admin())
  WITH CHECK (public.is_super_admin());

CREATE POLICY marketplace_transactions_tenant ON public.marketplace_transactions
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR merchant_company_id IN (SELECT public.user_company_ids())
    OR provider_company_id IN (SELECT public.user_company_ids())
  );

CREATE POLICY marketplace_ledger_tenant ON public.marketplace_ledger_entries
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR company_id IN (SELECT public.user_company_ids())
    OR company_id IS NULL AND public.is_super_admin()
  );

CREATE POLICY marketplace_settlements_admin ON public.marketplace_settlements
  FOR SELECT TO authenticated
  USING (public.is_super_admin());

CREATE POLICY provider_reviews_read ON public.provider_reviews
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR merchant_company_id IN (SELECT public.user_company_ids())
    OR provider_company_id IN (SELECT public.user_company_ids())
  );

CREATE POLICY provider_reviews_insert ON public.provider_reviews
  FOR INSERT TO authenticated
  WITH CHECK (merchant_company_id IN (SELECT public.user_company_ids()));

CREATE POLICY marketplace_disputes_tenant ON public.marketplace_disputes
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR merchant_company_id IN (SELECT public.user_company_ids())
    OR provider_company_id IN (SELECT public.user_company_ids())
  );

CREATE POLICY marketplace_disputes_insert ON public.marketplace_disputes
  FOR INSERT TO authenticated
  WITH CHECK (merchant_company_id IN (SELECT public.user_company_ids()));

-- Merchant read own marketplace deliveries via deliveries RLS already scoped by company_id;
-- add policy patch for merchant_company_id visibility
CREATE POLICY deliveries_merchant_marketplace_read ON public.deliveries
  FOR SELECT TO authenticated
  USING (
    merchant_company_id IN (SELECT public.user_company_ids())
  );
