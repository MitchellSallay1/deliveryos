-- Super Admin Control Tower upgrade: extend get_platform_alerts() with
-- three more data-driven conditions the frontend audit found were missing
-- (excessive delivery failures, companies low/out of SMS credits, unusual
-- API auth failure spikes). CREATE OR REPLACE on an existing function, same
-- signature, same is_super_admin() gate, same "only real evidence" style as
-- the three conditions already here. No schema change, no RLS/tenant/auth/
-- billing/rider/delivery-state-machine/MTN/MoMo logic touched — this is a
-- read-only aggregate query, purely for admin operational visibility.
--
-- Each alert now also carries `entity` (what it's about) and
-- `suggested_action` (what an operator should do), per the control-tower
-- redesign's requirement to make alerts actionable, not just descriptive.

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
  v_failed_deliveries_24h INT;
  v_companies_out_of_sms INT;
  v_companies_low_sms INT;
  v_api_auth_fail_1h INT;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT COUNT(*)::INT INTO v_sms_fail
  FROM public.sms_outbox WHERE status = 'failed' AND created_at > now() - interval '24 hours';
  IF v_sms_fail >= 20 THEN
    v_alerts := v_alerts || jsonb_build_array(jsonb_build_object(
      'severity', 'critical', 'title', 'SMS failure spike',
      'detail', v_sms_fail || ' failed in 24h', 'href', '/admin/communications',
      'entity', 'SMS outbox', 'suggested_action', 'Check sms-dispatch Edge Function logs and provider status.'
    ));
  END IF;

  SELECT COUNT(*)::INT INTO v_wh_dead FROM public.webhook_deliveries WHERE status = 'dead';
  IF v_wh_dead > 0 THEN
    v_alerts := v_alerts || jsonb_build_array(jsonb_build_object(
      'severity', 'high', 'title', 'Dead webhook deliveries',
      'detail', v_wh_dead || ' dead letter', 'href', '/admin/webhooks',
      'entity', 'Webhook dispatcher', 'suggested_action', 'Review dead-letter payloads; notify affected companies if endpoints are theirs to fix.'
    ));
  END IF;

  SELECT COUNT(*)::INT INTO v_past_due FROM public.company_subscriptions WHERE status = 'past_due';
  IF v_past_due > 0 THEN
    v_alerts := v_alerts || jsonb_build_array(jsonb_build_object(
      'severity', 'high', 'title', 'Past-due subscriptions',
      'detail', v_past_due || ' companies', 'href', '/admin/subscriptions',
      'entity', v_past_due || ' companies', 'suggested_action', 'Follow up on manual payment collection before period end.'
    ));
  END IF;

  SELECT COUNT(*)::INT INTO v_failed_deliveries_24h
  FROM public.deliveries WHERE status = 'failed' AND failed_at > now() - interval '24 hours';
  IF v_failed_deliveries_24h >= 25 THEN
    v_alerts := v_alerts || jsonb_build_array(jsonb_build_object(
      'severity', 'critical', 'title', 'Excessive delivery failures',
      'detail', v_failed_deliveries_24h || ' failed in 24h', 'href', '/admin/deliveries?status=failed',
      'entity', 'Delivery network', 'suggested_action', 'Check for a concentrated pattern (one company/branch) vs. a platform-wide issue.'
    ));
  ELSIF v_failed_deliveries_24h >= 10 THEN
    v_alerts := v_alerts || jsonb_build_array(jsonb_build_object(
      'severity', 'medium', 'title', 'Elevated delivery failures',
      'detail', v_failed_deliveries_24h || ' failed in 24h', 'href', '/admin/deliveries?status=failed',
      'entity', 'Delivery network', 'suggested_action', 'Monitor; escalate if the rate keeps climbing.'
    ));
  END IF;

  SELECT COUNT(*)::INT INTO v_companies_out_of_sms
  FROM public.companies WHERE status = 'active' AND sms_credits <= 0;
  IF v_companies_out_of_sms > 0 THEN
    v_alerts := v_alerts || jsonb_build_array(jsonb_build_object(
      'severity', 'high', 'title', 'Companies out of SMS credits',
      'detail', v_companies_out_of_sms || ' active companies at 0 credits', 'href', '/admin/companies?status=active',
      'entity', v_companies_out_of_sms || ' companies', 'suggested_action', 'Notify affected companies; consider a manual top-up if this is a billing gap.'
    ));
  END IF;

  SELECT COUNT(*)::INT INTO v_companies_low_sms
  FROM public.companies WHERE status = 'active' AND sms_credits > 0 AND sms_credits < 10;
  IF v_companies_low_sms > 0 THEN
    v_alerts := v_alerts || jsonb_build_array(jsonb_build_object(
      'severity', 'medium', 'title', 'Companies low on SMS credits',
      'detail', v_companies_low_sms || ' active companies below 10 credits', 'href', '/admin/companies?status=active',
      'entity', v_companies_low_sms || ' companies', 'suggested_action', 'Optional proactive outreach before they run out.'
    ));
  END IF;

  SELECT COUNT(*)::INT INTO v_api_auth_fail_1h
  FROM public.api_auth_events WHERE success = false AND created_at > now() - interval '1 hour';
  IF v_api_auth_fail_1h >= 20 THEN
    v_alerts := v_alerts || jsonb_build_array(jsonb_build_object(
      'severity', 'critical', 'title', 'Unusual API auth failure spike',
      'detail', v_api_auth_fail_1h || ' failed auth attempts in 1h', 'href', '/admin/security',
      'entity', 'Public API', 'suggested_action', 'Check api_auth_events for a concentrated key prefix; consider revoking if it looks like credential stuffing.'
    ));
  END IF;

  RETURN jsonb_build_object('alerts', v_alerts, 'checked_at', now());
END;
$$;
