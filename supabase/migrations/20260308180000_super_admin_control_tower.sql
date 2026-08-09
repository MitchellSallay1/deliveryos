-- DeliveryOS · Super Admin control tower RPCs (platform operators only)

-- ---------------------------------------------------------------------------
-- Command center KPIs (real aggregates + day-over-day where applicable)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_platform_command_center()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today_start TIMESTAMPTZ;
  v_yesterday_start TIMESTAMPTZ;
  v_deliveries_today INT;
  v_deliveries_yesterday INT;
  v_sms_today INT;
  v_sms_yesterday INT;
  v_api_today INT;
  v_api_yesterday INT;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  v_today_start := date_trunc('day', (current_timestamp AT TIME ZONE 'Africa/Monrovia'))
    AT TIME ZONE 'Africa/Monrovia';
  v_yesterday_start := v_today_start - interval '1 day';

  SELECT COUNT(*)::INT INTO v_deliveries_today
  FROM public.deliveries d WHERE d.created_at >= v_today_start;

  SELECT COUNT(*)::INT INTO v_deliveries_yesterday
  FROM public.deliveries d
  WHERE d.created_at >= v_yesterday_start AND d.created_at < v_today_start;

  SELECT COUNT(*)::INT INTO v_sms_today
  FROM public.sms_logs
  WHERE direction = 'outbound' AND created_at >= v_today_start;

  SELECT COUNT(*)::INT INTO v_sms_yesterday
  FROM public.sms_logs
  WHERE direction = 'outbound'
    AND created_at >= v_yesterday_start AND created_at < v_today_start;

  SELECT COUNT(*)::INT INTO v_api_today
  FROM public.api_auth_events WHERE created_at >= v_today_start;

  SELECT COUNT(*)::INT INTO v_api_yesterday
  FROM public.api_auth_events
  WHERE created_at >= v_yesterday_start AND created_at < v_today_start;

  RETURN jsonb_build_object(
    'companies_total', (SELECT COUNT(*)::INT FROM public.companies),
    'companies_active', (SELECT COUNT(*)::INT FROM public.companies WHERE status = 'active'),
    'companies_pending', (SELECT COUNT(*)::INT FROM public.companies WHERE status = 'pending'),
    'companies_suspended', (SELECT COUNT(*)::INT FROM public.companies WHERE status = 'suspended'),
    'logistics_providers', (
      SELECT COUNT(*)::INT FROM public.companies
      WHERE business_type IN ('logistics_provider', 'hybrid')
    ),
    'merchants', (
      SELECT COUNT(*)::INT FROM public.companies
      WHERE business_type IN ('merchant', 'hybrid')
    ),
    'riders_total', (SELECT COUNT(*)::INT FROM public.riders),
    'riders_active', (
      SELECT COUNT(*)::INT FROM public.riders WHERE status IN ('available', 'busy')
    ),
    'deliveries_today', v_deliveries_today,
    'deliveries_yesterday', v_deliveries_yesterday,
    'deliveries_in_transit', (
      SELECT COUNT(*)::INT FROM public.deliveries
      WHERE status IN ('assigned', 'accepted', 'picked_up', 'in_transit')
    ),
    'deliveries_completed_today', (
      SELECT COUNT(*)::INT FROM public.deliveries
      WHERE status = 'delivered' AND delivered_at >= v_today_start
    ),
    'deliveries_failed_today', (
      SELECT COUNT(*)::INT FROM public.deliveries
      WHERE status = 'failed' AND failed_at >= v_today_start
    ),
    'marketplace_requests_today', (
      SELECT COUNT(*)::INT FROM public.delivery_requests WHERE created_at >= v_today_start
    ),
    'marketplace_gmv_lrd_cents', (
      SELECT COALESCE(SUM(gross_amount_lrd_cents), 0)::BIGINT FROM public.marketplace_transactions
    ),
    'subscription_mrr_estimate_cents', (
      SELECT COALESCE(SUM(s.price_lrd_cents), 0)::BIGINT
      FROM public.company_subscriptions cs
      JOIN public.subscriptions s ON s.id = cs.plan_id
      WHERE cs.status IN ('active', 'past_due')
    ),
    'cod_outstanding_lrd_cents', (
      SELECT COALESCE(SUM(p.amount_lrd_cents), 0)::BIGINT
      FROM public.payments p
      WHERE p.status IN ('pending', 'collected')
    ),
    'sms_sent_today', v_sms_today,
    'sms_sent_yesterday', v_sms_yesterday,
    'api_requests_today', v_api_today,
    'api_requests_yesterday', v_api_yesterday,
    'checked_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_platform_command_center TO authenticated;

-- Backward-compatible alias
CREATE OR REPLACE FUNCTION public.get_platform_analytics()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v JSONB;
BEGIN
  v := public.get_platform_command_center();
  RETURN jsonb_build_object(
    'companies_total', v -> 'companies_total',
    'companies_active', v -> 'companies_active',
    'companies_pending', v -> 'companies_pending',
    'deliveries_today', v -> 'deliveries_today',
    'sms_sent', (SELECT COUNT(*)::INT FROM public.sms_logs WHERE direction = 'outbound')
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- Live snapshot (polling-friendly, bounded counts)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_platform_live_snapshot()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  RETURN jsonb_build_object(
    'deliveries', jsonb_build_object(
      'active', (SELECT COUNT(*)::INT FROM public.deliveries WHERE status NOT IN ('delivered', 'failed', 'cancelled')),
      'assigned', (SELECT COUNT(*)::INT FROM public.deliveries WHERE status = 'assigned'),
      'picked_up', (SELECT COUNT(*)::INT FROM public.deliveries WHERE status = 'picked_up'),
      'in_transit', (SELECT COUNT(*)::INT FROM public.deliveries WHERE status = 'in_transit'),
      'failed', (SELECT COUNT(*)::INT FROM public.deliveries WHERE status = 'failed')
    ),
    'riders', jsonb_build_object(
      'available', (SELECT COUNT(*)::INT FROM public.riders WHERE status = 'available'),
      'busy', (SELECT COUNT(*)::INT FROM public.riders WHERE status = 'busy'),
      'offline', (SELECT COUNT(*)::INT FROM public.riders WHERE status = 'offline')
    ),
    'marketplace', jsonb_build_object(
      'open_requests', (SELECT COUNT(*)::INT FROM public.delivery_requests WHERE status = 'open'),
      'pending_offers', (SELECT COUNT(*)::INT FROM public.delivery_requests WHERE status = 'offered'),
      'accepted', (SELECT COUNT(*)::INT FROM public.delivery_requests WHERE status = 'accepted')
    ),
    'communications', jsonb_build_object(
      'sms_pending', (SELECT COUNT(*)::INT FROM public.sms_outbox WHERE status IN ('pending', 'processing')),
      'sms_failed', (SELECT COUNT(*)::INT FROM public.sms_outbox WHERE status = 'failed'),
      'webhook_failed', (SELECT COUNT(*)::INT FROM public.webhook_deliveries WHERE status IN ('failed', 'dead')),
      'email_pending', (SELECT COUNT(*)::INT FROM public.email_outbox WHERE status IN ('pending', 'failed'))
    ),
    'checked_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_platform_live_snapshot TO authenticated;

-- ---------------------------------------------------------------------------
-- Network performance (aggregates for date range)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_platform_network_metrics(p_days INT DEFAULT 7)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_since TIMESTAMPTZ := now() - make_interval(days => GREATEST(LEAST(p_days, 90), 1));
  v_total INT;
  v_completed INT;
  v_failed INT;
  v_avg_mins NUMERIC;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT COUNT(*)::INT INTO v_total FROM public.deliveries WHERE created_at >= v_since;
  SELECT COUNT(*)::INT INTO v_completed
  FROM public.deliveries WHERE created_at >= v_since AND status = 'delivered';
  SELECT COUNT(*)::INT INTO v_failed
  FROM public.deliveries WHERE created_at >= v_since AND status = 'failed';

  SELECT ROUND(AVG(EXTRACT(EPOCH FROM (delivered_at - created_at)) / 60.0)::NUMERIC, 1) INTO v_avg_mins
  FROM public.deliveries
  WHERE created_at >= v_since AND status = 'delivered' AND delivered_at IS NOT NULL;

  RETURN jsonb_build_object(
    'period_days', p_days,
    'delivery_volume', v_total,
    'completion_rate', CASE WHEN v_total > 0 THEN ROUND(v_completed::NUMERIC / v_total, 4) ELSE NULL END,
    'failed_rate', CASE WHEN v_total > 0 THEN ROUND(v_failed::NUMERIC / v_total, 4) ELSE NULL END,
    'avg_delivery_minutes', v_avg_mins,
    'active_companies', (
      SELECT COUNT(DISTINCT company_id)::INT FROM public.deliveries WHERE created_at >= v_since
    ),
    'active_riders', (
      SELECT COUNT(DISTINCT rider_id)::INT FROM public.deliveries
      WHERE created_at >= v_since AND rider_id IS NOT NULL
    ),
    'top_companies', (
      SELECT COALESCE(jsonb_agg(row_to_json(t)), '[]'::JSONB)
      FROM (
        SELECT c.id, c.name, COUNT(*)::INT AS deliveries
        FROM public.deliveries d
        JOIN public.companies c ON c.id = d.company_id
        WHERE d.created_at >= v_since
        GROUP BY c.id, c.name
        ORDER BY deliveries DESC
        LIMIT 10
      ) t
    ),
    'marketplace_acceptance_rate', (
      SELECT CASE WHEN (a + c) > 0 THEN ROUND(a::NUMERIC / (a + c), 4) ELSE NULL END
      FROM (
        SELECT
          COUNT(*) FILTER (WHERE status IN ('accepted', 'converted')) AS a,
          COUNT(*) FILTER (WHERE status = 'cancelled') AS c
        FROM public.delivery_requests
        WHERE created_at >= v_since
      ) q
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_platform_network_metrics TO authenticated;

-- ---------------------------------------------------------------------------
-- Trial funnel (schema-derived; not full product analytics)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_platform_trial_funnel()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  RETURN jsonb_build_object(
    'note', 'Derived from subscriptions and tenant activity; not a full event funnel.',
    'trialing', (SELECT COUNT(*)::INT FROM public.company_subscriptions WHERE status = 'trialing'),
    'activated_active', (SELECT COUNT(*)::INT FROM public.company_subscriptions WHERE status = 'active'),
    'with_first_rider', (
      SELECT COUNT(DISTINCT r.company_id)::INT FROM public.riders r
    ),
    'with_first_delivery', (
      SELECT COUNT(DISTINCT d.company_id)::INT FROM public.deliveries d
    ),
    'trial_day_3_reached', (
      SELECT COUNT(*)::INT FROM public.company_subscriptions cs
      WHERE cs.status = 'trialing'
        AND cs.created_at <= now() - interval '3 days'
    ),
    'trial_day_7_reached', (
      SELECT COUNT(*)::INT FROM public.company_subscriptions cs
      WHERE cs.status = 'trialing'
        AND cs.created_at <= now() - interval '7 days'
    ),
    'paid_from_trial', (
      SELECT COUNT(*)::INT FROM public.subscription_billing_payments
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_platform_trial_funnel TO authenticated;

-- ---------------------------------------------------------------------------
-- Companies page (server-side)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_admin_companies_page(
  p_search TEXT DEFAULT NULL,
  p_business_type TEXT DEFAULT NULL,
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
  v_total INT;
  v_rows JSONB;
  v_q TEXT := NULLIF(trim(p_search), '');
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT COUNT(*)::INT INTO v_total
  FROM public.companies c
  WHERE (p_status IS NULL OR c.status::TEXT = p_status)
    AND (p_business_type IS NULL OR c.business_type::TEXT = p_business_type)
    AND (
      v_q IS NULL
      OR c.name ILIKE '%' || v_q || '%'
      OR c.email ILIKE '%' || v_q || '%'
      OR c.phone ILIKE '%' || v_q || '%'
    );

  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::JSONB) INTO v_rows
  FROM (
    SELECT
      c.id,
      c.name,
      c.email,
      c.phone,
      c.status,
      c.business_type,
      c.sms_credits,
      c.created_at,
      s.name AS plan_name,
      s.slug AS plan_slug,
      cs.status AS subscription_status,
      cs.current_period_end AS subscription_period_end
    FROM public.companies c
    LEFT JOIN public.subscriptions s ON s.id = c.subscription_id
    LEFT JOIN LATERAL (
      SELECT cs2.status, cs2.current_period_end
      FROM public.company_subscriptions cs2
      WHERE cs2.company_id = c.id
      ORDER BY cs2.created_at DESC
      LIMIT 1
    ) cs ON true
    WHERE (p_status IS NULL OR c.status::TEXT = p_status)
      AND (p_business_type IS NULL OR c.business_type::TEXT = p_business_type)
      AND (
        v_q IS NULL
        OR c.name ILIKE '%' || v_q || '%'
        OR c.email ILIKE '%' || v_q || '%'
        OR c.phone ILIKE '%' || v_q || '%'
      )
    ORDER BY c.created_at DESC
    LIMIT LEAST(GREATEST(p_limit, 1), 100)
    OFFSET GREATEST(p_offset, 0)
  ) t;

  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_admin_companies_page TO authenticated;

-- ---------------------------------------------------------------------------
-- Company health (transparent rules)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_company_health_score(p_company_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company public.companies;
  v_cs public.company_subscriptions;
  v_reasons JSONB := '[]'::JSONB;
  v_level TEXT := 'healthy';
  v_failed_sms INT;
  v_wh_fail INT;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT * INTO v_company FROM public.companies WHERE id = p_company_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'company_not_found'; END IF;

  v_cs := public.get_active_company_subscription(p_company_id);

  IF v_company.status = 'suspended' THEN
    v_level := 'at_risk';
    v_reasons := v_reasons || jsonb_build_array('Company workspace is suspended');
  END IF;

  IF v_cs.id IS NULL OR v_cs.status IN ('expired', 'cancelled', 'suspended') THEN
    v_level := 'at_risk';
    v_reasons := v_reasons || jsonb_build_array('No active subscription');
  ELSIF v_cs.status = 'past_due' THEN
    v_level := 'at_risk';
    v_reasons := v_reasons || jsonb_build_array('Subscription is past due');
  ELSIF v_cs.status = 'trialing' AND v_cs.current_period_end < now() + interval '2 days' THEN
    IF v_level = 'healthy' THEN v_level := 'needs_attention'; END IF;
    v_reasons := v_reasons || jsonb_build_array('Trial ends within 48 hours');
  END IF;

  IF v_company.sms_credits < 10 THEN
    IF v_level = 'healthy' THEN v_level := 'needs_attention'; END IF;
    v_reasons := v_reasons || jsonb_build_array('SMS credits are low');
  END IF;

  SELECT COUNT(*)::INT INTO v_failed_sms
  FROM public.sms_outbox o
  WHERE o.company_id = p_company_id AND o.status = 'failed'
    AND o.created_at > now() - interval '7 days';
  IF v_failed_sms > 0 THEN
    IF v_level = 'healthy' THEN v_level := 'needs_attention'; END IF;
    v_reasons := v_reasons || jsonb_build_array(v_failed_sms || ' failed SMS messages (7d)');
  END IF;

  SELECT COUNT(*)::INT INTO v_wh_fail
  FROM public.webhook_deliveries wd
  WHERE wd.company_id = p_company_id AND wd.status IN ('failed', 'dead')
    AND wd.created_at > now() - interval '7 days';
  IF v_wh_fail > 0 THEN
    IF v_level = 'healthy' THEN v_level := 'needs_attention'; END IF;
    v_reasons := v_reasons || jsonb_build_array(v_wh_fail || ' webhook delivery failures (7d)');
  END IF;

  RETURN jsonb_build_object('level', v_level, 'reasons', v_reasons);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_company_health_score TO authenticated;

-- ---------------------------------------------------------------------------
-- Company 360 summary
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_company_admin_360(p_company_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company public.companies;
  v_plan public.subscriptions;
  v_cs public.company_subscriptions;
  v_usage JSONB;
  v_health JSONB;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT * INTO v_company FROM public.companies WHERE id = p_company_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'company_not_found'; END IF;

  SELECT * INTO v_plan FROM public.subscriptions WHERE id = v_company.subscription_id;
  v_cs := public.get_active_company_subscription(p_company_id);
  v_usage := public.get_company_usage(p_company_id);
  v_health := public.get_company_health_score(p_company_id);

  RETURN jsonb_build_object(
    'company', to_jsonb(v_company),
    'plan', to_jsonb(v_plan),
    'subscription', CASE WHEN v_cs.id IS NULL THEN NULL ELSE to_jsonb(v_cs) END,
    'usage', v_usage,
    'health', v_health,
    'counts', jsonb_build_object(
      'users', (SELECT COUNT(*)::INT FROM public.company_users WHERE company_id = p_company_id),
      'riders', (SELECT COUNT(*)::INT FROM public.riders WHERE company_id = p_company_id),
      'deliveries', (SELECT COUNT(*)::INT FROM public.deliveries WHERE company_id = p_company_id),
      'api_keys', (SELECT COUNT(*)::INT FROM public.api_keys WHERE company_id = p_company_id AND is_active = true)
    ),
    'marketplace', (
      SELECT to_jsonb(p) FROM public.provider_marketplace_profiles p WHERE p.company_id = p_company_id
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_company_admin_360 TO authenticated;

-- ---------------------------------------------------------------------------
-- Global deliveries explorer
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_deliveries_created_at ON public.deliveries (created_at DESC);

CREATE OR REPLACE FUNCTION public.list_admin_deliveries_page(
  p_tracking_code TEXT DEFAULT NULL,
  p_company_id UUID DEFAULT NULL,
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
  v_total INT;
  v_rows JSONB;
  v_code TEXT := NULLIF(trim(p_tracking_code), '');
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT COUNT(*)::INT INTO v_total
  FROM public.deliveries d
  WHERE (p_company_id IS NULL OR d.company_id = p_company_id)
    AND (p_status IS NULL OR d.status::TEXT = p_status)
    AND (v_code IS NULL OR d.tracking_code ILIKE '%' || v_code || '%');

  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::JSONB) INTO v_rows
  FROM (
    SELECT
      d.id,
      d.tracking_code,
      d.status,
      d.company_id,
      c.name AS company_name,
      d.customer_name,
      public.mask_phone(d.customer_phone) AS customer_phone_masked,
      d.rider_id,
      d.created_at,
      d.amount_to_collect_lrd_cents
    FROM public.deliveries d
    JOIN public.companies c ON c.id = d.company_id
    WHERE (p_company_id IS NULL OR d.company_id = p_company_id)
      AND (p_status IS NULL OR d.status::TEXT = p_status)
      AND (v_code IS NULL OR d.tracking_code ILIKE '%' || v_code || '%')
    ORDER BY d.created_at DESC
    LIMIT LEAST(GREATEST(p_limit, 1), 100)
    OFFSET GREATEST(p_offset, 0)
  ) t;

  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END;
$$;

-- mask_phone helper if missing
CREATE OR REPLACE FUNCTION public.mask_phone(p_phone TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_phone IS NULL OR length(p_phone) < 4 THEN '***'
    ELSE repeat('*', greatest(length(p_phone) - 4, 0)) || right(p_phone, 4)
  END;
$$;

GRANT EXECUTE ON FUNCTION public.list_admin_deliveries_page TO authenticated;

CREATE OR REPLACE FUNCTION public.get_admin_delivery_detail(p_delivery_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_d public.deliveries;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT * INTO v_d FROM public.deliveries WHERE id = p_delivery_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;

  RETURN jsonb_build_object(
    'delivery', to_jsonb(v_d) || jsonb_build_object(
      'customer_phone_masked', public.mask_phone(v_d.customer_phone)
    ),
    'company', (SELECT to_jsonb(c) FROM public.companies c WHERE c.id = v_d.company_id),
    'rider', (SELECT to_jsonb(r) FROM public.riders r WHERE r.id = v_d.rider_id),
    'timeline', (
      SELECT COALESCE(jsonb_agg(to_jsonb(h) ORDER BY h.created_at), '[]'::JSONB)
      FROM public.delivery_status_history h WHERE h.delivery_id = v_d.id
    ),
    'sms_events', (
      SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.created_at DESC), '[]'::JSONB)
      FROM (
        SELECT id, direction, created_at, credits_used, phone
        FROM public.sms_logs WHERE delivery_id = v_d.id LIMIT 50
      ) s
    ),
    'webhook_events', (
      SELECT COALESCE(jsonb_agg(to_jsonb(w) ORDER BY w.created_at DESC), '[]'::JSONB)
      FROM (
        SELECT id, status, event_type, attempt_count, last_error, created_at
        FROM public.webhook_deliveries
        WHERE company_id = v_d.company_id
          AND payload ->> 'delivery_id' = v_d.id::TEXT
        LIMIT 50
      ) w
    ),
    'payment', (SELECT to_jsonb(p) FROM public.payments p WHERE p.delivery_id = v_d.id)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_admin_delivery_detail TO authenticated;

-- ---------------------------------------------------------------------------
-- Map points (privacy-conscious)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_admin_map_points(
  p_company_id UUID DEFAULT NULL,
  p_status TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  RETURN jsonb_build_object(
    'riders', (
      SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::JSONB)
      FROM (
        SELECT rl.rider_id, rl.latitude, rl.longitude, rl.recorded_at, r.status, r.company_id, c.name AS company_name
        FROM public.rider_locations rl
        JOIN public.riders r ON r.id = rl.rider_id
        JOIN public.companies c ON c.id = r.company_id
        WHERE (p_company_id IS NULL OR r.company_id = p_company_id)
        LIMIT 500
      ) t
    ),
    'deliveries', (
      SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::JSONB)
      FROM (
        SELECT d.id, d.tracking_code, d.status, d.company_id, c.name AS company_name
        FROM public.deliveries d
        JOIN public.companies c ON c.id = d.company_id
        WHERE d.status IN ('assigned', 'accepted', 'picked_up', 'in_transit')
          AND (p_company_id IS NULL OR d.company_id = p_company_id)
          AND (p_status IS NULL OR d.status::TEXT = p_status)
        LIMIT 500
      ) t
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_admin_map_points TO authenticated;

-- ---------------------------------------------------------------------------
-- Communications summary
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_admin_communications_summary(p_days INT DEFAULT 7)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_since TIMESTAMPTZ := now() - make_interval(days => GREATEST(LEAST(p_days, 90), 1));
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  RETURN jsonb_build_object(
    'sms', jsonb_build_object(
      'queued', (SELECT COUNT(*)::INT FROM public.sms_outbox WHERE status IN ('pending', 'processing')),
      'sent', (SELECT COUNT(*)::INT FROM public.sms_logs WHERE direction = 'outbound' AND created_at >= v_since),
      'failed', (SELECT COUNT(*)::INT FROM public.sms_outbox WHERE status = 'failed' AND created_at >= v_since)
    ),
    'email', jsonb_build_object(
      'pending', (SELECT COUNT(*)::INT FROM public.email_outbox WHERE status IN ('pending', 'failed')),
      'sent', (SELECT COUNT(*)::INT FROM public.email_outbox WHERE status = 'sent' AND created_at >= v_since)
    ),
    'notifications', (
      SELECT COUNT(*)::INT FROM public.notification_logs WHERE created_at >= v_since
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_admin_communications_summary TO authenticated;

-- ---------------------------------------------------------------------------
-- API keys (metadata only)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_admin_api_keys_page(
  p_company_id UUID DEFAULT NULL,
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
  v_total INT;
  v_rows JSONB;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT COUNT(*)::INT INTO v_total
  FROM public.api_keys k
  WHERE p_company_id IS NULL OR k.company_id = p_company_id;

  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::JSONB) INTO v_rows
  FROM (
    SELECT k.id, k.company_id, c.name AS company_name, k.name, k.key_prefix, k.permissions,
      k.is_active, k.created_at, k.last_used_at, k.expires_at
    FROM public.api_keys k
    JOIN public.companies c ON c.id = k.company_id
    WHERE p_company_id IS NULL OR k.company_id = p_company_id
    ORDER BY k.created_at DESC
    LIMIT LEAST(GREATEST(p_limit, 1), 100)
    OFFSET GREATEST(p_offset, 0)
  ) t;

  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_admin_api_keys_page TO authenticated;

-- ---------------------------------------------------------------------------
-- Global search
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_global_search(p_query TEXT, p_limit INT DEFAULT 15)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_q TEXT := NULLIF(trim(p_query), '');
  v_lim INT := LEAST(GREATEST(p_limit, 1), 30);
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;
  IF v_q IS NULL OR length(v_q) < 2 THEN
    RETURN jsonb_build_object('results', '[]'::JSONB);
  END IF;

  RETURN jsonb_build_object(
    'results', COALESCE((
      SELECT jsonb_agg(r)
      FROM (
        SELECT jsonb_build_object('kind', 'company', 'id', c.id, 'label', c.name, 'href', '/admin/companies/' || c.id::TEXT) AS r
        FROM public.companies c
        WHERE c.name ILIKE '%' || v_q || '%' OR c.phone ILIKE '%' || v_q || '%'
        LIMIT v_lim
      ) a
    ), '[]'::JSONB) || COALESCE((
      SELECT jsonb_agg(r)
      FROM (
        SELECT jsonb_build_object('kind', 'delivery', 'id', d.id, 'label', d.tracking_code, 'href', '/admin/deliveries?code=' || d.tracking_code) AS r
        FROM public.deliveries d
        WHERE d.tracking_code ILIKE '%' || v_q || '%'
        LIMIT v_lim
      ) b
    ), '[]'::JSONB) || COALESCE((
      SELECT jsonb_agg(r)
      FROM (
        SELECT jsonb_build_object('kind', 'rider', 'id', r.id, 'label', r.full_name, 'href', '/admin/riders?q=' || r.rider_code) AS r
        FROM public.riders r
        WHERE r.rider_code ILIKE '%' || v_q || '%' OR r.phone ILIKE '%' || v_q || '%'
        LIMIT v_lim
      ) c
    ), '[]'::JSONB) || COALESCE((
      SELECT jsonb_agg(r)
      FROM (
        SELECT jsonb_build_object('kind', 'user', 'id', p.id, 'label', COALESCE(p.full_name, p.phone), 'href', '/admin/users?q=' || COALESCE(p.phone, '')) AS r
        FROM public.profiles p
        WHERE p.phone ILIKE '%' || v_q || '%' OR p.full_name ILIKE '%' || v_q || '%'
        LIMIT v_lim
      ) d
    ), '[]'::JSONB)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_global_search TO authenticated;

-- ---------------------------------------------------------------------------
-- Support diagnostics
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_support_lookup(p_query TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_q TEXT := NULLIF(trim(p_query), '');
  v_company public.companies;
  v_delivery public.deliveries;
  v_hints JSONB := '[]'::JSONB;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;
  IF v_q IS NULL THEN RETURN jsonb_build_object('hints', v_hints); END IF;

  SELECT * INTO v_delivery FROM public.deliveries WHERE tracking_code ILIKE v_q LIMIT 1;
  IF FOUND THEN
    SELECT * INTO v_company FROM public.companies WHERE id = v_delivery.company_id;
    RETURN jsonb_build_object(
      'match', 'delivery',
      'delivery_id', v_delivery.id,
      'tracking_code', v_delivery.tracking_code,
      'company', to_jsonb(v_company),
      'health', public.get_company_health_score(v_company.id)
    );
  END IF;

  SELECT * INTO v_company FROM public.companies
  WHERE phone ILIKE '%' || v_q || '%' OR name ILIKE '%' || v_q || '%'
  ORDER BY created_at DESC
  LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'match', 'company',
      'company', to_jsonb(v_company),
      'health', public.get_company_health_score(v_company.id),
      'usage', public.get_company_usage(v_company.id)
    );
  END IF;

  RETURN jsonb_build_object('match', NULL, 'message', 'No company or tracking match');
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_support_lookup TO authenticated;

-- ---------------------------------------------------------------------------
-- Platform alerts (conservative, data-driven)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_platform_alerts()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_alerts JSONB := '[]'::JSONB;
  v_sms_fail INT;
  v_wh_dead INT;
  v_past_due INT;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT COUNT(*)::INT INTO v_sms_fail
  FROM public.sms_outbox WHERE status = 'failed' AND created_at > now() - interval '24 hours';
  IF v_sms_fail >= 20 THEN
    v_alerts := v_alerts || jsonb_build_array(jsonb_build_object(
      'severity', 'critical', 'title', 'SMS failure spike', 'detail', v_sms_fail || ' failed in 24h', 'href', '/admin/communications'
    ));
  END IF;

  SELECT COUNT(*)::INT INTO v_wh_dead FROM public.webhook_deliveries WHERE status = 'dead';
  IF v_wh_dead > 0 THEN
    v_alerts := v_alerts || jsonb_build_array(jsonb_build_object(
      'severity', 'high', 'title', 'Dead webhook deliveries', 'detail', v_wh_dead || ' dead letter', 'href', '/admin/webhooks'
    ));
  END IF;

  SELECT COUNT(*)::INT INTO v_past_due FROM public.company_subscriptions WHERE status = 'past_due';
  IF v_past_due > 0 THEN
    v_alerts := v_alerts || jsonb_build_array(jsonb_build_object(
      'severity', 'high', 'title', 'Past-due subscriptions', 'detail', v_past_due || ' companies', 'href', '/admin/subscriptions'
    ));
  END IF;

  RETURN jsonb_build_object('alerts', v_alerts, 'checked_at', now());
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_platform_alerts TO authenticated;

-- ---------------------------------------------------------------------------
-- Audited company status change
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_set_company_status(
  p_company_id UUID,
  p_status public.company_status
)
RETURNS public.companies
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.companies;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  UPDATE public.companies SET status = p_status, updated_at = now()
  WHERE id = p_company_id
  RETURNING * INTO v_row;

  IF NOT FOUND THEN RAISE EXCEPTION 'company_not_found'; END IF;

  PERFORM public.log_audit_event(
    p_company_id,
    'admin.company_status_changed',
    'companies',
    p_company_id,
    jsonb_build_object('status', p_status)
  );

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_set_company_status TO authenticated;

-- ---------------------------------------------------------------------------
-- Extended health snapshot
-- ---------------------------------------------------------------------------
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
    'database', jsonb_build_object('status', 'healthy', 'note', 'Connected via Supabase client'),
    'auth', jsonb_build_object('status', 'healthy'),
    'sms_worker', jsonb_build_object(
      'status', CASE
        WHEN (SELECT COUNT(*) FROM public.sms_outbox WHERE status = 'failed') > 50 THEN 'degraded'
        ELSE 'healthy'
      END,
      'pending', (SELECT COUNT(*)::INT FROM public.sms_outbox WHERE status IN ('pending', 'processing', 'failed'))
    ),
    'webhook_dispatcher', jsonb_build_object(
      'status', CASE
        WHEN (SELECT COUNT(*) FROM public.webhook_deliveries WHERE status = 'dead') > 0 THEN 'degraded'
        ELSE 'healthy'
      END,
      'pending', (SELECT COUNT(*)::INT FROM public.webhook_deliveries WHERE status IN ('pending', 'failed')),
      'dead', (SELECT COUNT(*)::INT FROM public.webhook_deliveries WHERE status = 'dead')
    ),
    'email_worker', jsonb_build_object(
      'status', 'healthy',
      'pending', (SELECT COUNT(*)::INT FROM public.email_outbox WHERE status IN ('pending', 'failed'))
    ),
    'mtn_sms', jsonb_build_object('status', 'not_configured'),
    'mtn_ussd', jsonb_build_object('status', 'not_configured'),
    'mtn_momo', jsonb_build_object('status', 'not_configured'),
    'api_auth_failures_24h', (
      SELECT COUNT(*)::INT FROM public.api_auth_events
      WHERE success = false AND created_at > now() - interval '24 hours'
    ),
    'checked_at', now()
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- Audit filters (super admin)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_audit_logs_admin(
  p_company_id UUID DEFAULT NULL,
  p_action TEXT DEFAULT NULL,
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
  v_total INT;
  v_rows JSONB;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT COUNT(*)::INT INTO v_total
  FROM public.audit_logs a
  WHERE (p_company_id IS NULL OR a.company_id = p_company_id)
    AND (p_action IS NULL OR a.action ILIKE '%' || p_action || '%');

  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::JSONB) INTO v_rows
  FROM (
    SELECT a.*, p.full_name AS actor_name
    FROM public.audit_logs a
    LEFT JOIN public.profiles p ON p.id = a.actor_user_id
    WHERE (p_company_id IS NULL OR a.company_id = p_company_id)
      AND (p_action IS NULL OR a.action ILIKE '%' || p_action || '%')
    ORDER BY a.created_at DESC
    LIMIT LEAST(p_limit, 100) OFFSET GREATEST(p_offset, 0)
  ) t;

  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_audit_logs_admin TO authenticated;

CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON public.audit_logs (action);
