-- DeliveryOS — platform_settings table, replacing the app.public_url GUC.
--
-- The previous fix (20260309220000_production_domain_readiness.sql) read
-- the tracking-SMS base URL from the Postgres GUC app.public_url. On
-- hosted Supabase this is unusable: `ALTER DATABASE ... SET app.public_url`
-- fails with `ERROR 42501: permission denied to set parameter` — the
-- hosted `postgres` migration role is not a superuser and cannot set
-- arbitrary custom GUCs at the database level. That was a real deployment
-- blocker, not a style preference, so this migration replaces the
-- mechanism entirely rather than trying to work around the permission.
--
-- Replacement: a small, durable `platform_settings` table — exactly the
-- table the pre-existing Admin Configuration page placeholder already
-- named ("Support contact and maintenance banner hooks can be added via
-- the platform_settings table in a future migration", src/pages/admin/
-- platform-config.tsx) — reused rather than inventing a differently-named
-- mechanism. No existing platform/app/system config table was found
-- anywhere else in the schema (confirmed by search) before adding this
-- one.
--
-- Not a secrets store: the value held here (a public app URL) is not
-- secret, and Vault is deliberately not used for it, per the same
-- reasoning already applied everywhere else in this schema (e.g.
-- commerce_fee_rules, provider_marketplace_profiles) — Super-Admin-
-- controlled configuration lives in a plain table with SECURITY DEFINER
-- RPCs gating access, matching this codebase's established convention.
CREATE TABLE public.platform_settings (
  key TEXT PRIMARY KEY,
  value TEXT,
  description TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by UUID REFERENCES auth.users (id) ON DELETE SET NULL
);

-- RLS enabled with zero policies for authenticated/anon — identical
-- posture to commerce_fee_rules/commerce_ledger_entries/etc. elsewhere in
-- this schema: no client role can read or write the table directly, every
-- access goes through a SECURITY DEFINER RPC below.
ALTER TABLE public.platform_settings ENABLE ROW LEVEL SECURITY;

-- Internal-only read seam: not client-callable (no GRANT to authenticated
-- at all), reachable only from within another SECURITY DEFINER function —
-- the same "internal seam" idiom used throughout this schema (e.g.
-- mark_commerce_order_paid). Returns NULL for an unset or empty value so
-- callers can treat "not configured" uniformly.
CREATE OR REPLACE FUNCTION public.get_platform_setting(p_key TEXT)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT NULLIF(value, '') FROM public.platform_settings WHERE key = p_key;
$$;

REVOKE ALL ON FUNCTION public.get_platform_setting(TEXT) FROM PUBLIC;

-- Super Admin read/write RPCs for the settings page
-- (src/pages/admin/platform-config.tsx). A small explicit key allowlist
-- keeps this from becoming an uncontrolled arbitrary key-value store —
-- extend the allowlist here when a future setting (support contact,
-- maintenance banner, ...) is actually built, per the placeholder page's
-- own stated intent.
CREATE OR REPLACE FUNCTION public.admin_list_platform_settings()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows JSONB;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.key), '[]'::JSONB) INTO v_rows
  FROM public.platform_settings s;

  RETURN v_rows;
END;
$$;

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

  IF p_key NOT IN ('public_app_url') THEN
    RAISE EXCEPTION 'invalid_setting_key';
  END IF;

  IF p_key = 'public_app_url' AND v_value IS NOT NULL AND v_value !~ '^https://' THEN
    RAISE EXCEPTION 'invalid_public_app_url';
  END IF;
  -- Store without a trailing slash so callers can always concatenate
  -- '/path' directly.
  IF v_value IS NOT NULL THEN
    v_value := regexp_replace(v_value, '/+$', '');
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

REVOKE ALL ON FUNCTION public.admin_list_platform_settings() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_platform_settings() TO authenticated;
REVOKE ALL ON FUNCTION public.admin_set_platform_setting(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_platform_setting(TEXT, TEXT) TO authenticated;

-- Seed the row as unset (not the literal domain — Super Admin sets the
-- real value via the admin UI/RPC after this migration deploys). Keeps
-- get_platform_setting's "row exists but empty" and "row never created"
-- cases behaviorally identical either way, and gives the admin list page
-- something to show immediately.
INSERT INTO public.platform_settings (key, value, description)
VALUES ('public_app_url', NULL, 'Public app origin used to build customer-facing links (e.g. delivery tracking SMS). Example: https://app.example.com — no trailing slash.')
ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------------------
-- notify_customer_tracking: identical body to the previous version, except
-- the base URL now comes from get_platform_setting('public_app_url')
-- instead of the unusable-on-hosted-Supabase app.public_url GUC. Behavior
-- when unset is unchanged from the prior fix: omit the tracking line
-- rather than ever emitting a broken/placeholder link. No domain is
-- hardcoded anywhere in this function.
-- ---------------------------------------------------------------------------
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
  v_base_url := public.get_platform_setting('public_app_url');
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
