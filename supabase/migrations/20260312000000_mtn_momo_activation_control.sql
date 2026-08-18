-- DeliveryOS — MTN MoMo collection activation control (production
-- activation-control audit, Commerce Phase E2 follow-up).
--
-- PRODUCTION FINANCIAL SYSTEM. Audited whether MTN MoMo collection could
-- become reachable by a real customer immediately after Phase E2's
-- migration/code deploys. It could: initiate_commerce_order_mtn_payment had
-- no platform-wide gate at all — only a per-company plan check
-- (can_use_feature(..., 'commerce_enabled')) and mtn-collect's own
-- credentials-presence check, neither of which is a deliberate,
-- Super-Admin-controlled "go live" switch. A vendor with commerce enabled
-- and (once configured) real WinAggregator credentials in place would have
-- been able to collect real money the moment this code shipped, with no
-- explicit activation step and no way to instantly disable it without a
-- redeploy.
--
-- Reused architecture, not invented: platform_settings + get_platform_
-- setting + admin_list_platform_settings + admin_set_platform_setting
-- already exist (20260309230000_platform_settings_public_app_url.sql) as
-- this codebase's one Super-Admin-controlled runtime configuration
-- mechanism (typed key/value rows, SECURITY DEFINER RPCs, zero direct
-- client RLS access, small explicit key allowlist). That migration is
-- already committed, so this one extends it in place via CREATE OR REPLACE
-- rather than editing history — exactly how a second setting was always
-- meant to be added (see that migration's own comment: "extend the
-- allowlist here when a future setting ... is actually built").
--
-- New setting: mtn_momo_collections_enabled ('true'/'false', TEXT-typed
-- like every other row in this table). Seeded 'false' — MTN collection is
-- OFF by default in every environment, including production, until a
-- Super Admin deliberately turns it on. No code deployment is needed to
-- flip it: admin_set_platform_setting is a live RPC, and initiate_
-- commerce_order_mtn_payment reads it via get_platform_setting on every
-- call (STABLE, not cached across calls).
--
-- The actual enforcement point is initiate_commerce_order_mtn_payment
-- itself (edited in place in 20260311000000, since that whole migration is
-- still unreleased/uncommitted at the time of this audit) — the ONE RPC
-- that can ever create a payment_attempts row. This is deliberate: a
-- SECURITY DEFINER RPC gate cannot be bypassed by a direct client RPC call
-- the way a frontend-only check could, and mtn-collect (the Edge Function)
-- calls this exact RPC first, so it inherits the same gate for free with
-- no duplicated logic to drift out of sync.
--
-- This is independent of, and does not replace, mtn-collect's existing
-- credentials-presence check (WINAGGREGATOR_MTN_SECRET_STRING/
-- _COMPANY_NAME missing -> 503 before any payment_attempts row is created).
-- Missing credentials fail closed on their own; an operator could
-- misconfigure or accidentally unset credentials and this setting would
-- still independently need to be 'true' for a request to even reach that
-- check, and vice versa — flipping this setting to 'true' with no
-- credentials configured still fails closed at the Edge Function. Neither
-- condition alone is suffient to collect money; both must independently be
-- satisfied.
--
-- Disabling never destroys visibility: this gate lives ONLY in initiate_
-- commerce_order_mtn_payment (new-attempt creation). record_payment_
-- attempt_result, admin_reconcile_payment_attempt, sweep_stuck_payment_
-- attempts, admin_list_payment_attempts_page, and payment_attempts' own
-- RLS SELECT policy are completely untouched — existing pending/unknown/
-- successful attempts remain fully readable and reconcilable regardless of
-- this setting's value. COD and Orange Money are untouched by this
-- migration entirely: COD never calls this RPC, and orange_money is
-- already unconditionally rejected in submit_commerce_order.
CREATE OR REPLACE FUNCTION public.admin_set_platform_setting(p_key TEXT, p_value TEXT)
RETURNS public.platform_settings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_value TEXT := NULLIF(trim(COALESCE(p_value, '')), '');
  v_row public.platform_settings;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF p_key NOT IN ('public_app_url', 'mtn_momo_collections_enabled') THEN
    RAISE EXCEPTION 'invalid_setting_key';
  END IF;

  IF p_key = 'public_app_url' AND v_value IS NOT NULL AND v_value !~ '^https://' THEN
    RAISE EXCEPTION 'invalid_public_app_url';
  END IF;
  -- Store without a trailing slash so callers can always concatenate
  -- '/path' directly.
  IF p_key = 'public_app_url' AND v_value IS NOT NULL THEN
    v_value := regexp_replace(v_value, '/+$', '');
  END IF;

  -- A kill switch that silently accepted a garbage value and was then read
  -- via `= 'true'` would fail closed by accident, which is safe but
  -- confusing (an admin typo would look like "successfully saved" while
  -- actually leaving collection disabled). Reject anything but an explicit
  -- true/false instead, and require a value at all — this setting has no
  -- meaningful "unset" state distinct from 'false'.
  IF p_key = 'mtn_momo_collections_enabled' AND COALESCE(v_value, '') NOT IN ('true', 'false') THEN
    RAISE EXCEPTION 'invalid_boolean_setting_value';
  END IF;

  INSERT INTO public.platform_settings (key, value, updated_by)
  VALUES (p_key, v_value, auth.uid())
  ON CONFLICT (key) DO UPDATE SET
    value = EXCLUDED.value,
    updated_at = now(),
    updated_by = EXCLUDED.updated_by
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_platform_setting(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_platform_setting(TEXT, TEXT) TO authenticated;

-- Defaults OFF everywhere, including production — a Super Admin must
-- deliberately flip this to 'true' via admin_set_platform_setting (no code
-- deployment required) before any customer can be charged.
INSERT INTO public.platform_settings (key, value, description)
VALUES (
  'mtn_momo_collections_enabled',
  'false',
  'When ''true'', MTN MoMo real-money collection is live for eligible orders. Defaults to false — a Super Admin must deliberately activate it. Independent of WINAGGREGATOR_MTN_* credentials: both this setting AND valid credentials are required for a collection to actually be attempted.'
)
ON CONFLICT (key) DO NOTHING;
