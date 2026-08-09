-- DeliveryOS · Phase 5: field ops schema (GPS, zones, API keys, webhooks, SMS outbox)

-- ---------------------------------------------------------------------------
-- Rider tracking state
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE public.rider_tracking_state AS ENUM (
    'off', 'available', 'active_delivery', 'paused'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Current location only (one row per rider — no unbounded history)
CREATE TABLE IF NOT EXISTS public.rider_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  rider_id UUID NOT NULL REFERENCES public.riders (id) ON DELETE CASCADE,
  delivery_id UUID REFERENCES public.deliveries (id) ON DELETE SET NULL,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  accuracy DOUBLE PRECISION,
  heading DOUBLE PRECISION,
  speed DOUBLE PRECISION,
  tracking_state public.rider_tracking_state NOT NULL DEFAULT 'off',
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT rider_locations_rider_unique UNIQUE (rider_id)
);

CREATE INDEX IF NOT EXISTS idx_rider_locations_company ON public.rider_locations (company_id);
CREATE INDEX IF NOT EXISTS idx_rider_locations_recorded ON public.rider_locations (company_id, recorded_at DESC);

CREATE TRIGGER rider_locations_updated_at
  BEFORE UPDATE ON public.rider_locations
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Optional short audit trail (retention: purge > 48h via scheduled job)
CREATE TABLE IF NOT EXISTS public.rider_location_samples (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  rider_id UUID NOT NULL REFERENCES public.riders (id) ON DELETE CASCADE,
  delivery_id UUID REFERENCES public.deliveries (id) ON DELETE SET NULL,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_rider_location_samples_purge
  ON public.rider_location_samples (recorded_at);

-- ---------------------------------------------------------------------------
-- Delivery zones & pricing
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.delivery_zones (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  area_label TEXT,
  base_fee_cents INT NOT NULL DEFAULT 0,
  currency TEXT NOT NULL DEFAULT 'LRD',
  is_active BOOLEAN NOT NULL DEFAULT true,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (company_id, name)
);

CREATE INDEX IF NOT EXISTS idx_delivery_zones_company ON public.delivery_zones (company_id, is_active);

CREATE TRIGGER delivery_zones_updated_at
  BEFORE UPDATE ON public.delivery_zones
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.deliveries
  ADD COLUMN IF NOT EXISTS delivery_zone_id UUID REFERENCES public.delivery_zones (id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS delivery_fee_manual_override BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_deliveries_zone ON public.deliveries (company_id, delivery_zone_id);

-- ---------------------------------------------------------------------------
-- API keys (hashed only)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.api_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  key_prefix TEXT NOT NULL,
  hashed_key TEXT NOT NULL,
  permissions JSONB NOT NULL DEFAULT '[]'::JSONB,
  last_used_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_by UUID REFERENCES auth.users (id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_api_keys_company ON public.api_keys (company_id, is_active);
CREATE INDEX IF NOT EXISTS idx_api_keys_prefix ON public.api_keys (key_prefix) WHERE is_active = true;

CREATE TRIGGER api_keys_updated_at
  BEFORE UPDATE ON public.api_keys
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Webhooks
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.webhook_endpoints (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  url TEXT NOT NULL,
  secret TEXT NOT NULL,
  events TEXT[] NOT NULL DEFAULT '{}',
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_webhook_endpoints_company ON public.webhook_endpoints (company_id, is_active);

CREATE TRIGGER webhook_endpoints_updated_at
  BEFORE UPDATE ON public.webhook_endpoints
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DO $$ BEGIN
  CREATE TYPE public.webhook_delivery_status AS ENUM (
    'pending', 'delivered', 'failed', 'dead'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS public.webhook_deliveries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  webhook_endpoint_id UUID NOT NULL REFERENCES public.webhook_endpoints (id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  payload JSONB NOT NULL,
  status public.webhook_delivery_status NOT NULL DEFAULT 'pending',
  attempt_count INT NOT NULL DEFAULT 0,
  last_error TEXT,
  next_retry_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  delivered_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_pending
  ON public.webhook_deliveries (status, next_retry_at)
  WHERE status IN ('pending', 'failed');

-- ---------------------------------------------------------------------------
-- SMS outbox (provider-agnostic)
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE public.sms_outbox_status AS ENUM (
    'pending', 'sent', 'failed', 'dead'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS public.sms_outbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  phone TEXT NOT NULL,
  body TEXT NOT NULL,
  delivery_id UUID REFERENCES public.deliveries (id) ON DELETE SET NULL,
  provider TEXT NOT NULL DEFAULT 'stub',
  status public.sms_outbox_status NOT NULL DEFAULT 'pending',
  attempt_count INT NOT NULL DEFAULT 0,
  last_error TEXT,
  provider_message_id TEXT,
  cost_cents INT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  sent_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_sms_outbox_pending ON public.sms_outbox (status, created_at)
  WHERE status = 'pending';

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.rider_locations;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN undefined_object THEN NULL;
END $$;
