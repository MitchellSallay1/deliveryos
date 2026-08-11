-- DeliveryOS Commerce — Phase A: Foundation
--
-- Schema + RLS + RPCs only. No public storefront UI, checkout UI, or
-- carrier-selection UI ships in this phase (none exists in the frontend
-- after this migration). No MoMo/Orange integration, no finance/settlement
-- ledger, no automatic payouts, no ratings/reviews, no promoted listings,
-- no multi-vendor carts, no SKU-variant matrices — all deliberately
-- deferred to later Commerce phases per the approved architecture plan.
--
-- Reuses, per the approved design:
--   - business_type = 'merchant' (unchanged) as the Vendor actor — no new
--     persona/role is introduced.
--   - public.marketplace_fee_model enum (fixed/percentage/subscription_only/
--     zero_commission) directly, for commerce_fee_rules — same fee-model
--     shape as the existing B2B marketplace, not a duplicate enum.
--   - the existing company_branches/delivery_zones tables remain the vendor
--     pickup-location/carrier-zone story — untouched here.
--   - the existing delivery_requests/delivery_offers/accept_marketplace_offer()
--     pipeline is the intended Commerce fulfillment path (Phase D) — this
--     migration only adds the nullable deliveries.commerce_order_id seam,
--     it does not build the conversion RPC.
--   - queue_outbound_sms / sms_credit_ledger (Phase 1) for future commerce
--     notifications, billed to the vendor company's own sms_credits —
--     nothing in this migration touches SMS; noted for Phase B/G.
--   - Supabase Auth's existing session semantics: auth.uid() can only be
--     non-null after a successful verifyOtp() call (signInWithOtp() alone
--     issues no session — see the phone-auth lifecycle audit earlier this
--     session), so "customer must OTP-verify before ordering" is enforced
--     by requiring auth.uid() IS NOT NULL, with an explicit defensive
--     phone_confirmed_at check in submit_commerce_order for auditability.

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
CREATE TYPE public.commerce_vendor_state AS ENUM (
  'draft', 'pending_review', 'active', 'suspended', 'rejected'
);

CREATE TYPE public.commerce_product_status AS ENUM (
  'draft', 'active', 'paused'
);

CREATE TYPE public.commerce_order_payment_status AS ENUM (
  'pending_payment', 'paid', 'payment_failed', 'refund_pending', 'refunded'
);

CREATE TYPE public.commerce_order_fulfillment_status AS ENUM (
  'awaiting_vendor', 'vendor_accepted', 'vendor_rejected', 'preparing',
  'ready_for_pickup', 'handed_to_carrier', 'completed', 'cancelled'
);

CREATE TYPE public.commerce_stock_movement_type AS ENUM (
  'restock', 'adjustment', 'reservation', 'release', 'sale_deduction'
);

-- ---------------------------------------------------------------------------
-- Store profiles (1:1 with a merchant/hybrid company)
-- ---------------------------------------------------------------------------
CREATE TABLE public.store_profiles (
  company_id UUID PRIMARY KEY REFERENCES public.companies (id) ON DELETE CASCADE,
  slug TEXT NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  display_name TEXT NOT NULL,
  description TEXT,
  logo_url TEXT,
  banner_url TEXT,
  business_hours JSONB NOT NULL DEFAULT '{}'::JSONB,
  status public.commerce_vendor_state NOT NULL DEFAULT 'draft',
  status_reason TEXT,
  reviewed_by UUID REFERENCES auth.users (id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_store_profiles_status ON public.store_profiles (status);

CREATE TRIGGER store_profiles_updated_at
  BEFORE UPDATE ON public.store_profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.store_is_publicly_visible(p_company_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.store_profiles sp
    JOIN public.companies c ON c.id = sp.company_id
    WHERE sp.company_id = p_company_id
      AND sp.status = 'active'
      AND c.status = 'active'
      AND c.marketplace_suspended = false
  );
$$;

-- ---------------------------------------------------------------------------
-- Catalog: categories, products, images, options
-- ---------------------------------------------------------------------------
CREATE TABLE public.product_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (company_id, name)
);

CREATE INDEX idx_product_categories_company ON public.product_categories (company_id, is_active);

CREATE TRIGGER product_categories_updated_at
  BEFORE UPDATE ON public.product_categories
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE public.products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  category_id UUID REFERENCES public.product_categories (id) ON DELETE SET NULL,
  name TEXT NOT NULL,
  description TEXT,
  price_lrd_cents INT NOT NULL CHECK (price_lrd_cents >= 0),
  currency TEXT NOT NULL DEFAULT 'LRD',
  status public.commerce_product_status NOT NULL DEFAULT 'draft',
  tracks_inventory BOOLEAN NOT NULL DEFAULT false,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_products_company_status ON public.products (company_id, status);

CREATE TRIGGER products_updated_at
  BEFORE UPDATE ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE public.product_images (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID NOT NULL REFERENCES public.products (id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  storage_path TEXT NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_product_images_product ON public.product_images (product_id, sort_order);

CREATE TABLE public.product_option_groups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID NOT NULL REFERENCES public.products (id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  selection_type TEXT NOT NULL DEFAULT 'single' CHECK (selection_type IN ('single', 'multiple')),
  is_required BOOLEAN NOT NULL DEFAULT false,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_product_option_groups_product ON public.product_option_groups (product_id, sort_order);

CREATE TABLE public.product_options (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  option_group_id UUID NOT NULL REFERENCES public.product_option_groups (id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  price_delta_lrd_cents INT NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_product_options_group ON public.product_options (option_group_id, sort_order);

-- ---------------------------------------------------------------------------
-- Stock: mirrors the existing inventory_stock/inventory_movements shape
-- (quantity_on_hand + quantity_reserved, append-only movement ledger) —
-- same reservation-safety pattern already proven for warehouse inventory,
-- applied here to sellable products.
-- ---------------------------------------------------------------------------
CREATE TABLE public.product_stock (
  product_id UUID PRIMARY KEY REFERENCES public.products (id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  quantity_on_hand NUMERIC(14, 3) NOT NULL DEFAULT 0 CHECK (quantity_on_hand >= 0),
  quantity_reserved NUMERIC(14, 3) NOT NULL DEFAULT 0 CHECK (quantity_reserved >= 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (quantity_reserved <= quantity_on_hand)
);

CREATE TABLE public.product_stock_movements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID NOT NULL REFERENCES public.products (id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  quantity NUMERIC(14, 3) NOT NULL,
  movement_type public.commerce_stock_movement_type NOT NULL,
  reference_type TEXT,
  reference_id UUID,
  notes TEXT,
  actor_user_id UUID REFERENCES auth.users (id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_product_stock_movements_product ON public.product_stock_movements (product_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- Carts (single vendor per cart for V1 — one open cart per customer+vendor)
-- ---------------------------------------------------------------------------
CREATE TABLE public.carts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  vendor_company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'converted', 'abandoned')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_carts_one_open_per_customer_vendor
  ON public.carts (customer_id, vendor_company_id)
  WHERE status = 'open';

CREATE TABLE public.cart_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cart_id UUID NOT NULL REFERENCES public.carts (id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES public.products (id) ON DELETE CASCADE,
  quantity INT NOT NULL CHECK (quantity > 0),
  selected_options JSONB NOT NULL DEFAULT '[]'::JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_cart_items_cart ON public.cart_items (cart_id);

-- ---------------------------------------------------------------------------
-- Commerce orders: header owns items/customer/vendor/payment/fulfillment.
-- Delivery specifics stay on the existing deliveries table (see the
-- nullable deliveries.commerce_order_id column added below) — this table
-- deliberately does not duplicate pickup/dropoff/carrier/rider/tracking.
-- ---------------------------------------------------------------------------
CREATE SEQUENCE public.commerce_order_number_seq START 1000;

CREATE TABLE public.commerce_orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_number TEXT NOT NULL UNIQUE DEFAULT (
    'ORD-' || to_char(now() AT TIME ZONE 'Africa/Monrovia', 'YYYYMM') || '-' ||
    lpad(nextval('public.commerce_order_number_seq')::TEXT, 5, '0')
  ),
  customer_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  vendor_company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  cart_id UUID REFERENCES public.carts (id) ON DELETE SET NULL,
  subtotal_lrd_cents INT NOT NULL DEFAULT 0 CHECK (subtotal_lrd_cents >= 0),
  delivery_fee_lrd_cents INT NOT NULL DEFAULT 0 CHECK (delivery_fee_lrd_cents >= 0),
  total_lrd_cents INT NOT NULL DEFAULT 0 CHECK (total_lrd_cents >= 0),
  currency TEXT NOT NULL DEFAULT 'LRD',
  payment_status public.commerce_order_payment_status NOT NULL DEFAULT 'pending_payment',
  fulfillment_status public.commerce_order_fulfillment_status NOT NULL DEFAULT 'awaiting_vendor',
  customer_name TEXT NOT NULL,
  customer_phone TEXT NOT NULL,
  delivery_address TEXT,
  delivery_area_summary TEXT,
  delivery_latitude DOUBLE PRECISION,
  delivery_longitude DOUBLE PRECISION,
  delivery_instructions TEXT,
  delivery_id UUID,
  cancelled_at TIMESTAMPTZ,
  cancellation_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_commerce_orders_customer ON public.commerce_orders (customer_id, created_at DESC);
CREATE INDEX idx_commerce_orders_vendor ON public.commerce_orders (vendor_company_id, created_at DESC);

CREATE TRIGGER commerce_orders_updated_at
  BEFORE UPDATE ON public.commerce_orders
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Append-only: no product FK cascade delete, so a snapshot survives a
-- product being removed from the catalog later.
CREATE TABLE public.commerce_order_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.commerce_orders (id) ON DELETE CASCADE,
  product_id UUID REFERENCES public.products (id) ON DELETE SET NULL,
  product_name TEXT NOT NULL,
  unit_price_lrd_cents INT NOT NULL CHECK (unit_price_lrd_cents >= 0),
  quantity INT NOT NULL CHECK (quantity > 0),
  selected_options JSONB NOT NULL DEFAULT '[]'::JSONB,
  line_total_lrd_cents INT NOT NULL CHECK (line_total_lrd_cents >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_commerce_order_items_order ON public.commerce_order_items (order_id);

-- ---------------------------------------------------------------------------
-- Nullable seam into the existing delivery engine — populated by the Phase D
-- conversion RPC (not built here). No existing deliveries row is affected;
-- every current delivery/marketplace flow is untouched by this column.
-- ---------------------------------------------------------------------------
ALTER TABLE public.deliveries
  ADD COLUMN IF NOT EXISTS commerce_order_id UUID REFERENCES public.commerce_orders (id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_deliveries_commerce_order ON public.deliveries (commerce_order_id)
  WHERE commerce_order_id IS NOT NULL;

ALTER TABLE public.commerce_orders
  ADD CONSTRAINT fk_commerce_orders_delivery
  FOREIGN KEY (delivery_id) REFERENCES public.deliveries (id) ON DELETE SET NULL;

-- ---------------------------------------------------------------------------
-- Commerce plan flags on the existing subscriptions catalog — Super Admin
-- remains the single source of truth for entitlements, same mechanism as
-- every existing plan flag (marketplace_access, gps_tracking, ...).
-- No commission rate is set here — that lives in commerce_fee_rules below,
-- kept deliberately separate from carrier subscription billing.
-- ---------------------------------------------------------------------------
ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS commerce_enabled BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS commerce_max_products INT;

UPDATE public.subscriptions SET
  commerce_enabled = (slug IN ('business', 'enterprise'))
WHERE slug IN ('starter', 'business', 'enterprise');

CREATE OR REPLACE FUNCTION public.can_use_feature(p_company_id UUID, p_feature_key TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cs public.company_subscriptions;
  v_plan public.subscriptions;
  v_ok BOOLEAN := false;
BEGIN
  v_cs := public.get_active_company_subscription(p_company_id);
  IF v_cs.id IS NULL OR v_cs.status NOT IN ('trialing', 'active') THEN
    RETURN false;
  END IF;
  IF v_cs.current_period_end < now() THEN
    RETURN false;
  END IF;

  SELECT * INTO v_plan FROM public.subscriptions WHERE id = v_cs.plan_id AND is_active = true;
  IF NOT FOUND THEN
    RETURN false;
  END IF;

  v_ok := CASE p_feature_key
    WHEN 'proof_of_delivery' THEN v_plan.proof_of_delivery
    WHEN 'advanced_reports' THEN v_plan.advanced_reports
    WHEN 'api_access' THEN v_plan.api_access
    WHEN 'gps_tracking' THEN v_plan.gps_tracking
    WHEN 'custom_branding' THEN v_plan.custom_branding
    WHEN 'sms_notifications' THEN v_plan.monthly_sms_allowance > 0
    WHEN 'multi_branch' THEN v_plan.multi_branch
    WHEN 'fleet_management' THEN v_plan.fleet_management
    WHEN 'inventory' THEN v_plan.inventory
    WHEN 'warehouse_management' THEN v_plan.warehouse_management
    WHEN 'cod_reconciliation' THEN v_plan.cod_reconciliation
    WHEN 'profitability_reports' THEN v_plan.profitability_reports
    WHEN 'marketplace_access' THEN v_plan.marketplace_access
    WHEN 'merchant_portal' THEN v_plan.merchant_portal
    WHEN 'provider_network' THEN v_plan.provider_network
    WHEN 'marketplace_api' THEN v_plan.marketplace_api
    WHEN 'commerce_enabled' THEN v_plan.commerce_enabled
    WHEN 'sms' THEN v_cs.status IN ('trialing', 'active')
    ELSE COALESCE((v_plan.features ->> p_feature_key)::BOOLEAN, false)
  END;

  RETURN COALESCE(v_ok, false);
END;
$$;

-- ---------------------------------------------------------------------------
-- Commerce fee rules — reuses the existing marketplace_fee_model enum
-- (fixed/percentage/subscription_only/zero_commission) directly. Seeded
-- platform default is zero_commission: Super Admin must explicitly opt in
-- to a real commission rate later; nothing here hardcodes a percentage.
-- ---------------------------------------------------------------------------
CREATE TABLE public.commerce_fee_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  fee_model public.marketplace_fee_model NOT NULL DEFAULT 'zero_commission',
  fixed_fee_lrd_cents INT NOT NULL DEFAULT 0,
  percentage_bps INT NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  is_platform_default BOOLEAN NOT NULL DEFAULT false,
  applies_to_vendor_company_id UUID REFERENCES public.companies (id) ON DELETE CASCADE,
  created_by UUID REFERENCES auth.users (id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_commerce_fee_rules_default
  ON public.commerce_fee_rules (is_platform_default)
  WHERE is_platform_default = true;

INSERT INTO public.commerce_fee_rules (name, fee_model, percentage_bps, is_active, is_platform_default)
SELECT 'Platform default (no commission yet)', 'zero_commission', 0, true, true
WHERE NOT EXISTS (SELECT 1 FROM public.commerce_fee_rules WHERE is_platform_default = true);

-- ---------------------------------------------------------------------------
-- Auto-provision a draft store profile for merchant/hybrid companies, same
-- pattern already used for provider_marketplace_profiles. Reproduces the
-- current full body of create_company_with_owner
-- (20260308190700_activate_self_service_companies.sql) plus this one block
-- — no other behavior changes.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_company_with_owner(
  p_name TEXT,
  p_phone TEXT,
  p_email TEXT,
  p_address TEXT DEFAULT NULL,
  p_business_type public.company_business_type DEFAULT 'logistics_provider'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_sub_id UUID;
  v_slug TEXT;
  v_type public.company_business_type := COALESCE(p_business_type, 'logistics_provider');
  v_email TEXT;
  v_auth_phone TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT cu.company_id INTO v_company_id
  FROM public.company_users cu
  WHERE cu.user_id = auth.uid() AND cu.is_active = true
  ORDER BY cu.created_at ASC LIMIT 1;

  IF v_company_id IS NOT NULL THEN
    RETURN v_company_id;
  END IF;

  IF p_name IS NULL OR length(trim(p_name)) < 2 THEN
    RAISE EXCEPTION 'invalid company name';
  END IF;

  SELECT phone INTO v_auth_phone FROM auth.users WHERE id = auth.uid();
  IF p_phone IS NULL OR length(trim(p_phone)) < 7 THEN
    p_phone := COALESCE(public.normalize_phone_lr(v_auth_phone), '+2310000000');
  END IF;

  v_email := NULLIF(lower(trim(COALESCE(p_email, ''))), '');
  IF v_email IS NULL OR position('@' in v_email) = 0 THEN
    v_email := replace(public.normalize_phone_lr(p_phone), '+', '') || '@contact.deliveryos.local';
  END IF;

  v_slug := lower(regexp_replace(trim(p_name), '[^a-zA-Z0-9]+', '-', 'g'));
  v_slug := trim(both '-' from v_slug);
  IF v_slug = '' THEN
    RAISE EXCEPTION 'invalid company name';
  END IF;

  SELECT id INTO v_sub_id FROM public.subscriptions WHERE slug = 'starter' LIMIT 1;

  INSERT INTO public.companies (name, slug, phone, email, address, subscription_id, business_type, status)
  VALUES (
    trim(p_name), v_slug, public.normalize_phone_lr(p_phone), v_email, p_address, v_sub_id, v_type,
    'active'::public.company_status
  )
  RETURNING id INTO v_company_id;

  INSERT INTO public.company_users (company_id, user_id, role)
  VALUES (v_company_id, auth.uid(), 'company_owner');

  PERFORM public.ensure_initial_company_subscription(v_company_id);

  IF v_type IN ('logistics_provider', 'hybrid') THEN
    INSERT INTO public.provider_marketplace_profiles (company_id, marketplace_enabled, accepting_jobs)
    VALUES (v_company_id, false, false)
    ON CONFLICT (company_id) DO NOTHING;
  END IF;

  IF v_type IN ('merchant', 'hybrid') THEN
    INSERT INTO public.store_profiles (company_id, slug, display_name, status)
    VALUES (v_company_id, v_slug || '-' || substr(v_company_id::text, 1, 6), trim(p_name), 'draft')
    ON CONFLICT (company_id) DO NOTHING;
  END IF;

  PERFORM public.sync_profile_from_auth_user();

  RETURN v_company_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- RLS: enable on every new table
-- ---------------------------------------------------------------------------
ALTER TABLE public.store_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_images ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_option_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_stock ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_stock_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.carts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commerce_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commerce_order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commerce_fee_rules ENABLE ROW LEVEL SECURITY;

-- store_profiles: vendor company + super admin always; public only once
-- actually published (status='active', company active, not suspended).
CREATE POLICY store_profiles_select ON public.store_profiles
  FOR SELECT TO anon, authenticated
  USING (
    status = 'active'
    OR public.is_super_admin()
    OR company_id IN (SELECT public.user_company_ids())
  );

-- product_categories / products / images / option groups / options:
-- vendor + super admin always; public only for active rows of a published store.
CREATE POLICY product_categories_select ON public.product_categories
  FOR SELECT TO anon, authenticated
  USING (
    public.is_super_admin()
    OR company_id IN (SELECT public.user_company_ids())
    OR (is_active = true AND public.store_is_publicly_visible(company_id))
  );

CREATE POLICY products_select ON public.products
  FOR SELECT TO anon, authenticated
  USING (
    public.is_super_admin()
    OR company_id IN (SELECT public.user_company_ids())
    OR (status = 'active' AND public.store_is_publicly_visible(company_id))
  );

CREATE POLICY product_images_select ON public.product_images
  FOR SELECT TO anon, authenticated
  USING (
    public.is_super_admin()
    OR company_id IN (SELECT public.user_company_ids())
    OR EXISTS (
      SELECT 1 FROM public.products p
      WHERE p.id = product_images.product_id AND p.status = 'active'
        AND public.store_is_publicly_visible(p.company_id)
    )
  );

CREATE POLICY product_option_groups_select ON public.product_option_groups
  FOR SELECT TO anon, authenticated
  USING (
    public.is_super_admin()
    OR company_id IN (SELECT public.user_company_ids())
    OR EXISTS (
      SELECT 1 FROM public.products p
      WHERE p.id = product_option_groups.product_id AND p.status = 'active'
        AND public.store_is_publicly_visible(p.company_id)
    )
  );

CREATE POLICY product_options_select ON public.product_options
  FOR SELECT TO anon, authenticated
  USING (
    public.is_super_admin()
    OR company_id IN (SELECT public.user_company_ids())
    OR (
      is_active = true
      AND EXISTS (
        SELECT 1 FROM public.product_option_groups g
        JOIN public.products p ON p.id = g.product_id
        WHERE g.id = product_options.option_group_id AND p.status = 'active'
          AND public.store_is_publicly_visible(p.company_id)
      )
    )
  );

-- Stock is never public — vendor + super admin only.
CREATE POLICY product_stock_select ON public.product_stock
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR company_id IN (SELECT public.user_company_ids())
  );

CREATE POLICY product_stock_movements_select ON public.product_stock_movements
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR company_id IN (SELECT public.user_company_ids())
  );

-- Carts are private to the owning customer (not vendor-visible — a cart is
-- a pre-commitment state, unlike a submitted order).
CREATE POLICY carts_select ON public.carts
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR customer_id = auth.uid()
  );

CREATE POLICY cart_items_select ON public.cart_items
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR EXISTS (
      SELECT 1 FROM public.carts c WHERE c.id = cart_items.cart_id AND c.customer_id = auth.uid()
    )
  );

-- Orders: customer who placed it, the vendor who owns it, or super admin.
CREATE POLICY commerce_orders_select ON public.commerce_orders
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR customer_id = auth.uid()
    OR vendor_company_id IN (SELECT public.user_company_ids())
  );

CREATE POLICY commerce_order_items_select ON public.commerce_order_items
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR EXISTS (
      SELECT 1 FROM public.commerce_orders o
      WHERE o.id = commerce_order_items.order_id
        AND (o.customer_id = auth.uid() OR o.vendor_company_id IN (SELECT public.user_company_ids()))
    )
  );

CREATE POLICY commerce_fee_rules_read ON public.commerce_fee_rules
  FOR SELECT TO authenticated
  USING (public.is_super_admin() OR is_active = true);

CREATE POLICY commerce_fee_rules_admin ON public.commerce_fee_rules
  FOR ALL TO authenticated
  USING (public.is_super_admin())
  WITH CHECK (public.is_super_admin());

-- No INSERT/UPDATE/DELETE policies are granted to `authenticated` on any
-- other new table above — every write goes through a SECURITY DEFINER RPC
-- below, which performs its own role/ownership check and bypasses RLS as
-- the table owner. This is the same "RLS is read-only for clients, RPCs are
-- the only write path" convention already used for company_subscriptions,
-- invoices, and every marketplace table. It is what makes price/status/
-- financial fields non-client-writable by construction, not by convention
-- alone.

-- ---------------------------------------------------------------------------
-- RPCs: vendor catalog management
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assert_vendor_manager(p_company_id UUID)
RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type public.company_business_type;
BEGIN
  IF NOT public.has_company_role(p_company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[])
     AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  SELECT business_type INTO v_type FROM public.companies WHERE id = p_company_id;
  IF v_type NOT IN ('merchant', 'hybrid') THEN
    RAISE EXCEPTION 'not_a_vendor_company';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.assert_vendor_manager(UUID) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.upsert_store_profile(p_payload JSONB)
RETURNS public.store_profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID := (p_payload ->> 'company_id')::UUID;
  v_row public.store_profiles;
BEGIN
  PERFORM public.assert_vendor_manager(v_company_id);

  INSERT INTO public.store_profiles (
    company_id, slug, display_name, description, logo_url, banner_url, business_hours
  ) VALUES (
    v_company_id,
    p_payload ->> 'slug',
    p_payload ->> 'display_name',
    p_payload ->> 'description',
    p_payload ->> 'logo_url',
    p_payload ->> 'banner_url',
    COALESCE(p_payload -> 'business_hours', '{}'::JSONB)
  )
  ON CONFLICT (company_id) DO UPDATE SET
    slug = COALESCE(NULLIF(p_payload ->> 'slug', ''), store_profiles.slug),
    display_name = COALESCE(NULLIF(p_payload ->> 'display_name', ''), store_profiles.display_name),
    description = COALESCE(p_payload ->> 'description', store_profiles.description),
    logo_url = COALESCE(p_payload ->> 'logo_url', store_profiles.logo_url),
    banner_url = COALESCE(p_payload ->> 'banner_url', store_profiles.banner_url),
    business_hours = COALESCE(p_payload -> 'business_hours', store_profiles.business_hours)
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_store_profile TO authenticated;

-- Vendor-initiated: draft/rejected -> pending_review only. Vendors can never
-- set their own status to 'active' — only Super Admin can (see
-- admin_set_vendor_state below).
CREATE OR REPLACE FUNCTION public.submit_store_profile_for_review(p_company_id UUID)
RETURNS public.store_profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.store_profiles;
BEGIN
  PERFORM public.assert_vendor_manager(p_company_id);

  SELECT * INTO v_row FROM public.store_profiles WHERE company_id = p_company_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'store_profile_not_found';
  END IF;
  IF v_row.status NOT IN ('draft', 'rejected') THEN
    RAISE EXCEPTION 'invalid_vendor_state';
  END IF;

  UPDATE public.store_profiles SET
    status = 'pending_review', status_reason = NULL
  WHERE company_id = p_company_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_store_profile_for_review TO authenticated;

CREATE OR REPLACE FUNCTION public.upsert_product_category(p_payload JSONB)
RETURNS public.product_categories
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID := (p_payload ->> 'company_id')::UUID;
  v_id UUID := NULLIF(p_payload ->> 'id', '')::UUID;
  v_row public.product_categories;
BEGIN
  PERFORM public.assert_vendor_manager(v_company_id);

  IF v_id IS NULL THEN
    INSERT INTO public.product_categories (company_id, name, sort_order, is_active)
    VALUES (
      v_company_id, p_payload ->> 'name',
      COALESCE((p_payload ->> 'sort_order')::INT, 0),
      COALESCE((p_payload ->> 'is_active')::BOOLEAN, true)
    )
    RETURNING * INTO v_row;
  ELSE
    UPDATE public.product_categories SET
      name = COALESCE(p_payload ->> 'name', name),
      sort_order = COALESCE((p_payload ->> 'sort_order')::INT, sort_order),
      is_active = COALESCE((p_payload ->> 'is_active')::BOOLEAN, is_active)
    WHERE id = v_id AND company_id = v_company_id
    RETURNING * INTO v_row;
    IF NOT FOUND THEN RAISE EXCEPTION 'category_not_found'; END IF;
  END IF;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_product_category TO authenticated;

CREATE OR REPLACE FUNCTION public.upsert_product(p_payload JSONB)
RETURNS public.products
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID := (p_payload ->> 'company_id')::UUID;
  v_id UUID := NULLIF(p_payload ->> 'id', '')::UUID;
  v_category_id UUID := NULLIF(p_payload ->> 'category_id', '')::UUID;
  v_tracks BOOLEAN;
  v_row public.products;
BEGIN
  PERFORM public.assert_vendor_manager(v_company_id);

  IF v_category_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.product_categories WHERE id = v_category_id AND company_id = v_company_id
  ) THEN
    RAISE EXCEPTION 'category_not_found';
  END IF;

  IF v_id IS NULL THEN
    v_tracks := COALESCE((p_payload ->> 'tracks_inventory')::BOOLEAN, false);

    INSERT INTO public.products (
      company_id, category_id, name, description, price_lrd_cents, status, tracks_inventory, sort_order
    ) VALUES (
      v_company_id, v_category_id, p_payload ->> 'name', p_payload ->> 'description',
      (p_payload ->> 'price_lrd_cents')::INT,
      COALESCE((p_payload ->> 'status')::public.commerce_product_status, 'draft'),
      v_tracks,
      COALESCE((p_payload ->> 'sort_order')::INT, 0)
    )
    RETURNING * INTO v_row;

    IF v_tracks THEN
      INSERT INTO public.product_stock (product_id, company_id, quantity_on_hand, quantity_reserved)
      VALUES (v_row.id, v_company_id, COALESCE((p_payload ->> 'initial_quantity')::NUMERIC, 0), 0);
    END IF;
  ELSE
    UPDATE public.products SET
      category_id = CASE WHEN p_payload ? 'category_id' THEN v_category_id ELSE category_id END,
      name = COALESCE(p_payload ->> 'name', name),
      description = COALESCE(p_payload ->> 'description', description),
      price_lrd_cents = COALESCE((p_payload ->> 'price_lrd_cents')::INT, price_lrd_cents),
      status = COALESCE((p_payload ->> 'status')::public.commerce_product_status, status),
      sort_order = COALESCE((p_payload ->> 'sort_order')::INT, sort_order)
    WHERE id = v_id AND company_id = v_company_id
    RETURNING * INTO v_row;
    IF NOT FOUND THEN RAISE EXCEPTION 'product_not_found'; END IF;

    IF v_row.tracks_inventory THEN
      INSERT INTO public.product_stock (product_id, company_id, quantity_on_hand, quantity_reserved)
      VALUES (v_row.id, v_company_id, 0, 0)
      ON CONFLICT (product_id) DO NOTHING;
    END IF;
  END IF;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_product TO authenticated;

CREATE OR REPLACE FUNCTION public.upsert_product_option_group(p_payload JSONB)
RETURNS public.product_option_groups
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_product_id UUID := (p_payload ->> 'product_id')::UUID;
  v_company_id UUID;
  v_row public.product_option_groups;
BEGIN
  SELECT company_id INTO v_company_id FROM public.products WHERE id = v_product_id;
  IF v_company_id IS NULL THEN RAISE EXCEPTION 'product_not_found'; END IF;
  PERFORM public.assert_vendor_manager(v_company_id);

  INSERT INTO public.product_option_groups (
    product_id, company_id, name, selection_type, is_required, sort_order
  ) VALUES (
    v_product_id, v_company_id, p_payload ->> 'name',
    COALESCE(p_payload ->> 'selection_type', 'single'),
    COALESCE((p_payload ->> 'is_required')::BOOLEAN, false),
    COALESCE((p_payload ->> 'sort_order')::INT, 0)
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_product_option_group TO authenticated;

CREATE OR REPLACE FUNCTION public.upsert_product_option(p_payload JSONB)
RETURNS public.product_options
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_group_id UUID := (p_payload ->> 'option_group_id')::UUID;
  v_company_id UUID;
  v_row public.product_options;
BEGIN
  SELECT company_id INTO v_company_id FROM public.product_option_groups WHERE id = v_group_id;
  IF v_company_id IS NULL THEN RAISE EXCEPTION 'option_group_not_found'; END IF;
  PERFORM public.assert_vendor_manager(v_company_id);

  INSERT INTO public.product_options (
    option_group_id, company_id, name, price_delta_lrd_cents, is_active, sort_order
  ) VALUES (
    v_group_id, v_company_id, p_payload ->> 'name',
    COALESCE((p_payload ->> 'price_delta_lrd_cents')::INT, 0),
    COALESCE((p_payload ->> 'is_active')::BOOLEAN, true),
    COALESCE((p_payload ->> 'sort_order')::INT, 0)
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_product_option TO authenticated;

CREATE OR REPLACE FUNCTION public.upsert_product_image(p_payload JSONB)
RETURNS public.product_images
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_product_id UUID := (p_payload ->> 'product_id')::UUID;
  v_company_id UUID;
  v_row public.product_images;
BEGIN
  SELECT company_id INTO v_company_id FROM public.products WHERE id = v_product_id;
  IF v_company_id IS NULL THEN RAISE EXCEPTION 'product_not_found'; END IF;
  PERFORM public.assert_vendor_manager(v_company_id);

  INSERT INTO public.product_images (product_id, company_id, storage_path, sort_order)
  VALUES (v_product_id, v_company_id, p_payload ->> 'storage_path', COALESCE((p_payload ->> 'sort_order')::INT, 0))
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_product_image TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_product_image(p_image_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
BEGIN
  SELECT company_id INTO v_company_id FROM public.product_images WHERE id = p_image_id;
  IF v_company_id IS NULL THEN RAISE EXCEPTION 'image_not_found'; END IF;
  PERFORM public.assert_vendor_manager(v_company_id);

  DELETE FROM public.product_images WHERE id = p_image_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_product_image TO authenticated;

-- Manual restock/adjustment only (reservation/release/sale_deduction are
-- system-driven, from the order lifecycle below — not exposed here).
CREATE OR REPLACE FUNCTION public.adjust_product_stock(
  p_product_id UUID,
  p_delta NUMERIC,
  p_reason TEXT DEFAULT 'manual_adjustment'
)
RETURNS public.product_stock
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_row public.product_stock;
  v_movement public.commerce_stock_movement_type;
BEGIN
  SELECT company_id INTO v_company_id FROM public.products WHERE id = p_product_id;
  IF v_company_id IS NULL THEN RAISE EXCEPTION 'product_not_found'; END IF;
  PERFORM public.assert_vendor_manager(v_company_id);

  IF p_delta = 0 THEN RAISE EXCEPTION 'delta_must_be_nonzero'; END IF;
  v_movement := CASE WHEN p_delta > 0 THEN 'restock' ELSE 'adjustment' END;

  SELECT * INTO v_row FROM public.product_stock WHERE product_id = p_product_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'stock_not_configured'; END IF;

  UPDATE public.product_stock SET
    quantity_on_hand = quantity_on_hand + p_delta,
    updated_at = now()
  WHERE product_id = p_product_id
  RETURNING * INTO v_row;

  INSERT INTO public.product_stock_movements (
    product_id, company_id, quantity, movement_type, reference_type, notes, actor_user_id
  ) VALUES (
    p_product_id, v_company_id, p_delta, v_movement, 'manual', p_reason, auth.uid()
  );

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.adjust_product_stock TO authenticated;

-- ---------------------------------------------------------------------------
-- RPCs: customer cart
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_or_create_cart(p_vendor_company_id UUID)
RETURNS public.carts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.carts;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  IF NOT public.store_is_publicly_visible(p_vendor_company_id) THEN
    RAISE EXCEPTION 'vendor_not_available';
  END IF;

  SELECT * INTO v_row FROM public.carts
  WHERE customer_id = auth.uid() AND vendor_company_id = p_vendor_company_id AND status = 'open';

  IF FOUND THEN
    RETURN v_row;
  END IF;

  INSERT INTO public.carts (customer_id, vendor_company_id)
  VALUES (auth.uid(), p_vendor_company_id)
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_or_create_cart TO authenticated;

CREATE OR REPLACE FUNCTION public.assert_valid_product_options(p_product_id UUID, p_selected_options JSONB)
RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
  v_expected INT;
BEGIN
  v_expected := COALESCE(jsonb_array_length(p_selected_options), 0);
  IF v_expected = 0 THEN
    RETURN;
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM public.product_options po
  JOIN public.product_option_groups g ON g.id = po.option_group_id
  WHERE po.id IN (SELECT (jsonb_array_elements_text(p_selected_options))::UUID)
    AND g.product_id = p_product_id
    AND po.is_active = true;

  IF v_count <> v_expected THEN
    RAISE EXCEPTION 'invalid_product_option';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.assert_valid_product_options(UUID, JSONB) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.add_cart_item(
  p_cart_id UUID,
  p_product_id UUID,
  p_quantity INT,
  p_selected_options JSONB DEFAULT '[]'::JSONB
)
RETURNS public.cart_items
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cart public.carts;
  v_product public.products;
  v_row public.cart_items;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF p_quantity IS NULL OR p_quantity <= 0 THEN RAISE EXCEPTION 'invalid_quantity'; END IF;

  SELECT * INTO v_cart FROM public.carts WHERE id = p_cart_id AND customer_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'cart_not_found'; END IF;
  IF v_cart.status <> 'open' THEN RAISE EXCEPTION 'cart_not_open'; END IF;

  SELECT * INTO v_product FROM public.products WHERE id = p_product_id;
  IF NOT FOUND OR v_product.company_id <> v_cart.vendor_company_id OR v_product.status <> 'active' THEN
    RAISE EXCEPTION 'product_not_available';
  END IF;

  PERFORM public.assert_valid_product_options(p_product_id, p_selected_options);

  INSERT INTO public.cart_items (cart_id, product_id, quantity, selected_options)
  VALUES (p_cart_id, p_product_id, p_quantity, COALESCE(p_selected_options, '[]'::JSONB))
  RETURNING * INTO v_row;

  UPDATE public.carts SET updated_at = now() WHERE id = p_cart_id;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.add_cart_item TO authenticated;

CREATE OR REPLACE FUNCTION public.update_cart_item_quantity(p_cart_item_id UUID, p_quantity INT)
RETURNS public.cart_items
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.cart_items;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF p_quantity IS NULL OR p_quantity <= 0 THEN RAISE EXCEPTION 'invalid_quantity'; END IF;

  UPDATE public.cart_items ci SET quantity = p_quantity, updated_at = now()
  FROM public.carts c
  WHERE ci.id = p_cart_item_id AND c.id = ci.cart_id
    AND c.customer_id = auth.uid() AND c.status = 'open'
  RETURNING ci.* INTO v_row;

  IF v_row.id IS NULL THEN RAISE EXCEPTION 'cart_item_not_found'; END IF;
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_cart_item_quantity TO authenticated;

CREATE OR REPLACE FUNCTION public.remove_cart_item(p_cart_item_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  DELETE FROM public.cart_items ci
  USING public.carts c
  WHERE ci.id = p_cart_item_id AND c.id = ci.cart_id
    AND c.customer_id = auth.uid() AND c.status = 'open';

  IF NOT FOUND THEN RAISE EXCEPTION 'cart_item_not_found'; END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.remove_cart_item TO authenticated;

-- ---------------------------------------------------------------------------
-- RPCs: order submission — the server-authoritative pricing + concurrency-
-- safe reservation boundary. Client never supplies a price or a fee here;
-- every amount is read from live products/product_options rows inside this
-- function and frozen into commerce_order_items.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_commerce_order(
  p_cart_id UUID,
  p_customer_name TEXT,
  p_delivery_address TEXT DEFAULT NULL,
  p_delivery_area_summary TEXT DEFAULT NULL,
  p_delivery_latitude DOUBLE PRECISION DEFAULT NULL,
  p_delivery_longitude DOUBLE PRECISION DEFAULT NULL,
  p_delivery_instructions TEXT DEFAULT NULL
)
RETURNS public.commerce_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_phone_confirmed TIMESTAMPTZ;
  v_auth_phone TEXT;
  v_cart public.carts;
  v_item RECORD;
  v_product public.products;
  v_stock public.product_stock;
  v_available NUMERIC;
  v_option_delta INT;
  v_option_snapshot JSONB;
  v_unit_price INT;
  v_line_total INT;
  v_subtotal INT := 0;
  v_order public.commerce_orders;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  -- Explicit, defensive re-assertion that this identity completed OTP
  -- verification (a session can only exist post-verifyOtp today, but this
  -- makes the guarantee checkable rather than merely structural).
  SELECT phone, phone_confirmed_at INTO v_auth_phone, v_phone_confirmed
  FROM auth.users WHERE id = auth.uid();
  IF v_phone_confirmed IS NULL THEN
    RAISE EXCEPTION 'phone_not_verified';
  END IF;

  SELECT * INTO v_cart FROM public.carts WHERE id = p_cart_id AND customer_id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'cart_not_found';
  END IF;
  IF v_cart.status <> 'open' THEN
    RAISE EXCEPTION 'cart_not_open';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.cart_items WHERE cart_id = v_cart.id) THEN
    RAISE EXCEPTION 'cart_empty';
  END IF;
  IF NOT public.store_is_publicly_visible(v_cart.vendor_company_id) THEN
    RAISE EXCEPTION 'vendor_not_available';
  END IF;

  INSERT INTO public.commerce_orders (
    customer_id, vendor_company_id, cart_id, customer_name, customer_phone,
    delivery_address, delivery_area_summary, delivery_latitude, delivery_longitude, delivery_instructions
  ) VALUES (
    auth.uid(), v_cart.vendor_company_id, v_cart.id,
    NULLIF(trim(p_customer_name), ''), public.normalize_phone_lr(v_auth_phone),
    p_delivery_address, p_delivery_area_summary, p_delivery_latitude, p_delivery_longitude, p_delivery_instructions
  )
  RETURNING * INTO v_order;

  IF v_order.customer_name IS NULL THEN
    RAISE EXCEPTION 'customer_name_required';
  END IF;

  FOR v_item IN SELECT * FROM public.cart_items WHERE cart_id = v_cart.id LOOP
    SELECT * INTO v_product FROM public.products WHERE id = v_item.product_id;
    IF NOT FOUND OR v_product.status <> 'active' OR v_product.company_id <> v_cart.vendor_company_id THEN
      RAISE EXCEPTION 'product_not_available';
    END IF;

    PERFORM public.assert_valid_product_options(v_product.id, v_item.selected_options);

    v_unit_price := v_product.price_lrd_cents;
    v_option_snapshot := '[]'::JSONB;

    IF COALESCE(jsonb_array_length(v_item.selected_options), 0) > 0 THEN
      SELECT COALESCE(SUM(po.price_delta_lrd_cents), 0),
             COALESCE(jsonb_agg(jsonb_build_object('name', po.name, 'price_delta_lrd_cents', po.price_delta_lrd_cents)), '[]'::JSONB)
      INTO v_option_delta, v_option_snapshot
      FROM public.product_options po
      WHERE po.id IN (SELECT (jsonb_array_elements_text(v_item.selected_options))::UUID);

      v_unit_price := v_unit_price + COALESCE(v_option_delta, 0);
    END IF;

    v_line_total := v_unit_price * v_item.quantity;
    v_subtotal := v_subtotal + v_line_total;

    INSERT INTO public.commerce_order_items (
      order_id, product_id, product_name, unit_price_lrd_cents, quantity, selected_options, line_total_lrd_cents
    ) VALUES (
      v_order.id, v_product.id, v_product.name, v_unit_price, v_item.quantity, v_option_snapshot, v_line_total
    );

    IF v_product.tracks_inventory THEN
      SELECT * INTO v_stock FROM public.product_stock WHERE product_id = v_product.id FOR UPDATE;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'stock_not_configured';
      END IF;
      v_available := v_stock.quantity_on_hand - v_stock.quantity_reserved;
      IF v_available < v_item.quantity THEN
        RAISE EXCEPTION 'insufficient_stock';
      END IF;

      UPDATE public.product_stock SET
        quantity_reserved = quantity_reserved + v_item.quantity, updated_at = now()
      WHERE product_id = v_product.id;

      INSERT INTO public.product_stock_movements (
        product_id, company_id, quantity, movement_type, reference_type, reference_id, actor_user_id
      ) VALUES (
        v_product.id, v_cart.vendor_company_id, v_item.quantity, 'reservation', 'commerce_order', v_order.id, auth.uid()
      );
    END IF;
  END LOOP;

  UPDATE public.commerce_orders SET
    subtotal_lrd_cents = v_subtotal,
    total_lrd_cents = v_subtotal + delivery_fee_lrd_cents
  WHERE id = v_order.id
  RETURNING * INTO v_order;

  UPDATE public.carts SET status = 'converted', updated_at = now() WHERE id = v_cart.id;

  RETURN v_order;
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_commerce_order TO authenticated;

-- Customer-initiated cancellation, only before the vendor has acted.
CREATE OR REPLACE FUNCTION public.customer_cancel_commerce_order(p_order_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS public.commerce_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.commerce_orders;
  v_item RECORD;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT * INTO v_order FROM public.commerce_orders WHERE id = p_order_id AND customer_id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'order_not_found'; END IF;
  IF v_order.fulfillment_status <> 'awaiting_vendor' THEN
    RAISE EXCEPTION 'cannot_cancel';
  END IF;

  FOR v_item IN
    SELECT oi.product_id, oi.quantity, p.tracks_inventory
    FROM public.commerce_order_items oi
    JOIN public.products p ON p.id = oi.product_id
    WHERE oi.order_id = v_order.id AND p.tracks_inventory = true
  LOOP
    UPDATE public.product_stock SET
      quantity_reserved = GREATEST(quantity_reserved - v_item.quantity, 0), updated_at = now()
    WHERE product_id = v_item.product_id;

    INSERT INTO public.product_stock_movements (
      product_id, company_id, quantity, movement_type, reference_type, reference_id, actor_user_id
    ) VALUES (
      v_item.product_id, v_order.vendor_company_id, v_item.quantity, 'release', 'commerce_order', v_order.id, auth.uid()
    );
  END LOOP;

  UPDATE public.commerce_orders SET
    fulfillment_status = 'cancelled',
    payment_status = CASE WHEN payment_status = 'paid' THEN 'refund_pending' ELSE payment_status END,
    cancelled_at = now(),
    cancellation_reason = p_reason
  WHERE id = v_order.id
  RETURNING * INTO v_order;

  RETURN v_order;
END;
$$;

GRANT EXECUTE ON FUNCTION public.customer_cancel_commerce_order TO authenticated;

-- ---------------------------------------------------------------------------
-- Internal-only payment seam (Phase E will call these from a payment
-- webhook handler running as service_role). Never exposed to authenticated
-- clients — no client can mark its own order paid.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.mark_commerce_order_paid(p_order_id UUID)
RETURNS public.commerce_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.commerce_orders;
  v_item RECORD;
BEGIN
  SELECT * INTO v_order FROM public.commerce_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'order_not_found'; END IF;
  IF v_order.payment_status <> 'pending_payment' THEN
    RAISE EXCEPTION 'invalid_payment_state';
  END IF;

  FOR v_item IN
    SELECT oi.product_id, oi.quantity
    FROM public.commerce_order_items oi
    JOIN public.products p ON p.id = oi.product_id
    WHERE oi.order_id = v_order.id AND p.tracks_inventory = true
  LOOP
    UPDATE public.product_stock SET
      quantity_on_hand = GREATEST(quantity_on_hand - v_item.quantity, 0),
      quantity_reserved = GREATEST(quantity_reserved - v_item.quantity, 0),
      updated_at = now()
    WHERE product_id = v_item.product_id;

    INSERT INTO public.product_stock_movements (
      product_id, company_id, quantity, movement_type, reference_type, reference_id
    ) VALUES (
      v_item.product_id, v_order.vendor_company_id, v_item.quantity, 'sale_deduction', 'commerce_order', v_order.id
    );
  END LOOP;

  UPDATE public.commerce_orders SET payment_status = 'paid', updated_at = now()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  RETURN v_order;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_commerce_order_paid(UUID) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.mark_commerce_order_payment_failed(p_order_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS public.commerce_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.commerce_orders;
  v_item RECORD;
BEGIN
  SELECT * INTO v_order FROM public.commerce_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'order_not_found'; END IF;
  IF v_order.payment_status <> 'pending_payment' THEN
    RAISE EXCEPTION 'invalid_payment_state';
  END IF;

  FOR v_item IN
    SELECT oi.product_id, oi.quantity
    FROM public.commerce_order_items oi
    JOIN public.products p ON p.id = oi.product_id
    WHERE oi.order_id = v_order.id AND p.tracks_inventory = true
  LOOP
    UPDATE public.product_stock SET
      quantity_reserved = GREATEST(quantity_reserved - v_item.quantity, 0), updated_at = now()
    WHERE product_id = v_item.product_id;

    INSERT INTO public.product_stock_movements (
      product_id, company_id, quantity, movement_type, reference_type, reference_id, notes
    ) VALUES (
      v_item.product_id, v_order.vendor_company_id, v_item.quantity, 'release', 'commerce_order', v_order.id, p_reason
    );
  END LOOP;

  UPDATE public.commerce_orders SET
    payment_status = 'payment_failed',
    fulfillment_status = 'cancelled',
    cancelled_at = now(),
    cancellation_reason = COALESCE(p_reason, 'payment_failed')
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  RETURN v_order;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_commerce_order_payment_failed(UUID, TEXT) FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- RPCs: Super Admin vendor review + commerce fee rule configuration
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_set_vendor_state(
  p_company_id UUID,
  p_state TEXT,
  p_reason TEXT DEFAULT NULL
)
RETURNS public.store_profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.store_profiles;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF p_state NOT IN ('draft', 'pending_review', 'active', 'suspended', 'rejected') THEN
    RAISE EXCEPTION 'invalid_vendor_state';
  END IF;

  UPDATE public.store_profiles SET
    status = p_state::public.commerce_vendor_state,
    status_reason = p_reason,
    reviewed_by = auth.uid(),
    reviewed_at = now()
  WHERE company_id = p_company_id
  RETURNING * INTO v_row;

  IF NOT FOUND THEN RAISE EXCEPTION 'store_profile_not_found'; END IF;

  PERFORM public.log_audit_event(
    p_company_id, 'vendor_state_changed', 'store_profiles', p_company_id,
    jsonb_build_object('state', p_state, 'reason', p_reason)
  );

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_set_vendor_state TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_list_vendor_stores(
  p_status TEXT DEFAULT NULL,
  p_search TEXT DEFAULT NULL,
  p_limit INT DEFAULT 25,
  p_offset INT DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total INT;
  v_rows JSONB;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT COUNT(*)::INT INTO v_total
  FROM public.store_profiles sp
  JOIN public.companies c ON c.id = sp.company_id
  WHERE (p_status IS NULL OR sp.status::TEXT = p_status)
    AND (p_search IS NULL OR p_search = '' OR sp.display_name ILIKE '%' || p_search || '%' OR c.name ILIKE '%' || p_search || '%');

  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::JSONB) INTO v_rows
  FROM (
    SELECT sp.company_id, sp.slug, sp.display_name, sp.status, sp.status_reason,
      sp.reviewed_at, c.name AS company_name, c.status AS company_status,
      (SELECT COUNT(*) FROM public.products p WHERE p.company_id = sp.company_id) AS product_count
    FROM public.store_profiles sp
    JOIN public.companies c ON c.id = sp.company_id
    WHERE (p_status IS NULL OR sp.status::TEXT = p_status)
      AND (p_search IS NULL OR p_search = '' OR sp.display_name ILIKE '%' || p_search || '%' OR c.name ILIKE '%' || p_search || '%')
    ORDER BY sp.created_at DESC
    LIMIT LEAST(GREATEST(p_limit, 1), 100)
    OFFSET GREATEST(p_offset, 0)
  ) t;

  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_list_vendor_stores TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_upsert_commerce_fee_rule(p_payload JSONB)
RETURNS public.commerce_fee_rules
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.commerce_fee_rules;
  v_id UUID := NULLIF(p_payload ->> 'id', '')::UUID;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  IF COALESCE((p_payload ->> 'is_platform_default')::BOOLEAN, false) THEN
    UPDATE public.commerce_fee_rules SET is_platform_default = false WHERE is_platform_default = true;
  END IF;

  IF v_id IS NULL THEN
    INSERT INTO public.commerce_fee_rules (
      name, fee_model, fixed_fee_lrd_cents, percentage_bps, is_active, is_platform_default,
      applies_to_vendor_company_id, created_by
    ) VALUES (
      p_payload ->> 'name',
      COALESCE((p_payload ->> 'fee_model')::public.marketplace_fee_model, 'zero_commission'),
      COALESCE((p_payload ->> 'fixed_fee_lrd_cents')::INT, 0),
      COALESCE((p_payload ->> 'percentage_bps')::INT, 0),
      COALESCE((p_payload ->> 'is_active')::BOOLEAN, true),
      COALESCE((p_payload ->> 'is_platform_default')::BOOLEAN, false),
      NULLIF(p_payload ->> 'applies_to_vendor_company_id', '')::UUID,
      auth.uid()
    )
    RETURNING * INTO v_row;
  ELSE
    UPDATE public.commerce_fee_rules SET
      name = COALESCE(p_payload ->> 'name', name),
      fee_model = COALESCE((p_payload ->> 'fee_model')::public.marketplace_fee_model, fee_model),
      fixed_fee_lrd_cents = COALESCE((p_payload ->> 'fixed_fee_lrd_cents')::INT, fixed_fee_lrd_cents),
      percentage_bps = COALESCE((p_payload ->> 'percentage_bps')::INT, percentage_bps),
      is_active = COALESCE((p_payload ->> 'is_active')::BOOLEAN, is_active),
      is_platform_default = COALESCE((p_payload ->> 'is_platform_default')::BOOLEAN, is_platform_default),
      updated_at = now()
    WHERE id = v_id
    RETURNING * INTO v_row;
    IF NOT FOUND THEN RAISE EXCEPTION 'fee_rule_not_found'; END IF;
  END IF;

  PERFORM public.log_audit_event(NULL, 'commerce_fee_rule_upserted', 'commerce_fee_rules', v_row.id, to_jsonb(v_row));

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_upsert_commerce_fee_rule TO authenticated;
