-- Portable random tokens (no gen_random_bytes) + ensure pgcrypto for SHA-256 API key hashing

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION public.random_token_hex(p_length INT)
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE
SET search_path = public
AS $$
DECLARE
  v_result TEXT := '';
BEGIN
  IF p_length IS NULL OR p_length < 1 THEN
    RAISE EXCEPTION 'invalid token length';
  END IF;

  WHILE length(v_result) < p_length LOOP
    v_result := v_result || replace(gen_random_uuid()::text, '-', '');
  END LOOP;

  RETURN substr(v_result, 1, p_length);
END;
$$;

REVOKE ALL ON FUNCTION public.random_token_hex(INT) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.generate_tracking_code()
RETURNS TEXT
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_code TEXT;
BEGIN
  LOOP
    v_code := 'DLV-' || upper(public.random_token_hex(12));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.deliveries d WHERE d.tracking_code = v_code);
  END LOOP;
  RETURN v_code;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_company_api_key(
  p_company_id UUID,
  p_name TEXT,
  p_permissions JSONB,
  p_expires_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_plain TEXT;
  v_prefix TEXT;
  v_hash TEXT;
  v_id UUID;
BEGIN
  IF NOT public.can_use_feature(p_company_id, 'api_access') THEN
    RAISE EXCEPTION 'api_not_enabled';
  END IF;

  IF NOT public.has_company_role(p_company_id, ARRAY['company_owner']::public.company_role[])
     AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  v_plain := 'dos_' || public.random_token_hex(48);
  v_prefix := substr(v_plain, 1, 12);
  v_hash := encode(extensions.digest(v_plain, 'sha256'), 'hex');

  INSERT INTO public.api_keys (
    company_id, name, key_prefix, hashed_key, permissions, expires_at, created_by
  ) VALUES (
    p_company_id, p_name, v_prefix, v_hash, COALESCE(p_permissions, '[]'::JSONB), p_expires_at, auth.uid()
  )
  RETURNING id INTO v_id;

  PERFORM public.log_audit_event(
    p_company_id, 'api_key_created', 'api_keys', v_id,
    jsonb_build_object('name', p_name, 'permissions', p_permissions)
  );

  RETURN jsonb_build_object(
    'id', v_id,
    'api_key', v_plain,
    'key_prefix', v_prefix,
    'message', 'Store this key securely; it cannot be retrieved again.'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_webhook_endpoint(p_payload JSONB)
RETURNS public.webhook_endpoints
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID := (p_payload ->> 'company_id')::UUID;
  v_id UUID := NULLIF(p_payload ->> 'id', '')::UUID;
  v_row public.webhook_endpoints;
  v_secret TEXT;
BEGIN
  IF NOT public.has_company_role(v_company_id, ARRAY['company_owner']::public.company_role[])
     AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  v_secret := COALESCE(p_payload ->> 'secret', public.random_token_hex(64));

  IF v_id IS NULL THEN
    INSERT INTO public.webhook_endpoints (company_id, url, secret, events, is_active)
    VALUES (
      v_company_id,
      p_payload ->> 'url',
      v_secret,
      ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_payload -> 'events', '[]'::JSONB))),
      COALESCE((p_payload ->> 'is_active')::BOOLEAN, true)
    )
    RETURNING * INTO v_row;
  ELSE
    UPDATE public.webhook_endpoints SET
      url = COALESCE(p_payload ->> 'url', url),
      events = CASE
        WHEN p_payload ? 'events' THEN ARRAY(SELECT jsonb_array_elements_text(p_payload -> 'events'))
        ELSE events
      END,
      is_active = COALESCE((p_payload ->> 'is_active')::BOOLEAN, is_active)
    WHERE id = v_id AND company_id = v_company_id
    RETURNING * INTO v_row;
  END IF;

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_company_invitation(
  p_company_id UUID,
  p_email TEXT,
  p_role public.company_role
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_token TEXT;
  v_row public.company_invitations;
  v_company public.companies;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  PERFORM public.assert_company_operational(p_company_id);
  IF NOT public.has_company_role(p_company_id, ARRAY['company_owner']::public.company_role[])
    AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF p_role = 'company_owner' AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'cannot_invite_owner';
  END IF;

  v_token := public.random_token_hex(48);

  INSERT INTO public.company_invitations (company_id, email, role, token, invited_by, expires_at)
  VALUES (p_company_id, lower(trim(p_email)), p_role, v_token, auth.uid(), now() + INTERVAL '7 days')
  RETURNING * INTO v_row;

  SELECT * INTO v_company FROM public.companies WHERE id = p_company_id;

  PERFORM public.queue_email(
    lower(trim(p_email)),
    'team_invite',
    format('You are invited to %s on DeliveryOS', v_company.name),
    format(
      '<p>You have been invited to join <strong>%s</strong> on DeliveryOS.</p><p>Use your invitation link to accept.</p>',
      v_company.name
    ),
    format('You have been invited to join %s on DeliveryOS.', v_company.name),
    p_company_id,
    jsonb_build_object('invitation_id', v_row.id, 'token', v_token)
  );

  PERFORM public.log_audit_event(p_company_id, 'invitation_created', 'company_invitations', v_row.id, to_jsonb(v_row));

  RETURN jsonb_build_object(
    'id', v_row.id,
    'token', v_row.token,
    'email', v_row.email,
    'role', v_row.role,
    'expires_at', v_row.expires_at
  );
END;
$$;
