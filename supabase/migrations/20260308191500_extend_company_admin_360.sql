-- ---------------------------------------------------------------------------
-- Extend get_company_admin_360 with the remaining Company 360 surfaces:
-- owner/contact, branches, customers count, webhook health, recent webhook
-- errors, recent audit history, and API key metadata (never key material).
--
-- This is the one additional "small safe read RPC" needed for the Super
-- Admin Control Tower Company 360 rebuild — read-only, SECURITY DEFINER,
-- super-admin gated exactly like the function it replaces. No schema
-- change, no RLS change, no change to tenant isolation, billing rules,
-- rider logic, delivery state machine, or MTN/MoMo behavior. Forward-safe:
-- CREATE OR REPLACE only, no edits to already-applied migration files.
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
  v_owner JSONB;
  v_branches JSONB;
  v_webhooks JSONB;
  v_recent_errors JSONB;
  v_audit_recent JSONB;
  v_api_keys JSONB;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT * INTO v_company FROM public.companies WHERE id = p_company_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'company_not_found'; END IF;

  SELECT * INTO v_plan FROM public.subscriptions WHERE id = v_company.subscription_id;
  v_cs := public.get_active_company_subscription(p_company_id);
  v_usage := public.get_company_usage(p_company_id);
  v_health := public.get_company_health_score(p_company_id);

  SELECT jsonb_build_object('full_name', p.full_name, 'phone', p.phone, 'role', cu.role)
  INTO v_owner
  FROM public.company_users cu
  JOIN public.profiles p ON p.id = cu.user_id
  WHERE cu.company_id = p_company_id AND cu.role = 'company_owner'::public.company_role
  ORDER BY cu.created_at ASC
  LIMIT 1;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', b.id, 'name', b.name, 'code', b.code, 'city', b.city, 'is_active', b.is_active
  ) ORDER BY b.created_at ASC), '[]'::JSONB)
  INTO v_branches
  FROM public.company_branches b
  WHERE b.company_id = p_company_id;

  SELECT jsonb_build_object(
    'endpoints_active', (SELECT COUNT(*)::INT FROM public.webhook_endpoints WHERE company_id = p_company_id AND is_active = true),
    'endpoints_total', (SELECT COUNT(*)::INT FROM public.webhook_endpoints WHERE company_id = p_company_id),
    'delivered_24h', (SELECT COUNT(*)::INT FROM public.webhook_deliveries WHERE company_id = p_company_id AND status = 'delivered' AND created_at >= now() - INTERVAL '24 hours'),
    'failed_24h', (SELECT COUNT(*)::INT FROM public.webhook_deliveries WHERE company_id = p_company_id AND status IN ('failed', 'dead') AND created_at >= now() - INTERVAL '24 hours'),
    'last_failure_at', (SELECT MAX(created_at) FROM public.webhook_deliveries WHERE company_id = p_company_id AND status IN ('failed', 'dead'))
  ) INTO v_webhooks;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'event_type', w.event_type, 'status', w.status, 'last_error', w.last_error, 'created_at', w.created_at
  ) ORDER BY w.created_at DESC), '[]'::JSONB)
  INTO v_recent_errors
  FROM (
    SELECT event_type, status, last_error, created_at
    FROM public.webhook_deliveries
    WHERE company_id = p_company_id AND status IN ('failed', 'dead')
    ORDER BY created_at DESC
    LIMIT 5
  ) w;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'action', a.action, 'entity_type', a.entity_type, 'entity_id', a.entity_id, 'created_at', a.created_at
  ) ORDER BY a.created_at DESC), '[]'::JSONB)
  INTO v_audit_recent
  FROM (
    SELECT action, entity_type, entity_id, created_at
    FROM public.audit_logs
    WHERE company_id = p_company_id
    ORDER BY created_at DESC
    LIMIT 10
  ) a;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'name', k.name, 'key_prefix', k.key_prefix, 'is_active', k.is_active,
    'last_used_at', k.last_used_at, 'created_at', k.created_at
  ) ORDER BY k.created_at DESC), '[]'::JSONB)
  INTO v_api_keys
  FROM public.api_keys k
  WHERE k.company_id = p_company_id;

  RETURN jsonb_build_object(
    'company', to_jsonb(v_company),
    'plan', to_jsonb(v_plan),
    'subscription', CASE WHEN v_cs.id IS NULL THEN NULL ELSE to_jsonb(v_cs) END,
    'usage', v_usage,
    'health', v_health,
    'owner', v_owner,
    'branches', v_branches,
    'webhooks', v_webhooks,
    'recent_webhook_errors', v_recent_errors,
    'audit_recent', v_audit_recent,
    'api_keys', v_api_keys,
    'counts', jsonb_build_object(
      'users', (SELECT COUNT(*)::INT FROM public.company_users WHERE company_id = p_company_id),
      'riders', (SELECT COUNT(*)::INT FROM public.riders WHERE company_id = p_company_id),
      'deliveries', (SELECT COUNT(*)::INT FROM public.deliveries WHERE company_id = p_company_id),
      'customers', (SELECT COUNT(*)::INT FROM public.customers WHERE company_id = p_company_id),
      'branches', (SELECT COUNT(*)::INT FROM public.company_branches WHERE company_id = p_company_id),
      'api_keys', (SELECT COUNT(*)::INT FROM public.api_keys WHERE company_id = p_company_id AND is_active = true)
    ),
    'marketplace', (
      SELECT to_jsonb(p) FROM public.provider_marketplace_profiles p WHERE p.company_id = p_company_id
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_company_admin_360 TO authenticated;
