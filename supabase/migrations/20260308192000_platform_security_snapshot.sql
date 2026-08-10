-- ---------------------------------------------------------------------------
-- Super Admin Control Tower: Security page needs real, itemized signals
-- (recent auth failures, recent super-admin actions) rather than just the
-- aggregate counts already in get_platform_health_snapshot(). This is the
-- last "small safe read RPC" for this rebuild — read-only, SECURITY
-- DEFINER, super-admin gated, no schema/RLS/tenant/auth/billing/rider/
-- delivery-state-machine/MTN/MoMo change. Never returns secret values —
-- api_auth_events has no secret columns by design, and audit_logs metadata
-- is not exposed here, only action/entity/actor name.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_platform_security_snapshot()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_recent_auth_failures JSONB;
  v_recent_admin_actions JSONB;
  v_failing_prefixes_24h INT;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'key_prefix', e.key_prefix, 'error_code', e.error_code,
    'company_name', c.name, 'created_at', e.created_at
  ) ORDER BY e.created_at DESC), '[]'::JSONB)
  INTO v_recent_auth_failures
  FROM (
    SELECT key_prefix, error_code, company_id, created_at
    FROM public.api_auth_events
    WHERE success = false
    ORDER BY created_at DESC
    LIMIT 15
  ) e
  LEFT JOIN public.companies c ON c.id = e.company_id;

  SELECT COUNT(DISTINCT key_prefix)::INT INTO v_failing_prefixes_24h
  FROM public.api_auth_events
  WHERE success = false AND created_at > now() - interval '24 hours' AND key_prefix IS NOT NULL;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'actor_name', p.full_name, 'action', a.action, 'entity_type', a.entity_type,
    'company_name', c.name, 'created_at', a.created_at
  ) ORDER BY a.created_at DESC), '[]'::JSONB)
  INTO v_recent_admin_actions
  FROM (
    SELECT a.actor_user_id, a.action, a.entity_type, a.company_id, a.created_at
    FROM public.audit_logs a
    JOIN public.profiles pr ON pr.id = a.actor_user_id AND pr.is_super_admin = true
    ORDER BY a.created_at DESC
    LIMIT 10
  ) a
  JOIN public.profiles p ON p.id = a.actor_user_id
  LEFT JOIN public.companies c ON c.id = a.company_id;

  RETURN jsonb_build_object(
    'recent_auth_failures', v_recent_auth_failures,
    'recent_admin_actions', v_recent_admin_actions,
    'distinct_failing_key_prefixes_24h', v_failing_prefixes_24h,
    'checked_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_platform_security_snapshot TO authenticated;
