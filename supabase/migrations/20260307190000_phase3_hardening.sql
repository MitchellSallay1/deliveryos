-- DeliveryOS · Phase 3: company status, subscription limits, team invites, payment RLS

-- ---------------------------------------------------------------------------
-- Operational guards (structured exception messages for the client)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assert_company_operational(p_company_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status public.company_status;
BEGIN
  SELECT status INTO v_status FROM public.companies WHERE id = p_company_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'company_not_found';
  END IF;
  IF v_status = 'suspended' THEN
    RAISE EXCEPTION 'company_suspended';
  END IF;
  IF v_status = 'pending' THEN
    RAISE EXCEPTION 'company_pending';
  END IF;
  IF v_status <> 'active' THEN
    RAISE EXCEPTION 'company_inactive';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.company_deliveries_in_billing_month(p_company_id UUID)
RETURNS INT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COUNT(*)::INT
  FROM public.deliveries d
  WHERE d.company_id = p_company_id
    AND d.created_at >= (
      date_trunc('month', (current_timestamp AT TIME ZONE 'Africa/Monrovia'))
      AT TIME ZONE 'Africa/Monrovia'
    )
    AND d.created_at < (
      (date_trunc('month', (current_timestamp AT TIME ZONE 'Africa/Monrovia')) + INTERVAL '1 month')
      AT TIME ZONE 'Africa/Monrovia'
    );
$$;

CREATE OR REPLACE FUNCTION public.assert_subscription_delivery_limit(p_company_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max INT;
  v_count INT;
BEGIN
  SELECT s.max_deliveries_per_month INTO v_max
  FROM public.companies c
  JOIN public.subscriptions s ON s.id = c.subscription_id
  WHERE c.id = p_company_id;

  IF v_max IS NULL THEN
    RETURN;
  END IF;

  v_count := public.company_deliveries_in_billing_month(p_company_id);
  IF v_count >= v_max THEN
    RAISE EXCEPTION 'delivery_monthly_limit_reached';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.company_has_sms_credits(p_company_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT sms_credits > 0 FROM public.companies WHERE id = p_company_id),
    false
  );
$$;

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
  SELECT COALESCE(
    (
      SELECT (s.features ->> p_feature_key)::BOOLEAN
      FROM public.companies c
      JOIN public.subscriptions s ON s.id = c.subscription_id
      WHERE c.id = p_company_id
    ),
    true
  );
$$;

-- ---------------------------------------------------------------------------
-- Patch SMS outbound
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.queue_outbound_sms(
  p_company_id UUID,
  p_phone TEXT,
  p_body TEXT,
  p_delivery_id UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_credits INT;
  v_balance INT;
BEGIN
  PERFORM public.assert_company_operational(p_company_id);

  IF NOT public.company_feature_enabled(p_company_id, 'sms') THEN
    RETURN false;
  END IF;

  IF p_phone IS NULL OR p_phone = '' OR p_body IS NULL OR p_body = '' THEN
    RETURN false;
  END IF;

  SELECT sms_credits INTO v_credits FROM public.companies WHERE id = p_company_id FOR UPDATE;
  IF NOT FOUND OR v_credits < 1 THEN
    RAISE EXCEPTION 'sms_credits_exhausted';
  END IF;

  v_balance := v_credits - 1;
  UPDATE public.companies SET sms_credits = v_balance WHERE id = p_company_id;

  INSERT INTO public.sms_credit_ledger (company_id, delta, balance_after, reason, reference_id)
  VALUES (p_company_id, -1, v_balance, 'outbound_sms', p_delivery_id);

  INSERT INTO public.sms_logs (company_id, direction, phone, body, credits_used, delivery_id)
  VALUES (p_company_id, 'outbound', p_phone, p_body, 1, p_delivery_id);

  INSERT INTO public.notification_logs (company_id, channel, recipient, body, status)
  VALUES (p_company_id, 'sms', p_phone, p_body, 'sent');

  RETURN true;
END;
$$;

-- ---------------------------------------------------------------------------
-- Patch create_delivery
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_delivery(
  p_company_id UUID,
  p_pickup_business_name TEXT,
  p_pickup_address TEXT,
  p_customer_name TEXT,
  p_customer_phone TEXT,
  p_destination_address TEXT,
  p_package_description TEXT DEFAULT NULL,
  p_amount_to_collect_lrd_cents INT DEFAULT 0,
  p_delivery_fee_lrd_cents INT DEFAULT 0,
  p_customer_id UUID DEFAULT NULL
)
RETURNS public.deliveries
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.deliveries;
  v_customer_id UUID := p_customer_id;
BEGIN
  PERFORM public.assert_company_dispatcher(p_company_id);
  PERFORM public.assert_company_operational(p_company_id);
  PERFORM public.assert_subscription_delivery_limit(p_company_id);

  IF v_customer_id IS NULL AND p_customer_phone IS NOT NULL THEN
    INSERT INTO public.customers (company_id, full_name, phone, address)
    VALUES (p_company_id, p_customer_name, p_customer_phone, p_destination_address)
    ON CONFLICT (company_id, phone) DO UPDATE SET
      full_name = EXCLUDED.full_name,
      address = COALESCE(EXCLUDED.address, public.customers.address)
    RETURNING id INTO v_customer_id;
  END IF;

  INSERT INTO public.deliveries (
    company_id, tracking_code, pickup_business_name, pickup_address,
    customer_id, customer_name, customer_phone, destination_address,
    package_description, amount_to_collect_lrd_cents, delivery_fee_lrd_cents,
    status, created_by
  ) VALUES (
    p_company_id, public.generate_tracking_code(),
    p_pickup_business_name, p_pickup_address, v_customer_id,
    p_customer_name, p_customer_phone, p_destination_address,
    p_package_description, COALESCE(p_amount_to_collect_lrd_cents, 0),
    COALESCE(p_delivery_fee_lrd_cents, 0), 'pending', auth.uid()
  )
  RETURNING * INTO v_row;

  INSERT INTO public.delivery_status_history (
    delivery_id, company_id, from_status, to_status, changed_by, note
  ) VALUES (
    v_row.id, p_company_id, NULL, 'pending', auth.uid(), 'created'
  );

  RETURN v_row;
END;
$$;

-- ---------------------------------------------------------------------------
-- Patch assign_delivery_rider (includes SMS hook from notifications migration)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assign_delivery_rider(
  p_delivery_id UUID,
  p_rider_id UUID
)
RETURNS public.deliveries
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.deliveries;
  v_from public.delivery_status;
BEGIN
  SELECT * INTO v_row FROM public.deliveries WHERE id = p_delivery_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'delivery not found';
  END IF;

  PERFORM public.assert_company_dispatcher(v_row.company_id);
  PERFORM public.assert_company_operational(v_row.company_id);

  IF v_row.status NOT IN ('pending', 'assigned') THEN
    RAISE EXCEPTION 'cannot assign from status %', v_row.status;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.riders r
    WHERE r.id = p_rider_id AND r.company_id = v_row.company_id AND r.status <> 'suspended'
  ) THEN
    RAISE EXCEPTION 'invalid rider';
  END IF;

  v_from := v_row.status;

  UPDATE public.deliveries SET
    status = 'assigned', rider_id = p_rider_id, assigned_at = now()
  WHERE id = p_delivery_id
  RETURNING * INTO v_row;

  INSERT INTO public.delivery_status_history (
    delivery_id, company_id, from_status, to_status, changed_by, note
  ) VALUES (
    p_delivery_id, v_row.company_id, v_from, 'assigned', auth.uid(), 'rider assigned'
  );

  PERFORM public.notify_rider_new_job(v_row);

  RETURN v_row;
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

-- Rider plan limit also requires active company
CREATE OR REPLACE FUNCTION public.enforce_rider_plan_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max INT;
  v_count INT;
  v_status public.company_status;
BEGIN
  SELECT c.status INTO v_status FROM public.companies c WHERE c.id = NEW.company_id;
  IF v_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'company_not_operational';
  END IF;

  SELECT s.max_riders INTO v_max
  FROM public.companies c
  JOIN public.subscriptions s ON s.id = c.subscription_id
  WHERE c.id = NEW.company_id;

  SELECT COUNT(*)::INT INTO v_count FROM public.riders WHERE company_id = NEW.company_id;

  IF v_count >= v_max THEN
    RAISE EXCEPTION 'rider_plan_limit_reached';
  END IF;

  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- RLS: block direct writes when company is not active
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.company_id_is_active(p_company_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.companies c
    WHERE c.id = p_company_id AND c.status = 'active'
  );
$$;

DROP POLICY IF EXISTS customers_write ON public.customers;
CREATE POLICY customers_write ON public.customers
  FOR ALL TO authenticated
  USING (
    (public.is_super_admin() OR public.has_company_role(
      company_id,
      ARRAY['company_owner', 'dispatcher', 'support_staff']::public.company_role[]
    ))
    AND (public.is_super_admin() OR public.company_id_is_active(company_id))
  )
  WITH CHECK (
    (public.is_super_admin() OR public.has_company_role(
      company_id,
      ARRAY['company_owner', 'dispatcher', 'support_staff']::public.company_role[]
    ))
    AND (public.is_super_admin() OR public.company_id_is_active(company_id))
  );

DROP POLICY IF EXISTS riders_write ON public.riders;
CREATE POLICY riders_write ON public.riders
  FOR ALL TO authenticated
  USING (
    (public.is_super_admin() OR public.has_company_role(
      company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[]
    ))
    AND (public.is_super_admin() OR public.company_id_is_active(company_id))
  )
  WITH CHECK (
    (public.is_super_admin() OR public.has_company_role(
      company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[]
    ))
    AND (public.is_super_admin() OR public.company_id_is_active(company_id))
  );

DROP POLICY IF EXISTS deliveries_insert ON public.deliveries;
CREATE POLICY deliveries_insert ON public.deliveries
  FOR INSERT TO authenticated
  WITH CHECK (
    (public.is_super_admin() OR public.has_company_role(
      company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[]
    ))
    AND (public.is_super_admin() OR public.company_id_is_active(company_id))
  );

-- ---------------------------------------------------------------------------
-- Payments: SELECT only via RLS; mutations via RPC
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS payments_write ON public.payments;

CREATE OR REPLACE FUNCTION public.mark_payment_reconciled(p_payment_id UUID)
RETURNS public.payments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.payments;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT * INTO v_row FROM public.payments WHERE id = p_payment_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'payment not found';
  END IF;

  IF NOT (
    public.is_super_admin()
    OR public.has_company_role(
      v_row.company_id,
      ARRAY['company_owner']::public.company_role[]
    )
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE public.payments
  SET status = 'reconciled', updated_at = now()
  WHERE id = p_payment_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_payment_reconciled TO authenticated;

-- ---------------------------------------------------------------------------
-- Team invitations
-- ---------------------------------------------------------------------------
CREATE TABLE public.company_invitations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  role public.company_role NOT NULL,
  token TEXT NOT NULL UNIQUE,
  invited_by UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL,
  accepted_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT company_invitations_role_check CHECK (
    role IN ('dispatcher', 'support_staff', 'rider', 'company_owner')
  )
);

CREATE INDEX idx_company_invitations_company ON public.company_invitations (company_id, created_at DESC);
CREATE UNIQUE INDEX idx_company_invitations_pending_email
  ON public.company_invitations (company_id, lower(email))
  WHERE accepted_at IS NULL AND revoked_at IS NULL;

ALTER TABLE public.company_invitations ENABLE ROW LEVEL SECURITY;

CREATE POLICY company_invitations_select ON public.company_invitations
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR public.has_company_role(company_id, ARRAY['company_owner']::public.company_role[])
    OR (
      lower(email) = lower((SELECT email FROM auth.users WHERE id = auth.uid()))
      AND revoked_at IS NULL
      AND accepted_at IS NULL
      AND expires_at > now()
    )
  );

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
  v_id UUID;
  v_row public.company_invitations;
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

  v_token := encode(gen_random_bytes(24), 'hex');

  INSERT INTO public.company_invitations (company_id, email, role, token, invited_by, expires_at)
  VALUES (p_company_id, lower(trim(p_email)), p_role, v_token, auth.uid(), now() + INTERVAL '7 days')
  RETURNING * INTO v_row;

  RETURN jsonb_build_object(
    'id', v_row.id,
    'token', v_row.token,
    'email', v_row.email,
    'role', v_row.role,
    'expires_at', v_row.expires_at
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_company_invitation TO authenticated;

CREATE OR REPLACE FUNCTION public.revoke_company_invitation(p_invitation_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company UUID;
BEGIN
  SELECT company_id INTO v_company FROM public.company_invitations WHERE id = p_invitation_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'invitation not found';
  END IF;
  IF NOT public.has_company_role(v_company, ARRAY['company_owner']::public.company_role[])
    AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  UPDATE public.company_invitations SET revoked_at = now()
  WHERE id = p_invitation_id AND accepted_at IS NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION public.revoke_company_invitation TO authenticated;

CREATE OR REPLACE FUNCTION public.accept_company_invitation(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inv public.company_invitations;
  v_user_email TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT email INTO v_user_email FROM auth.users WHERE id = auth.uid();

  SELECT * INTO v_inv
  FROM public.company_invitations
  WHERE token = p_token
    AND revoked_at IS NULL
    AND accepted_at IS NULL
    AND expires_at > now()
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invitation_invalid';
  END IF;

  IF lower(v_user_email) <> lower(v_inv.email) THEN
    RAISE EXCEPTION 'invitation_email_mismatch';
  END IF;

  PERFORM public.assert_company_operational(v_inv.company_id);

  INSERT INTO public.company_users (company_id, user_id, role, is_active)
  VALUES (v_inv.company_id, auth.uid(), v_inv.role, true)
  ON CONFLICT (company_id, user_id) DO UPDATE SET
    role = EXCLUDED.role,
    is_active = true;

  UPDATE public.company_invitations SET accepted_at = now() WHERE id = v_inv.id;

  RETURN jsonb_build_object(
    'company_id', v_inv.company_id,
    'role', v_inv.role
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.accept_company_invitation TO authenticated;

CREATE OR REPLACE FUNCTION public.set_company_member_active(
  p_membership_id UUID,
  p_is_active BOOLEAN
)
RETURNS public.company_users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.company_users;
BEGIN
  SELECT * INTO v_row FROM public.company_users WHERE id = p_membership_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'member not found';
  END IF;
  IF NOT public.has_company_role(v_row.company_id, ARRAY['company_owner']::public.company_role[])
    AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF v_row.user_id = auth.uid() AND p_is_active = false THEN
    RAISE EXCEPTION 'cannot_disable_self';
  END IF;
  UPDATE public.company_users SET is_active = p_is_active WHERE id = p_membership_id
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_company_member_active TO authenticated;

CREATE OR REPLACE FUNCTION public.update_company_member_role(
  p_membership_id UUID,
  p_role public.company_role
)
RETURNS public.company_users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.company_users;
BEGIN
  SELECT * INTO v_row FROM public.company_users WHERE id = p_membership_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'member not found';
  END IF;
  IF NOT public.has_company_role(v_row.company_id, ARRAY['company_owner']::public.company_role[])
    AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF p_role = 'company_owner' AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'cannot_assign_owner';
  END IF;
  UPDATE public.company_users SET role = p_role WHERE id = p_membership_id
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_company_member_role TO authenticated;

CREATE OR REPLACE FUNCTION public.list_company_team(p_company_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT (
    public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY['company_owner']::public.company_role[])
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  RETURN (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', cu.id,
      'user_id', cu.user_id,
      'role', cu.role,
      'is_active', cu.is_active,
      'created_at', cu.created_at,
      'email', u.email,
      'full_name', p.full_name
    ) ORDER BY cu.created_at), '[]'::JSONB)
    FROM public.company_users cu
    JOIN auth.users u ON u.id = cu.user_id
    LEFT JOIN public.profiles p ON p.id = cu.user_id
    WHERE cu.company_id = p_company_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_company_team TO authenticated;

CREATE OR REPLACE FUNCTION public.list_company_invitations(p_company_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT (
    public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY['company_owner']::public.company_role[])
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  RETURN (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', i.id,
      'email', i.email,
      'role', i.role,
      'token', i.token,
      'expires_at', i.expires_at,
      'created_at', i.created_at,
      'revoked_at', i.revoked_at,
      'accepted_at', i.accepted_at
    ) ORDER BY i.created_at DESC), '[]'::JSONB)
    FROM public.company_invitations i
    WHERE i.company_id = p_company_id
      AND i.accepted_at IS NULL
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_company_invitations TO authenticated;

CREATE OR REPLACE FUNCTION public.get_invitation_by_token(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inv public.company_invitations;
  v_company_name TEXT;
BEGIN
  SELECT * INTO v_inv
  FROM public.company_invitations
  WHERE token = p_token
    AND revoked_at IS NULL
    AND accepted_at IS NULL
    AND expires_at > now();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invitation_invalid';
  END IF;

  SELECT name INTO v_company_name FROM public.companies WHERE id = v_inv.company_id;

  RETURN jsonb_build_object(
    'email', v_inv.email,
    'role', v_inv.role,
    'company_name', v_company_name,
    'expires_at', v_inv.expires_at
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_invitation_by_token TO authenticated, anon;

-- Dispatcher transitions require operational company
CREATE OR REPLACE FUNCTION public.transition_delivery_status(
  p_delivery_id UUID,
  p_to_status public.delivery_status,
  p_note TEXT DEFAULT NULL
)
RETURNS public.deliveries
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company UUID;
BEGIN
  SELECT company_id INTO v_company FROM public.deliveries WHERE id = p_delivery_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'delivery not found';
  END IF;
  PERFORM public.assert_company_operational(v_company);
  PERFORM public.assert_company_dispatcher(v_company);
  RETURN public.delivery_transition_core(p_delivery_id, p_to_status, COALESCE(p_note, ''), auth.uid());
END;
$$;

CREATE OR REPLACE FUNCTION public.rider_transition_delivery_status(
  p_delivery_id UUID,
  p_to_status public.delivery_status,
  p_note TEXT DEFAULT NULL
)
RETURNS public.deliveries
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.deliveries;
  v_from public.delivery_status;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT * INTO v_row FROM public.deliveries WHERE id = p_delivery_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'delivery not found';
  END IF;

  PERFORM public.assert_company_operational(v_row.company_id);

  IF NOT EXISTS (
    SELECT 1 FROM public.riders r
    WHERE r.id = v_row.rider_id AND r.user_id = auth.uid() AND r.company_id = v_row.company_id
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  v_from := v_row.status;

  IF p_to_status IN ('pending', 'assigned', 'cancelled') THEN
    RAISE EXCEPTION 'rider cannot set status to %', p_to_status;
  END IF;

  IF NOT public.delivery_can_transition(v_from, p_to_status) THEN
    RAISE EXCEPTION 'invalid transition from % to %', v_from, p_to_status;
  END IF;

  RETURN public.delivery_transition_core(
    p_delivery_id, p_to_status, COALESCE(p_note, 'rider app'), auth.uid()
  );
END;
$$;
