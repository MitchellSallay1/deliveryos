-- DeliveryOS · Phase 4: billing schema (provider-independent)

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE public.company_subscription_status AS ENUM (
    'trialing', 'active', 'past_due', 'suspended', 'cancelled', 'expired'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE public.invoice_status AS ENUM (
    'draft', 'issued', 'paid', 'overdue', 'cancelled'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE public.billing_payment_method AS ENUM (
    'cash', 'mtn_momo', 'orange_money', 'bank_transfer', 'other'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ---------------------------------------------------------------------------
-- Upgrade plan catalog (subscriptions = billing plans)
-- ---------------------------------------------------------------------------
ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS currency TEXT NOT NULL DEFAULT 'LRD',
  ADD COLUMN IF NOT EXISTS monthly_sms_allowance INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS proof_of_delivery BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS advanced_reports BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS api_access BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS gps_tracking BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS custom_branding BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;

UPDATE public.subscriptions SET
  currency = 'LRD',
  monthly_sms_allowance = CASE slug
    WHEN 'starter' THEN 200
    WHEN 'business' THEN 2000
    WHEN 'enterprise' THEN 100000
    ELSE monthly_sms_allowance
  END,
  proof_of_delivery = true,
  advanced_reports = (slug IN ('business', 'enterprise')),
  api_access = (slug = 'enterprise'),
  gps_tracking = (slug = 'enterprise'),
  custom_branding = (slug IN ('business', 'enterprise')),
  is_active = true
WHERE slug IN ('starter', 'business', 'enterprise');

-- ---------------------------------------------------------------------------
-- Company subscription lifecycle
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.company_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  plan_id UUID NOT NULL REFERENCES public.subscriptions (id),
  status public.company_subscription_status NOT NULL DEFAULT 'active',
  starts_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  current_period_start TIMESTAMPTZ NOT NULL DEFAULT date_trunc('month', now() AT TIME ZONE 'Africa/Monrovia'),
  current_period_end TIMESTAMPTZ NOT NULL DEFAULT (date_trunc('month', now() AT TIME ZONE 'Africa/Monrovia') + INTERVAL '1 month'),
  trial_ends_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_company_subscriptions_company
  ON public.company_subscriptions (company_id, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_company_subscriptions_one_open
  ON public.company_subscriptions (company_id)
  WHERE status IN ('trialing', 'active', 'past_due');

CREATE TRIGGER company_subscriptions_updated_at
  BEFORE UPDATE ON public.company_subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Backfill one active subscription per company from legacy subscription_id
INSERT INTO public.company_subscriptions (
  company_id, plan_id, status, starts_at, current_period_start, current_period_end
)
SELECT
  c.id,
  c.subscription_id,
  'active'::public.company_subscription_status,
  c.created_at,
  (date_trunc('month', (current_timestamp AT TIME ZONE 'Africa/Monrovia')) AT TIME ZONE 'Africa/Monrovia'),
  ((date_trunc('month', (current_timestamp AT TIME ZONE 'Africa/Monrovia')) + INTERVAL '1 month') AT TIME ZONE 'Africa/Monrovia')
FROM public.companies c
WHERE NOT EXISTS (
  SELECT 1 FROM public.company_subscriptions cs WHERE cs.company_id = c.id
);

-- ---------------------------------------------------------------------------
-- Invoices
-- ---------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS public.invoice_number_seq START 1000;

CREATE TABLE IF NOT EXISTS public.invoices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_number TEXT NOT NULL UNIQUE DEFAULT (
    'INV-' || to_char(now() AT TIME ZONE 'Africa/Monrovia', 'YYYYMM') || '-' ||
    lpad(nextval('public.invoice_number_seq')::TEXT, 5, '0')
  ),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  company_subscription_id UUID REFERENCES public.company_subscriptions (id) ON DELETE SET NULL,
  plan_id UUID NOT NULL REFERENCES public.subscriptions (id),
  billing_period_start TIMESTAMPTZ NOT NULL,
  billing_period_end TIMESTAMPTZ NOT NULL,
  amount_cents INT NOT NULL,
  currency TEXT NOT NULL DEFAULT 'LRD',
  status public.invoice_status NOT NULL DEFAULT 'draft',
  issued_at TIMESTAMPTZ,
  due_at TIMESTAMPTZ,
  paid_at TIMESTAMPTZ,
  payment_reference TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_invoices_company ON public.invoices (company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_invoices_status ON public.invoices (status, due_at);

CREATE TRIGGER invoices_updated_at
  BEFORE UPDATE ON public.invoices
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Manual subscription billing payments (not COD payments table)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.subscription_billing_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  invoice_id UUID REFERENCES public.invoices (id) ON DELETE SET NULL,
  amount_cents INT NOT NULL,
  currency TEXT NOT NULL DEFAULT 'LRD',
  payment_method public.billing_payment_method NOT NULL,
  reference TEXT,
  paid_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  billing_period_start TIMESTAMPTZ,
  billing_period_end TIMESTAMPTZ,
  recorded_by UUID NOT NULL REFERENCES auth.users (id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_subscription_billing_payments_company
  ON public.subscription_billing_payments (company_id, paid_at DESC);

-- ---------------------------------------------------------------------------
-- Immutable audit log
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_user_id UUID REFERENCES auth.users (id) ON DELETE SET NULL,
  company_id UUID REFERENCES public.companies (id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id UUID,
  metadata JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_company ON public.audit_logs (company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created ON public.audit_logs (created_at DESC);
