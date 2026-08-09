-- DeliveryOS · Phase 7: Logistics network & marketplace

CREATE TYPE public.company_business_type AS ENUM (
  'logistics_provider',
  'merchant',
  'hybrid'
);

CREATE TYPE public.delivery_request_status AS ENUM (
  'draft',
  'open',
  'offered',
  'accepted',
  'cancelled',
  'expired',
  'converted'
);

CREATE TYPE public.delivery_offer_status AS ENUM (
  'pending',
  'accepted',
  'rejected',
  'expired',
  'withdrawn'
);

CREATE TYPE public.merchant_provider_relationship_type AS ENUM (
  'preferred',
  'blocked',
  'contracted',
  'marketplace'
);

CREATE TYPE public.marketplace_fee_model AS ENUM (
  'fixed',
  'percentage',
  'subscription_only',
  'zero_commission'
);

CREATE TYPE public.marketplace_transaction_status AS ENUM (
  'pending',
  'earned',
  'settled',
  'refunded',
  'cancelled',
  'disputed'
);

CREATE TYPE public.marketplace_ledger_account AS ENUM (
  'merchant_payable',
  'provider_receivable',
  'platform_revenue'
);

CREATE TYPE public.marketplace_dispute_status AS ENUM (
  'open',
  'under_review',
  'resolved',
  'rejected'
);

CREATE TYPE public.marketplace_dispute_reason AS ENUM (
  'delivery_not_completed',
  'cod_issue',
  'damage',
  'incorrect_charge',
  'provider_issue',
  'merchant_issue',
  'other'
);

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS business_type public.company_business_type NOT NULL DEFAULT 'logistics_provider',
  ADD COLUMN IF NOT EXISTS marketplace_suspended BOOLEAN NOT NULL DEFAULT false;

UPDATE public.companies SET business_type = 'logistics_provider' WHERE business_type IS NULL;

ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS marketplace_access BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS merchant_portal BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS provider_network BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS marketplace_api BOOLEAN NOT NULL DEFAULT false;

UPDATE public.subscriptions SET
  marketplace_access = (slug IN ('business', 'enterprise')),
  merchant_portal = (slug IN ('starter', 'business', 'enterprise')),
  provider_network = (slug IN ('business', 'enterprise')),
  marketplace_api = (slug = 'enterprise')
WHERE slug IN ('starter', 'business', 'enterprise');

ALTER TABLE public.deliveries
  ADD COLUMN IF NOT EXISTS delivery_request_id UUID,
  ADD COLUMN IF NOT EXISTS merchant_company_id UUID REFERENCES public.companies (id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_deliveries_merchant ON public.deliveries (merchant_company_id)
  WHERE merchant_company_id IS NOT NULL;

-- Provider marketplace profile (opt-in)
CREATE TABLE IF NOT EXISTS public.provider_marketplace_profiles (
  company_id UUID PRIMARY KEY REFERENCES public.companies (id) ON DELETE CASCADE,
  marketplace_enabled BOOLEAN NOT NULL DEFAULT false,
  service_description TEXT,
  service_phone TEXT,
  service_email TEXT,
  service_regions JSONB NOT NULL DEFAULT '[]'::JSONB,
  accepting_jobs BOOLEAN NOT NULL DEFAULT false,
  minimum_delivery_fee_lrd_cents INT NOT NULL DEFAULT 0,
  maximum_service_distance_km NUMERIC(8, 2),
  rating_visible BOOLEAN NOT NULL DEFAULT true,
  business_hours JSONB NOT NULL DEFAULT '{}'::JSONB,
  admin_marketplace_disabled BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.provider_marketplace_zones (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  delivery_zone_id UUID NOT NULL REFERENCES public.delivery_zones (id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (provider_company_id, delivery_zone_id)
);

CREATE INDEX IF NOT EXISTS idx_provider_marketplace_zones_provider
  ON public.provider_marketplace_zones (provider_company_id);

CREATE TABLE IF NOT EXISTS public.delivery_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  pickup_branch_id UUID REFERENCES public.company_branches (id) ON DELETE SET NULL,
  customer_id UUID REFERENCES public.customers (id) ON DELETE SET NULL,
  pickup_address TEXT NOT NULL,
  pickup_latitude DOUBLE PRECISION,
  pickup_longitude DOUBLE PRECISION,
  pickup_area_summary TEXT,
  destination_address TEXT NOT NULL,
  destination_latitude DOUBLE PRECISION,
  destination_longitude DOUBLE PRECISION,
  destination_area_summary TEXT,
  zone_id UUID REFERENCES public.delivery_zones (id) ON DELETE SET NULL,
  package_count INT NOT NULL DEFAULT 1,
  weight_kg NUMERIC(10, 3),
  fragile BOOLEAN NOT NULL DEFAULT false,
  cod_amount_lrd_cents INT NOT NULL DEFAULT 0,
  delivery_notes TEXT,
  customer_name TEXT,
  customer_phone TEXT,
  package_description TEXT,
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  status public.delivery_request_status NOT NULL DEFAULT 'draft',
  selected_provider_id UUID REFERENCES public.companies (id) ON DELETE SET NULL,
  quoted_amount_lrd_cents INT,
  currency TEXT NOT NULL DEFAULT 'LRD',
  accepted_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ,
  converted_delivery_id UUID REFERENCES public.deliveries (id) ON DELETE SET NULL,
  cancellation_reason TEXT,
  cancelled_at TIMESTAMPTZ,
  created_by UUID REFERENCES auth.users (id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_delivery_requests_merchant_status
  ON public.delivery_requests (merchant_company_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS public.delivery_offers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_request_id UUID NOT NULL REFERENCES public.delivery_requests (id) ON DELETE CASCADE,
  provider_company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  quoted_amount_lrd_cents INT NOT NULL,
  currency TEXT NOT NULL DEFAULT 'LRD',
  estimated_pickup_minutes INT,
  status public.delivery_offer_status NOT NULL DEFAULT 'pending',
  offered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at TIMESTAMPTZ,
  rejected_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (delivery_request_id, provider_company_id)
);

CREATE INDEX IF NOT EXISTS idx_delivery_offers_provider_status
  ON public.delivery_offers (provider_company_id, status, offered_at DESC);

CREATE INDEX IF NOT EXISTS idx_delivery_offers_request
  ON public.delivery_offers (delivery_request_id, status);

CREATE TABLE IF NOT EXISTS public.merchant_provider_relationships (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  provider_company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  relationship_type public.merchant_provider_relationship_type NOT NULL DEFAULT 'marketplace',
  notes TEXT,
  created_by UUID REFERENCES auth.users (id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (merchant_company_id, provider_company_id)
);

CREATE INDEX IF NOT EXISTS idx_merchant_provider_merchant
  ON public.merchant_provider_relationships (merchant_company_id, relationship_type);

CREATE TABLE IF NOT EXISTS public.marketplace_fee_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  fee_model public.marketplace_fee_model NOT NULL DEFAULT 'percentage',
  fixed_fee_lrd_cents INT NOT NULL DEFAULT 0,
  percentage_bps INT NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  is_platform_default BOOLEAN NOT NULL DEFAULT false,
  applies_to_merchant_company_id UUID REFERENCES public.companies (id) ON DELETE CASCADE,
  applies_to_provider_company_id UUID REFERENCES public.companies (id) ON DELETE CASCADE,
  created_by UUID REFERENCES auth.users (id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_marketplace_fee_rules_default
  ON public.marketplace_fee_rules (is_platform_default)
  WHERE is_platform_default = true;

INSERT INTO public.marketplace_fee_rules (name, fee_model, percentage_bps, is_active, is_platform_default)
SELECT 'Platform default 10%', 'percentage', 1000, true, true
WHERE NOT EXISTS (
  SELECT 1 FROM public.marketplace_fee_rules WHERE is_platform_default = true
);

CREATE TABLE IF NOT EXISTS public.marketplace_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_request_id UUID NOT NULL REFERENCES public.delivery_requests (id) ON DELETE RESTRICT,
  merchant_company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  provider_company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  delivery_id UUID REFERENCES public.deliveries (id) ON DELETE SET NULL,
  gross_amount_lrd_cents INT NOT NULL,
  platform_fee_lrd_cents INT NOT NULL,
  provider_amount_lrd_cents INT NOT NULL,
  currency TEXT NOT NULL DEFAULT 'LRD',
  status public.marketplace_transaction_status NOT NULL DEFAULT 'pending',
  settled_at TIMESTAMPTZ,
  settlement_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_marketplace_transactions_request
  ON public.marketplace_transactions (delivery_request_id);

CREATE INDEX IF NOT EXISTS idx_marketplace_transactions_provider
  ON public.marketplace_transactions (provider_company_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS public.marketplace_ledger_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID REFERENCES public.companies (id) ON DELETE SET NULL,
  account_type public.marketplace_ledger_account NOT NULL,
  marketplace_transaction_id UUID REFERENCES public.marketplace_transactions (id) ON DELETE RESTRICT,
  amount_lrd_cents INT NOT NULL,
  currency TEXT NOT NULL DEFAULT 'LRD',
  description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_marketplace_ledger_company
  ON public.marketplace_ledger_entries (company_id, account_type, created_at DESC);

CREATE TABLE IF NOT EXISTS public.marketplace_settlements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  marketplace_transaction_id UUID NOT NULL REFERENCES public.marketplace_transactions (id) ON DELETE RESTRICT,
  merchant_paid_platform BOOLEAN NOT NULL DEFAULT false,
  platform_paid_provider BOOLEAN NOT NULL DEFAULT false,
  provider_collected_cod BOOLEAN NOT NULL DEFAULT false,
  net_settlement_notes TEXT,
  recorded_by UUID REFERENCES auth.users (id) ON DELETE SET NULL,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_marketplace_settlements_tx
  ON public.marketplace_settlements (marketplace_transaction_id);

CREATE TABLE IF NOT EXISTS public.provider_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  provider_company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  delivery_id UUID NOT NULL REFERENCES public.deliveries (id) ON DELETE CASCADE,
  delivery_request_id UUID REFERENCES public.delivery_requests (id) ON DELETE SET NULL,
  rating SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment TEXT,
  created_by UUID REFERENCES auth.users (id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (delivery_id)
);

CREATE TABLE IF NOT EXISTS public.marketplace_disputes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_request_id UUID NOT NULL REFERENCES public.delivery_requests (id) ON DELETE CASCADE,
  marketplace_transaction_id UUID REFERENCES public.marketplace_transactions (id) ON DELETE SET NULL,
  merchant_company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  provider_company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  reason public.marketplace_dispute_reason NOT NULL,
  description TEXT,
  status public.marketplace_dispute_status NOT NULL DEFAULT 'open',
  resolution_notes TEXT,
  created_by UUID REFERENCES auth.users (id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_marketplace_disputes_status
  ON public.marketplace_disputes (status, created_at DESC);

ALTER TABLE public.delivery_requests
  ADD CONSTRAINT fk_delivery_requests_converted_delivery
  FOREIGN KEY (converted_delivery_id) REFERENCES public.deliveries (id) ON DELETE SET NULL;

ALTER TABLE public.deliveries
  ADD CONSTRAINT fk_deliveries_delivery_request
  FOREIGN KEY (delivery_request_id) REFERENCES public.delivery_requests (id) ON DELETE SET NULL;

-- RLS enable
ALTER TABLE public.provider_marketplace_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.provider_marketplace_zones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_offers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_provider_relationships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_fee_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_ledger_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_settlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.provider_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_disputes ENABLE ROW LEVEL SECURITY;
