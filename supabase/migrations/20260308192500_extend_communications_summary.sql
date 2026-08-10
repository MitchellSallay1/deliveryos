-- ---------------------------------------------------------------------------
-- Communications page needs inbound SMS command volume (provider-neutral —
-- populated once carrier SMS/USSD is wired up, honestly zero until then)
-- and a delivery-notification breakdown by channel. CREATE OR REPLACE on an
-- existing function, same signature, same is_super_admin() gate. No schema/
-- RLS/tenant/auth/billing/rider/delivery-state-machine/MTN/MoMo change —
-- this only adds two more read-only aggregates from tables that already
-- exist (sms_logs.direction, notification_logs.channel).
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
      'failed', (SELECT COUNT(*)::INT FROM public.sms_outbox WHERE status = 'failed' AND created_at >= v_since),
      'inbound_commands', (SELECT COUNT(*)::INT FROM public.sms_logs WHERE direction = 'inbound' AND created_at >= v_since)
    ),
    'email', jsonb_build_object(
      'pending', (SELECT COUNT(*)::INT FROM public.email_outbox WHERE status IN ('pending', 'failed')),
      'sent', (SELECT COUNT(*)::INT FROM public.email_outbox WHERE status = 'sent' AND created_at >= v_since)
    ),
    'notifications', (
      SELECT COUNT(*)::INT FROM public.notification_logs WHERE created_at >= v_since
    ),
    'notifications_by_channel', (
      SELECT COALESCE(jsonb_object_agg(channel, cnt), '{}'::JSONB)
      FROM (
        SELECT channel, COUNT(*)::INT AS cnt
        FROM public.notification_logs
        WHERE created_at >= v_since
        GROUP BY channel
      ) q
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_admin_communications_summary TO authenticated;
