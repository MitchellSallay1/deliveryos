-- DeliveryOS — Production Domain Readiness (soft-launch preparation).
--
-- Scope: exactly one real deployment problem discovered while auditing the
-- app for its real domain, fixed at its source. Everything else in this
-- audit (frontend build/hosting config, security headers, env-var
-- handling, favicon) is frontend/config-only and needs no database change
-- — reported separately, not migrated here.
--
-- Problem found: notify_customer_tracking (20260307160000_notifications_
-- sms.sql) builds the customer tracking-SMS link from the Postgres GUC
-- app.public_url, falling back to 'http://localhost:5173' if that GUC was
-- never set. Repo-wide search confirms app.public_url is never set by any
-- migration and is undocumented as a required manual step anywhere in
-- docs/ — meaning on the current production database this fallback is
-- almost certainly still active today, and every "your package is on the
-- way" SMS sent to a real customer contains a dead localhost link. The
-- companion GUC app.sms_provider (same undocumented-manual-config pattern,
-- used only as a bookkeeping label on sms_outbox.provider) is left
-- untouched — real SMS delivery already goes through the sms-dispatch
-- Edge Function's own SMS_PROVIDER secret, confirmed production-verified,
-- so there is no equivalent live bug there.
--
-- Fix: once app.public_url is set (see the manual step below — no
-- migration can set a per-environment public URL, this must be configured
-- against the actual production database), the link behaves exactly as
-- before. If it is ever unset again in the future, the function now omits
-- the tracking line entirely rather than sending a broken link — a
-- customer still gets their status update by SMS either way.
--
-- Required one-time manual step (run once against the production
-- database, e.g. via the Supabase SQL Editor — not part of this
-- migration, since the correct value is environment-specific):
--   ALTER DATABASE postgres SET app.public_url = 'https://app.<your-domain>';
-- Then either reconnect/start a new session, or run
-- SELECT pg_reload_conf(); to pick it up without a restart.
CREATE OR REPLACE FUNCTION public.notify_customer_tracking(
  p_delivery public.deliveries,
  p_status public.delivery_status
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_body TEXT;
  v_base_url TEXT;
  v_track TEXT;
BEGIN
  v_base_url := nullif(current_setting('app.public_url', true), '');
  v_track := CASE WHEN v_base_url IS NOT NULL THEN v_base_url || '/track/' || p_delivery.tracking_code ELSE NULL END;

  IF p_status IN ('picked_up', 'in_transit') THEN
    IF v_track IS NOT NULL THEN
      v_body := format(
        E'Hello %s\nYour package is on the way.\nStatus: %s\nTrack: %s',
        p_delivery.customer_name,
        replace(p_status::TEXT, '_', ' '),
        v_track
      );
    ELSE
      v_body := format(
        E'Hello %s\nYour package is on the way.\nStatus: %s',
        p_delivery.customer_name,
        replace(p_status::TEXT, '_', ' ')
      );
    END IF;
  ELSIF p_status = 'delivered' THEN
    v_body := format(E'Hello %s\nYour package was delivered. Thank you!', p_delivery.customer_name);
  ELSE
    RETURN;
  END IF;

  PERFORM public.queue_outbound_sms(
    p_delivery.company_id,
    p_delivery.customer_phone,
    v_body,
    p_delivery.id
  );
END;
$$;
