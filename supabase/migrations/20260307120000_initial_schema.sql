-- DeliveryOS · core schema (multi-tenant, Supabase-native)
-- Run via: supabase db push / supabase migration up

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
CREATE TYPE public.company_status AS ENUM ('pending', 'active', 'suspended');
CREATE TYPE public.company_role AS ENUM (
  'company_owner',
  'dispatcher',
  'rider',
  'support_staff'
);
CREATE TYPE public.rider_status AS ENUM ('available', 'busy', 'offline', 'suspended');
CREATE TYPE public.delivery_status AS ENUM (
  'pending',
  'assigned',
  'accepted',
  'picked_up',
  'in_transit',
  'delivered',
  'failed',
  'cancelled'
);
CREATE TYPE public.payment_status AS ENUM ('pending', 'collected', 'deposited', 'reconciled');

-- ---------------------------------------------------------------------------
-- Roles catalog (reference; company membership uses company_role enum)
-- ---------------------------------------------------------------------------
CREATE TABLE public.roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO public.roles (slug, name, description) VALUES
  ('company_owner', 'Company Owner', 'Full workspace access'),
  ('dispatcher', 'Dispatcher', 'Create and assign deliveries'),
  ('rider', 'Rider', 'Execute deliveries'),
  ('support_staff', 'Support Staff', 'Read-only and customer support');

-- ---------------------------------------------------------------------------
-- Subscriptions (plans)
-- ---------------------------------------------------------------------------
CREATE TABLE public.subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  max_riders INT NOT NULL,
  max_deliveries_per_month INT,
  price_lrd_cents INT NOT NULL DEFAULT 0,
  features JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO public.subscriptions (slug, name, max_riders, max_deliveries_per_month, price_lrd_cents) VALUES
  ('starter', 'Starter', 5, 200, 200000),
  ('business', 'Business', 20, NULL, 500000),
  ('enterprise', 'Enterprise', 2147483647, NULL, 0);

-- ---------------------------------------------------------------------------
-- Profiles (1:1 with auth.users)
-- ---------------------------------------------------------------------------
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  full_name TEXT,
  phone TEXT,
  avatar_url TEXT,
  is_super_admin BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Companies (tenants)
-- ---------------------------------------------------------------------------
CREATE TABLE public.companies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  logo_url TEXT,
  phone TEXT NOT NULL,
  email TEXT NOT NULL,
  address TEXT,
  status public.company_status NOT NULL DEFAULT 'pending',
  subscription_id UUID NOT NULL REFERENCES public.subscriptions (id),
  sms_credits INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_companies_status ON public.companies (status);

-- ---------------------------------------------------------------------------
-- Company membership (tenant + role)
-- ---------------------------------------------------------------------------
CREATE TABLE public.company_users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  role public.company_role NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (company_id, user_id)
);

CREATE INDEX idx_company_users_user ON public.company_users (user_id);
CREATE INDEX idx_company_users_company ON public.company_users (company_id);

-- ---------------------------------------------------------------------------
-- Riders
-- ---------------------------------------------------------------------------
CREATE TABLE public.riders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users (id) ON DELETE SET NULL,
  rider_code TEXT NOT NULL,
  full_name TEXT NOT NULL,
  phone TEXT NOT NULL,
  status public.rider_status NOT NULL DEFAULT 'offline',
  completed_deliveries INT NOT NULL DEFAULT 0,
  rating NUMERIC(3, 2) NOT NULL DEFAULT 5.00,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (company_id, rider_code),
  UNIQUE (company_id, phone)
);

CREATE INDEX idx_riders_company ON public.riders (company_id);

-- ---------------------------------------------------------------------------
-- Customers
-- ---------------------------------------------------------------------------
CREATE TABLE public.customers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  full_name TEXT NOT NULL,
  phone TEXT NOT NULL,
  address TEXT,
  landmark TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (company_id, phone)
);

CREATE INDEX idx_customers_company ON public.customers (company_id);

-- ---------------------------------------------------------------------------
-- Deliveries
-- ---------------------------------------------------------------------------
CREATE TABLE public.deliveries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  tracking_code TEXT NOT NULL UNIQUE,
  pickup_business_name TEXT NOT NULL,
  pickup_address TEXT NOT NULL,
  customer_id UUID REFERENCES public.customers (id) ON DELETE SET NULL,
  customer_name TEXT NOT NULL,
  customer_phone TEXT NOT NULL,
  destination_address TEXT NOT NULL,
  package_description TEXT,
  amount_to_collect_lrd_cents INT NOT NULL DEFAULT 0,
  delivery_fee_lrd_cents INT NOT NULL DEFAULT 0,
  status public.delivery_status NOT NULL DEFAULT 'pending',
  rider_id UUID REFERENCES public.riders (id) ON DELETE SET NULL,
  assigned_at TIMESTAMPTZ,
  accepted_at TIMESTAMPTZ,
  picked_up_at TIMESTAMPTZ,
  in_transit_at TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  failed_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  failure_reason TEXT,
  created_by UUID REFERENCES auth.users (id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_deliveries_company_status ON public.deliveries (company_id, status);
CREATE INDEX idx_deliveries_rider ON public.deliveries (rider_id) WHERE rider_id IS NOT NULL;
CREATE INDEX idx_deliveries_created ON public.deliveries (company_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- Delivery status history (audit trail)
-- ---------------------------------------------------------------------------
CREATE TABLE public.delivery_status_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id UUID NOT NULL REFERENCES public.deliveries (id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  from_status public.delivery_status,
  to_status public.delivery_status NOT NULL,
  changed_by UUID REFERENCES auth.users (id) ON DELETE SET NULL,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_delivery_history_delivery ON public.delivery_status_history (delivery_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- Payments (COD tracking)
-- ---------------------------------------------------------------------------
CREATE TABLE public.payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  delivery_id UUID NOT NULL REFERENCES public.deliveries (id) ON DELETE CASCADE,
  amount_lrd_cents INT NOT NULL,
  status public.payment_status NOT NULL DEFAULT 'pending',
  collected_by UUID REFERENCES public.riders (id) ON DELETE SET NULL,
  collected_at TIMESTAMPTZ,
  deposited_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (delivery_id)
);

CREATE INDEX idx_payments_company_status ON public.payments (company_id, status);

-- ---------------------------------------------------------------------------
-- Notifications & SMS logs
-- ---------------------------------------------------------------------------
CREATE TABLE public.notification_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID REFERENCES public.companies (id) ON DELETE CASCADE,
  channel TEXT NOT NULL,
  recipient TEXT NOT NULL,
  subject TEXT,
  body TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'queued',
  metadata JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_notification_logs_company ON public.notification_logs (company_id, created_at DESC);

CREATE TABLE public.sms_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  direction TEXT NOT NULL CHECK (direction IN ('outbound', 'inbound')),
  phone TEXT NOT NULL,
  body TEXT NOT NULL,
  credits_used INT NOT NULL DEFAULT 0,
  delivery_id UUID REFERENCES public.deliveries (id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_sms_logs_company ON public.sms_logs (company_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- Delivery photos (Storage object path)
-- ---------------------------------------------------------------------------
CREATE TABLE public.delivery_photos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  delivery_id UUID NOT NULL REFERENCES public.deliveries (id) ON DELETE CASCADE,
  storage_path TEXT NOT NULL,
  uploaded_by UUID REFERENCES auth.users (id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_delivery_photos_delivery ON public.delivery_photos (delivery_id);

-- ---------------------------------------------------------------------------
-- Timestamps trigger
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER profiles_updated_at BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER companies_updated_at BEFORE UPDATE ON public.companies
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER riders_updated_at BEFORE UPDATE ON public.riders
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER customers_updated_at BEFORE UPDATE ON public.customers
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER deliveries_updated_at BEFORE UPDATE ON public.deliveries
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER payments_updated_at BEFORE UPDATE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Auth: auto-create profile
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'full_name', NEW.email)
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Onboarding RPC (company + owner membership) — SECURITY DEFINER
-- Why: client cannot insert into companies without bypassing RLS safely;
-- this function validates auth.uid() and writes in one transaction.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_company_with_owner(
  p_name TEXT,
  p_phone TEXT,
  p_email TEXT,
  p_address TEXT DEFAULT NULL
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
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  v_slug := lower(regexp_replace(trim(p_name), '[^a-zA-Z0-9]+', '-', 'g'));
  v_slug := trim(both '-' from v_slug);
  IF v_slug = '' THEN
    RAISE EXCEPTION 'invalid company name';
  END IF;

  SELECT id INTO v_sub_id FROM public.subscriptions WHERE slug = 'starter' LIMIT 1;

  INSERT INTO public.companies (name, slug, phone, email, address, subscription_id)
  VALUES (p_name, v_slug, p_phone, p_email, p_address, v_sub_id)
  RETURNING id INTO v_company_id;

  INSERT INTO public.company_users (company_id, user_id, role)
  VALUES (v_company_id, auth.uid(), 'company_owner');

  RETURN v_company_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_company_with_owner TO authenticated;
