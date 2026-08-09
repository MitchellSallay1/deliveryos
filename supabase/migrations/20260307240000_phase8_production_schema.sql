-- DeliveryOS · Phase 8: production launch (queues, email, tracking hardening, indexes)

-- ---------------------------------------------------------------------------
-- SMS outbox lifecycle (processing + retry scheduling)
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  ALTER TYPE public.sms_outbox_status ADD VALUE IF NOT EXISTS 'processing';
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE public.sms_outbox
  ADD COLUMN IF NOT EXISTS next_attempt_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_attempt_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_sms_outbox_retry
  ON public.sms_outbox (status, next_attempt_at, created_at)
  WHERE status IN ('pending', 'failed');

-- ---------------------------------------------------------------------------
-- Email outbox (transactional)
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE public.email_outbox_status AS ENUM (
    'pending', 'processing', 'sent', 'failed', 'dead'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS public.email_outbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID REFERENCES public.companies (id) ON DELETE SET NULL,
  to_email TEXT NOT NULL,
  template_key TEXT NOT NULL,
  subject TEXT NOT NULL,
  body_html TEXT NOT NULL,
  body_text TEXT,
  payload JSONB NOT NULL DEFAULT '{}'::JSONB,
  status public.email_outbox_status NOT NULL DEFAULT 'pending',
  attempt_count INT NOT NULL DEFAULT 0,
  last_error TEXT,
  provider TEXT NOT NULL DEFAULT 'stub',
  provider_message_id TEXT,
  next_attempt_at TIMESTAMPTZ,
  last_attempt_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  sent_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_email_outbox_pending
  ON public.email_outbox (status, next_attempt_at, created_at)
  WHERE status IN ('pending', 'failed');

ALTER TABLE public.email_outbox ENABLE ROW LEVEL SECURITY;

CREATE POLICY email_outbox_admin ON public.email_outbox
  FOR SELECT TO authenticated
  USING (public.is_super_admin());

-- ---------------------------------------------------------------------------
-- Public tracking rate limit (IP bucket, no auth)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.public_tracking_rate_limits (
  client_key TEXT PRIMARY KEY,
  window_start TIMESTAMPTZ NOT NULL DEFAULT now(),
  request_count INT NOT NULL DEFAULT 0
);

-- ---------------------------------------------------------------------------
-- Webhook delivery diagnostics
-- ---------------------------------------------------------------------------
ALTER TABLE public.webhook_deliveries
  ADD COLUMN IF NOT EXISTS response_status INT,
  ADD COLUMN IF NOT EXISTS response_body_preview TEXT;

-- ---------------------------------------------------------------------------
-- API auth failure log (minimal, no secrets)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.api_auth_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key_prefix TEXT,
  company_id UUID REFERENCES public.companies (id) ON DELETE SET NULL,
  success BOOLEAN NOT NULL,
  error_code TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_api_auth_events_created ON public.api_auth_events (created_at DESC);

ALTER TABLE public.api_auth_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY api_auth_events_admin ON public.api_auth_events
  FOR SELECT TO authenticated
  USING (public.is_super_admin());

-- ---------------------------------------------------------------------------
-- Performance indexes (query patterns)
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_deliveries_tracking_code
  ON public.deliveries (tracking_code);

CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_retry
  ON public.webhook_deliveries (status, next_retry_at)
  WHERE status IN ('pending', 'failed');

CREATE INDEX IF NOT EXISTS idx_audit_logs_company_created
  ON public.audit_logs (company_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_delivery_offers_request_provider
  ON public.delivery_offers (delivery_request_id, provider_company_id);
