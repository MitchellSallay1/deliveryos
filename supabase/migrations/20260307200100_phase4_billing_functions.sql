-- DeliveryOS · Phase 4: billing functions, RLS, feature access, audit, tracking privacy

-- ---------------------------------------------------------------------------
-- Audit (insert-only for clients via RPC)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.log_audit_event(
  p_company_id UUID,
  p_action TEXT,
  p_entity_type TEXT,
  p_entity_id UUID,
  p_metadata JSONB DEFAULT '{}'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO public.audit_logs (actor_user_id, company_id, action, entity_type, entity_id, metadata)
  VALUES (auth.uid(), p_company_id, p_action, p_entity_type, p_entity_id, COALESCE(p_metadata, '{}'))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.log_audit_event FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- Active subscription + billing period
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_active_company_subscription(p_company_id UUID)
RETURNS public.company_subscriptions
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT cs.*
  FROM public.company_subscriptions cs
  WHERE cs.company_id = p_company_id
    AND cs.status IN ('trialing', 'active', 'past_due')
  ORDER BY cs.created_at DESC
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.company_deliveries_in_period(
  p_company_id UUID,
  p_start TIMESTAMPTZ,
  p_end TIMESTAMPTZ
)
RETURNS INT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COUNT(*)::INT
  FROM public.deliveries d
  WHERE d.company_id = p_company_id
    AND d.created_at >= p_start
    AND d.created_at < p_end;
$$;

CREATE OR REPLACE FUNCTION public.company_sms_consumed_in_period(
  p_company_id UUID,
  p_start TIMESTAMPTZ,
  p_end TIMESTAMPTZ
)
RETURNS INT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(SUM(credits_used), 0)::INT
  FROM public.sms_logs
  WHERE company_id = p_company_id
    AND direction = 'outbound'
    AND created_at >= p_start
    AND created_at < p_end;
$$;

CREATE OR REPLACE FUNCTION public.get_company_usage(p_company_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cs public.company_subscriptions;
  v_plan public.subscriptions;
  v_riders INT;
  v_deliveries INT;
  v_completed INT;
  v_sms INT;
  v_photos BIGINT;
BEGIN
  IF NOT (
    public.is_super_admin()
    OR p_company_id IN (SELECT public.user_company_ids())
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  v_cs := public.get_active_company_subscription(p_company_id);
  IF v_cs.id IS NULL THEN
    SELECT c.subscription_id INTO v_plan.id FROM public.companies c WHERE c.id = p_company_id;
    SELECT * INTO v_plan FROM public.subscriptions WHERE id = (
      SELECT subscription_id FROM public.companies WHERE id = p_company_id
    );
    RETURN jsonb_build_object('subscription', NULL, 'plan', to_jsonb(v_plan));
  END IF;

  SELECT * INTO v_plan FROM public.subscriptions WHERE id = v_cs.plan_id;
  SELECT COUNT(*)::INT INTO v_riders FROM public.riders WHERE company_id = p_company_id;
  v_deliveries := public.company_deliveries_in_period(
    p_company_id, v_cs.current_period_start, v_cs.current_period_end
  );
  SELECT COUNT(*)::INT INTO v_completed
  FROM public.deliveries d
  WHERE d.company_id = p_company_id
    AND d.status = 'delivered'
    AND d.delivered_at >= v_cs.current_period_start
    AND d.delivered_at < v_cs.current_period_end;
  v_sms := public.company_sms_consumed_in_period(
    p_company_id, v_cs.current_period_start, v_cs.current_period_end
  );
  SELECT COUNT(*) INTO v_photos FROM public.delivery_photos WHERE company_id = p_company_id;

  RETURN jsonb_build_object(
    'subscription', to_jsonb(v_cs),
    'plan', to_jsonb(v_plan),
    'period', jsonb_build_object(
      'start', v_cs.current_period_start,
      'end', v_cs.current_period_end
    ),
    'usage', jsonb_build_object(
      'deliveries_created', v_deliveries,
      'deliveries_completed', v_completed,
      'riders', v_riders,
      'sms_consumed', v_sms,
      'storage_photos', v_photos
    ),
    'limits', jsonb_build_object(
      'max_deliveries_per_month', v_plan.max_deliveries_per_month,
      'max_riders', v_plan.max_riders,
      'monthly_sms_allowance', v_plan.monthly_sms_allowance
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_company_usage TO authenticated;

-- ---------------------------------------------------------------------------
-- Centralized feature access
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
    WHEN 'sms' THEN v_cs.status IN ('trialing', 'active')
    ELSE COALESCE((v_plan.features ->> p_feature_key)::BOOLEAN, false)
  END;

  RETURN COALESCE(v_ok, false);
END;
$$;

GRANT EXECUTE ON FUNCTION public.can_use_feature TO authenticated;

-- Replace legacy feature helper used by SMS queue
CREATE OR REPLACE FUNCTION public.company_feature_enabled(
  p_company_id UUID,
  p_feature_key TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.can_use_feature(p_company_id, p_feature_key);
$$;

-- ---------------------------------------------------------------------------
-- Subscription-aware limits (use active plan from company_subscriptions)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assert_subscription_delivery_limit(p_company_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max INT;
  v_count INT;
  v_cs public.company_subscriptions;
  v_plan public.subscriptions;
BEGIN
  v_cs := public.get_active_company_subscription(p_company_id);
  IF v_cs.id IS NULL OR v_cs.status NOT IN ('trialing', 'active', 'past_due') THEN
    RAISE EXCEPTION 'subscription_inactive';
  END IF;
  IF v_cs.status = 'past_due' THEN
    RAISE EXCEPTION 'subscription_past_due';
  END IF;
  IF v_cs.current_period_end < now() THEN
    RAISE EXCEPTION 'subscription_expired';
  END IF;

  SELECT * INTO v_plan FROM public.subscriptions WHERE id = v_cs.plan_id;
  v_max := v_plan.max_deliveries_per_month;
  IF v_max IS NULL THEN
    RETURN;
  END IF;

  v_count := public.company_deliveries_in_period(
    p_company_id, v_cs.current_period_start, v_cs.current_period_end
  );
  IF v_count >= v_max THEN
    RAISE EXCEPTION 'delivery_monthly_limit_reached';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_rider_plan_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max INT;
  v_count INT;
  v_cs public.company_subscriptions;
  v_plan public.subscriptions;
BEGIN
  PERFORM public.assert_company_operational(NEW.company_id);

  v_cs := public.get_active_company_subscription(NEW.company_id);
  IF v_cs.id IS NULL THEN
    RAISE EXCEPTION 'subscription_inactive';
  END IF;

  SELECT * INTO v_plan FROM public.subscriptions WHERE id = v_cs.plan_id;
  v_max := v_plan.max_riders;

  SELECT COUNT(*)::INT INTO v_count FROM public.riders WHERE company_id = NEW.company_id;
  IF v_count >= v_max THEN
    RAISE EXCEPTION 'rider_plan_limit_reached';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.register_delivery_photo(
  p_company_id UUID,
  p_delivery_id UUID,
  p_storage_path TEXT
)
RETURNS public.delivery_photos
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.delivery_photos;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  PERFORM public.assert_company_operational(p_company_id);
  IF NOT public.can_use_feature(p_company_id, 'proof_of_delivery') THEN
    RAISE EXCEPTION 'feature_not_available';
  END IF;
  IF NOT (
    public.is_super_admin()
    OR public.has_company_role(
      p_company_id,
      ARRAY['company_owner', 'dispatcher', 'rider']::public.company_role[]
    )
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.deliveries d
    WHERE d.id = p_delivery_id AND d.company_id = p_company_id
  ) THEN
    RAISE EXCEPTION 'delivery not found';
  END IF;

  INSERT INTO public.delivery_photos (company_id, delivery_id, storage_path, uploaded_by)
  VALUES (p_company_id, p_delivery_id, p_storage_path, auth.uid())
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

-- ---------------------------------------------------------------------------
-- Public tracking privacy
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.generalize_address(p_address TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_address IS NULL OR trim(p_address) = '' THEN 'Area unavailable'
    WHEN length(p_address) <= 40 THEN p_address
    ELSE left(p_address, 40) || '…'
  END;
$$;

DROP FUNCTION IF EXISTS public.get_delivery_tracking(TEXT);

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
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT
    d.tracking_code,
    d.status,
    c.name AS company_name,
    public.generalize_address(d.pickup_address) AS pickup_area,
    public.generalize_address(d.destination_address) AS destination_area,
    d.updated_at,
    (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'status', h.to_status,
        'at', h.created_at
      ) ORDER BY h.created_at), '[]'::JSONB)
      FROM public.delivery_status_history h
      WHERE h.delivery_id = d.id
    ) AS status_timeline
  FROM public.deliveries d
  JOIN public.companies c ON c.id = d.company_id
  WHERE d.tracking_code = p_tracking_code;
$$;

GRANT EXECUTE ON FUNCTION public.get_delivery_tracking(TEXT) TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- RLS: billing tables
-- ---------------------------------------------------------------------------
ALTER TABLE public.company_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_billing_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY company_subscriptions_select ON public.company_subscriptions
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR company_id IN (SELECT public.user_company_ids())
  );

CREATE POLICY invoices_select ON public.invoices
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR (
      company_id IN (SELECT public.user_company_ids())
      AND public.has_company_role(company_id, ARRAY['company_owner']::public.company_role[])
    )
  );

CREATE POLICY subscription_billing_payments_select ON public.subscription_billing_payments
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR (
      company_id IN (SELECT public.user_company_ids())
      AND public.has_company_role(company_id, ARRAY['company_owner']::public.company_role[])
    )
  );

CREATE POLICY audit_logs_select ON public.audit_logs
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR (
      company_id IN (SELECT public.user_company_ids())
      AND public.has_company_role(company_id, ARRAY['company_owner']::public.company_role[])
    )
  );

-- subscriptions: super admin can update plans via RPC only; keep read for all authenticated
CREATE POLICY subscriptions_admin_update ON public.subscriptions
  FOR UPDATE TO authenticated
  USING (public.is_super_admin())
  WITH CHECK (public.is_super_admin());

-- ---------------------------------------------------------------------------
-- Super admin billing RPCs
-- ---------------------------------------------------------------------------
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
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF v_id IS NULL THEN
    INSERT INTO public.subscriptions (
      slug, name, max_riders, max_deliveries_per_month, price_lrd_cents, currency,
      monthly_sms_allowance, proof_of_delivery, advanced_reports, api_access,
      gps_tracking, custom_branding, is_active, features
    ) VALUES (
      p_payload ->> 'slug',
      p_payload ->> 'name',
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
      COALESCE(p_payload -> 'features', '{}'::JSONB)
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
      currency = COALESCE(p_payload ->> 'currency', currency),
      monthly_sms_allowance = COALESCE((p_payload ->> 'monthly_sms_allowance')::INT, monthly_sms_allowance),
      proof_of_delivery = COALESCE((p_payload ->> 'proof_of_delivery')::BOOLEAN, proof_of_delivery),
      advanced_reports = COALESCE((p_payload ->> 'advanced_reports')::BOOLEAN, advanced_reports),
      api_access = COALESCE((p_payload ->> 'api_access')::BOOLEAN, api_access),
      gps_tracking = COALESCE((p_payload ->> 'gps_tracking')::BOOLEAN, gps_tracking),
      custom_branding = COALESCE((p_payload ->> 'custom_branding')::BOOLEAN, custom_branding),
      is_active = COALESCE((p_payload ->> 'is_active')::BOOLEAN, is_active),
      features = COALESCE(p_payload -> 'features', features)
    WHERE id = v_id
    RETURNING * INTO v_row;
  END IF;

  PERFORM public.log_audit_event(NULL, 'plan_upserted', 'subscriptions', v_row.id, to_jsonb(v_row));
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_upsert_plan TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_company_subscription(
  p_company_id UUID,
  p_plan_id UUID,
  p_status public.company_subscription_status,
  p_period_end TIMESTAMPTZ DEFAULT NULL
)
RETURNS public.company_subscriptions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.company_subscriptions;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE public.company_subscriptions
  SET status = 'cancelled', cancelled_at = now(), updated_at = now()
  WHERE company_id = p_company_id
    AND status IN ('trialing', 'active', 'past_due');

  INSERT INTO public.company_subscriptions (
    company_id, plan_id, status,
    current_period_start, current_period_end
  ) VALUES (
    p_company_id,
    p_plan_id,
    p_status,
    date_trunc('month', now() AT TIME ZONE 'Africa/Monrovia'),
    COALESCE(p_period_end, (date_trunc('month', now() AT TIME ZONE 'Africa/Monrovia') + INTERVAL '1 month'))
  )
  RETURNING * INTO v_row;

  UPDATE public.companies SET subscription_id = p_plan_id WHERE id = p_company_id;

  PERFORM public.log_audit_event(
    p_company_id, 'subscription_changed', 'company_subscriptions', v_row.id, to_jsonb(v_row)
  );
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_set_company_subscription TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_extend_subscription(
  p_company_subscription_id UUID,
  p_new_period_end TIMESTAMPTZ
)
RETURNS public.company_subscriptions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.company_subscriptions;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE public.company_subscriptions
  SET current_period_end = p_new_period_end, status = 'active', updated_at = now()
  WHERE id = p_company_subscription_id
  RETURNING * INTO v_row;

  PERFORM public.log_audit_event(
    v_row.company_id, 'subscription_extended', 'company_subscriptions', v_row.id,
    jsonb_build_object('period_end', p_new_period_end)
  );
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_extend_subscription TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_create_invoice(
  p_company_id UUID,
  p_plan_id UUID,
  p_amount_cents INT,
  p_period_start TIMESTAMPTZ,
  p_period_end TIMESTAMPTZ,
  p_due_at TIMESTAMPTZ
)
RETURNS public.invoices
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.invoices;
  v_cs UUID;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT id INTO v_cs FROM public.company_subscriptions
  WHERE company_id = p_company_id
  ORDER BY created_at DESC LIMIT 1;

  INSERT INTO public.invoices (
    company_id, company_subscription_id, plan_id,
    billing_period_start, billing_period_end,
    amount_cents, currency, status, issued_at, due_at
  )
  SELECT
    p_company_id, v_cs, p_plan_id,
    p_period_start, p_period_end,
    p_amount_cents, s.currency, 'issued', now(), p_due_at
  FROM public.subscriptions s WHERE s.id = p_plan_id
  RETURNING * INTO v_row;

  PERFORM public.log_audit_event(
    p_company_id, 'invoice_issued', 'invoices', v_row.id, to_jsonb(v_row)
  );
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_create_invoice TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_record_billing_payment(
  p_company_id UUID,
  p_invoice_id UUID,
  p_amount_cents INT,
  p_payment_method public.billing_payment_method,
  p_reference TEXT,
  p_paid_at TIMESTAMPTZ
)
RETURNS public.subscription_billing_payments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.subscription_billing_payments;
  v_inv public.invoices;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT * INTO v_inv FROM public.invoices WHERE id = p_invoice_id AND company_id = p_company_id;

  INSERT INTO public.subscription_billing_payments (
    company_id, invoice_id, amount_cents, currency, payment_method,
    reference, paid_at, billing_period_start, billing_period_end, recorded_by
  ) VALUES (
    p_company_id, p_invoice_id, p_amount_cents,
    COALESCE(v_inv.currency, 'LRD'),
    p_payment_method, p_reference, COALESCE(p_paid_at, now()),
    v_inv.billing_period_start, v_inv.billing_period_end, auth.uid()
  )
  RETURNING * INTO v_row;

  PERFORM public.log_audit_event(
    p_company_id, 'billing_payment_recorded', 'subscription_billing_payments', v_row.id, to_jsonb(v_row)
  );
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_record_billing_payment TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_mark_invoice_paid(
  p_invoice_id UUID,
  p_payment_reference TEXT DEFAULT NULL
)
RETURNS public.invoices
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.invoices;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE public.invoices SET
    status = 'paid',
    paid_at = now(),
    payment_reference = COALESCE(p_payment_reference, payment_reference),
    updated_at = now()
  WHERE id = p_invoice_id
  RETURNING * INTO v_row;

  PERFORM public.log_audit_event(
    v_row.company_id, 'invoice_marked_paid', 'invoices', v_row.id, to_jsonb(v_row)
  );
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_mark_invoice_paid TO authenticated;

CREATE OR REPLACE FUNCTION public.get_platform_billing_metrics()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  RETURN jsonb_build_object(
    'active_subscriptions', (
      SELECT COUNT(*)::INT FROM public.company_subscriptions WHERE status = 'active'
    ),
    'trialing', (
      SELECT COUNT(*)::INT FROM public.company_subscriptions WHERE status = 'trialing'
    ),
    'suspended_subscriptions', (
      SELECT COUNT(*)::INT FROM public.company_subscriptions WHERE status = 'suspended'
    ),
    'past_due', (
      SELECT COUNT(*)::INT FROM public.company_subscriptions WHERE status = 'past_due'
    ),
    'monthly_revenue_cents', (
      SELECT COALESCE(SUM(amount_cents), 0)::INT
      FROM public.subscription_billing_payments
      WHERE paid_at >= date_trunc('month', now() AT TIME ZONE 'Africa/Monrovia')
    ),
    'unpaid_invoices', (
      SELECT COUNT(*)::INT FROM public.invoices WHERE status IN ('issued', 'overdue')
    ),
    'plan_breakdown', (
      SELECT COALESCE(jsonb_object_agg(slug, cnt), '{}'::JSONB)
      FROM (
        SELECT s.slug, COUNT(*)::INT AS cnt
        FROM public.company_subscriptions cs
        JOIN public.subscriptions s ON s.id = cs.plan_id
        WHERE cs.status IN ('active', 'trialing', 'past_due')
        GROUP BY s.slug
      ) q
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_platform_billing_metrics TO authenticated;

CREATE OR REPLACE FUNCTION public.list_invoices_page(
  p_company_id UUID DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_search TEXT DEFAULT NULL,
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
  IF p_company_id IS NOT NULL THEN
    IF NOT (
      public.is_super_admin()
      OR (
        p_company_id IN (SELECT public.user_company_ids())
        AND public.has_company_role(p_company_id, ARRAY['company_owner']::public.company_role[])
      )
    ) THEN
      RAISE EXCEPTION 'forbidden';
    END IF;
  ELSIF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT COUNT(*)::INT INTO v_total
  FROM public.invoices i
  WHERE (p_company_id IS NULL OR i.company_id = p_company_id)
    AND (p_status IS NULL OR i.status::TEXT = p_status)
    AND (
      p_search IS NULL OR p_search = ''
      OR i.invoice_number ILIKE '%' || p_search || '%'
    );

  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::JSONB) INTO v_rows
  FROM (
    SELECT i.*, c.name AS company_name, s.name AS plan_name
    FROM public.invoices i
    JOIN public.companies c ON c.id = i.company_id
    JOIN public.subscriptions s ON s.id = i.plan_id
    WHERE (p_company_id IS NULL OR i.company_id = p_company_id)
      AND (p_status IS NULL OR i.status::TEXT = p_status)
      AND (
        p_search IS NULL OR p_search = ''
        OR i.invoice_number ILIKE '%' || p_search || '%'
      )
    ORDER BY i.created_at DESC
    LIMIT LEAST(p_limit, 100) OFFSET GREATEST(p_offset, 0)
  ) t;

  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_invoices_page TO authenticated;

CREATE OR REPLACE FUNCTION public.list_audit_logs_page(
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
  IF p_company_id IS NOT NULL THEN
    IF NOT (
      public.is_super_admin()
      OR (
        p_company_id IN (SELECT public.user_company_ids())
        AND public.has_company_role(p_company_id, ARRAY['company_owner']::public.company_role[])
      )
    ) THEN
      RAISE EXCEPTION 'forbidden';
    END IF;
  ELSIF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT COUNT(*)::INT INTO v_total
  FROM public.audit_logs a
  WHERE p_company_id IS NULL OR a.company_id = p_company_id;

  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::JSONB) INTO v_rows
  FROM (
    SELECT a.*
    FROM public.audit_logs a
    WHERE p_company_id IS NULL OR a.company_id = p_company_id
    ORDER BY a.created_at DESC
    LIMIT LEAST(p_limit, 100) OFFSET GREATEST(p_offset, 0)
  ) t;

  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_audit_logs_page TO authenticated;

CREATE OR REPLACE FUNCTION public.list_billing_payments_page(
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
  IF p_company_id IS NOT NULL THEN
    IF NOT (
      public.is_super_admin()
      OR (
        p_company_id IN (SELECT public.user_company_ids())
        AND public.has_company_role(p_company_id, ARRAY['company_owner']::public.company_role[])
      )
    ) THEN
      RAISE EXCEPTION 'forbidden';
    END IF;
  ELSIF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT COUNT(*)::INT INTO v_total
  FROM public.subscription_billing_payments p
  WHERE p_company_id IS NULL OR p.company_id = p_company_id;

  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::JSONB) INTO v_rows
  FROM (
    SELECT p.*, c.name AS company_name
    FROM public.subscription_billing_payments p
    JOIN public.companies c ON c.id = p.company_id
    WHERE p_company_id IS NULL OR p.company_id = p_company_id
    ORDER BY p.paid_at DESC
    LIMIT LEAST(p_limit, 100) OFFSET GREATEST(p_offset, 0)
  ) t;

  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_billing_payments_page TO authenticated;

CREATE OR REPLACE FUNCTION public.list_plans_admin()
RETURNS SETOF public.subscriptions
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  RETURN QUERY SELECT * FROM public.subscriptions ORDER BY price_lrd_cents;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_plans_admin TO authenticated;

-- Patch admin_add_sms_credits to audit
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

  PERFORM public.log_audit_event(
    p_company_id, 'sms_credits_added', 'companies', p_company_id,
    jsonb_build_object('amount', p_amount, 'balance', v_balance, 'reason', p_reason)
  );

  RETURN v_balance;
END;
$$;

-- Preserve report logic under new core name
CREATE OR REPLACE FUNCTION public.get_workspace_report_core(
  p_company_id UUID,
  p_period TEXT DEFAULT 'day'
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_local TIMESTAMP;
  v_from TIMESTAMPTZ;
  v_to TIMESTAMPTZ;
  v_label TEXT;
  v_summary JSONB;
  v_riders JSONB;
BEGIN
  IF p_period NOT IN ('day', 'week', 'month') THEN
    RAISE EXCEPTION 'invalid period';
  END IF;

  v_local := (current_timestamp AT TIME ZONE 'Africa/Monrovia');

  IF p_period = 'week' THEN
    v_label := 'week';
    v_from := (date_trunc('day', v_local) - ((EXTRACT(ISODOW FROM v_local)::INT - 1) || ' days')::INTERVAL)
      AT TIME ZONE 'Africa/Monrovia';
    v_to := v_from + INTERVAL '7 days';
  ELSIF p_period = 'month' THEN
    v_label := 'month';
    v_from := (date_trunc('month', v_local) AT TIME ZONE 'Africa/Monrovia');
    v_to := v_from + INTERVAL '1 month';
  ELSE
    v_label := 'day';
    v_from := (date_trunc('day', v_local) AT TIME ZONE 'Africa/Monrovia');
    v_to := v_from + INTERVAL '1 day';
  END IF;

  SELECT jsonb_build_object(
    'period', v_label,
    'from', v_from,
    'to', v_to,
    'total', COUNT(*)::INT,
    'completed', COUNT(*) FILTER (WHERE status = 'delivered')::INT,
    'failed', COUNT(*) FILTER (WHERE status = 'failed')::INT,
    'cancelled', COUNT(*) FILTER (WHERE status = 'cancelled')::INT,
    'in_progress', COUNT(*) FILTER (
      WHERE status IN ('pending', 'assigned', 'accepted', 'picked_up', 'in_transit')
    )::INT,
    'cod_collected_lrd_cents', COALESCE(SUM(amount_to_collect_lrd_cents) FILTER (WHERE status = 'delivered'), 0)::INT,
    'delivery_fees_lrd_cents', COALESCE(SUM(delivery_fee_lrd_cents) FILTER (WHERE status = 'delivered'), 0)::INT,
    'avg_delivery_minutes', (
      SELECT (AVG(EXTRACT(EPOCH FROM (delivered_at - created_at)) / 60))::INT
      FROM public.deliveries d2
      WHERE d2.company_id = p_company_id
        AND d2.status = 'delivered'
        AND d2.delivered_at IS NOT NULL
        AND d2.created_at >= v_from
        AND d2.created_at < v_to
    )
  ) INTO v_summary
  FROM public.deliveries d
  WHERE d.company_id = p_company_id
    AND d.created_at >= v_from
    AND d.created_at < v_to;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'rider_code', rider_code,
        'full_name', full_name,
        'completed_deliveries', completed_deliveries,
        'rating', rating,
        'period_completed', period_completed
      )
      ORDER BY period_completed DESC
    ),
    '[]'::JSONB
  ) INTO v_riders
  FROM (
    SELECT
      r.rider_code,
      r.full_name,
      r.completed_deliveries,
      r.rating,
      COUNT(del.id) FILTER (WHERE del.status = 'delivered')::INT AS period_completed
    FROM public.riders r
    LEFT JOIN public.deliveries del ON del.rider_id = r.id
      AND del.created_at >= v_from
      AND del.created_at < v_to
    WHERE r.company_id = p_company_id
    GROUP BY r.id, r.rider_code, r.full_name, r.completed_deliveries, r.rating
    ORDER BY period_completed DESC
    LIMIT 5
  ) top;

  RETURN jsonb_build_object('summary', v_summary, 'top_riders', v_riders);
END;
$$;

REVOKE ALL ON FUNCTION public.get_workspace_report_core FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.get_workspace_report(
  p_company_id UUID,
  p_period TEXT DEFAULT 'day'
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.assert_company_member(p_company_id);
  IF NOT public.can_use_feature(p_company_id, 'advanced_reports') AND p_period <> 'day' THEN
    RAISE EXCEPTION 'feature_not_available';
  END IF;
  RETURN public.get_workspace_report_core(p_company_id, p_period);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_workspace_report TO authenticated;
