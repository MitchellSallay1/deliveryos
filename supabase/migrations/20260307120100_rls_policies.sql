-- DeliveryOS · Row Level Security
-- Principle: every query is scoped by company_id; super_admin bypass via is_super_admin.

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.riders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sms_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- Helper functions (SECURITY DEFINER, stable checks for policies)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT is_super_admin FROM public.profiles WHERE id = auth.uid()),
    false
  );
$$;

CREATE OR REPLACE FUNCTION public.user_company_ids()
RETURNS SETOF UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT company_id
  FROM public.company_users
  WHERE user_id = auth.uid() AND is_active = true;
$$;

CREATE OR REPLACE FUNCTION public.has_company_role(p_company_id UUID, p_roles public.company_role[])
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.company_users cu
    WHERE cu.company_id = p_company_id
      AND cu.user_id = auth.uid()
      AND cu.is_active = true
      AND cu.role = ANY (p_roles)
  );
$$;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
CREATE POLICY profiles_select_own ON public.profiles
  FOR SELECT TO authenticated
  USING (id = auth.uid() OR public.is_super_admin());

CREATE POLICY profiles_update_own ON public.profiles
  FOR UPDATE TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- ---------------------------------------------------------------------------
-- subscriptions & roles (read-only catalog)
-- ---------------------------------------------------------------------------
CREATE POLICY subscriptions_read ON public.subscriptions
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY roles_read ON public.roles
  FOR SELECT TO authenticated
  USING (true);

-- ---------------------------------------------------------------------------
-- companies
-- ---------------------------------------------------------------------------
CREATE POLICY companies_select_member ON public.companies
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR id IN (SELECT public.user_company_ids())
  );

CREATE POLICY companies_update_owner ON public.companies
  FOR UPDATE TO authenticated
  USING (
    public.is_super_admin()
    OR public.has_company_role(id, ARRAY['company_owner']::public.company_role[])
  )
  WITH CHECK (
    public.is_super_admin()
    OR public.has_company_role(id, ARRAY['company_owner']::public.company_role[])
  );

-- ---------------------------------------------------------------------------
-- company_users
-- ---------------------------------------------------------------------------
CREATE POLICY company_users_select ON public.company_users
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR company_id IN (SELECT public.user_company_ids())
  );

CREATE POLICY company_users_manage_owner ON public.company_users
  FOR ALL TO authenticated
  USING (
    public.is_super_admin()
    OR public.has_company_role(company_id, ARRAY['company_owner']::public.company_role[])
  )
  WITH CHECK (
    public.is_super_admin()
    OR public.has_company_role(company_id, ARRAY['company_owner']::public.company_role[])
  );

-- ---------------------------------------------------------------------------
-- Tenant tables: company_id isolation + role gates on writes
-- ---------------------------------------------------------------------------
CREATE POLICY riders_tenant ON public.riders
  FOR SELECT TO authenticated
  USING (company_id IN (SELECT public.user_company_ids()) OR public.is_super_admin());

CREATE POLICY riders_write ON public.riders
  FOR ALL TO authenticated
  USING (
    public.is_super_admin()
    OR public.has_company_role(company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[])
  )
  WITH CHECK (
    public.is_super_admin()
    OR public.has_company_role(company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[])
  );

CREATE POLICY customers_tenant ON public.customers
  FOR SELECT TO authenticated
  USING (company_id IN (SELECT public.user_company_ids()) OR public.is_super_admin());

CREATE POLICY customers_write ON public.customers
  FOR ALL TO authenticated
  USING (
    public.is_super_admin()
    OR public.has_company_role(company_id, ARRAY['company_owner', 'dispatcher', 'support_staff']::public.company_role[])
  )
  WITH CHECK (
    public.is_super_admin()
    OR public.has_company_role(company_id, ARRAY['company_owner', 'dispatcher', 'support_staff']::public.company_role[])
  );

CREATE POLICY deliveries_select ON public.deliveries
  FOR SELECT TO authenticated
  USING (company_id IN (SELECT public.user_company_ids()) OR public.is_super_admin());

CREATE POLICY deliveries_write ON public.deliveries
  FOR ALL TO authenticated
  USING (
    public.is_super_admin()
    OR public.has_company_role(company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[])
  )
  WITH CHECK (
    public.is_super_admin()
    OR public.has_company_role(company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[])
  );

CREATE POLICY delivery_history_select ON public.delivery_status_history
  FOR SELECT TO authenticated
  USING (company_id IN (SELECT public.user_company_ids()) OR public.is_super_admin());

CREATE POLICY delivery_history_insert ON public.delivery_status_history
  FOR INSERT TO authenticated
  WITH CHECK (
    public.is_super_admin()
    OR public.has_company_role(company_id, ARRAY['company_owner', 'dispatcher', 'rider']::public.company_role[])
  );

CREATE POLICY payments_tenant ON public.payments
  FOR SELECT TO authenticated
  USING (company_id IN (SELECT public.user_company_ids()) OR public.is_super_admin());

CREATE POLICY payments_write ON public.payments
  FOR ALL TO authenticated
  USING (
    public.is_super_admin()
    OR public.has_company_role(company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[])
  )
  WITH CHECK (
    public.is_super_admin()
    OR public.has_company_role(company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[])
  );

CREATE POLICY notification_logs_tenant ON public.notification_logs
  FOR SELECT TO authenticated
  USING (
    company_id IS NULL
    OR company_id IN (SELECT public.user_company_ids())
    OR public.is_super_admin()
  );

CREATE POLICY sms_logs_tenant ON public.sms_logs
  FOR SELECT TO authenticated
  USING (company_id IN (SELECT public.user_company_ids()) OR public.is_super_admin());

CREATE POLICY delivery_photos_tenant ON public.delivery_photos
  FOR SELECT TO authenticated
  USING (company_id IN (SELECT public.user_company_ids()) OR public.is_super_admin());

CREATE POLICY delivery_photos_write ON public.delivery_photos
  FOR INSERT TO authenticated
  WITH CHECK (
    public.is_super_admin()
    OR public.has_company_role(company_id, ARRAY['company_owner', 'dispatcher', 'rider']::public.company_role[])
  );

-- Realtime: enable on deliveries in Supabase dashboard or:
-- alter publication supabase_realtime add table public.deliveries;
