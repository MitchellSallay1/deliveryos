-- Company/Tenant Production Readiness Audit, Phase 1 (item 1): SMS allowance
-- provisioning. companies.sms_credits has always defaulted to 0 and nothing
-- ever funded it from the plan's monthly_sms_allowance — every company's
-- operational SMS silently fails (queue_outbound_sms returns false, no
-- exception) until a super admin manually calls admin_add_sms_credits.
--
-- Design: split the single sms_credits balance into two auditable buckets so
-- "no rollover for plan-included allowance" and "purchased/admin-added
-- credits never disappear" can both hold without conflating the two:
--
--   companies.sms_credits_included  — current period's plan allowance.
--                                      Forfeited (not carried forward) the
--                                      moment a new company_subscriptions
--                                      row is provisioned.
--   companies.sms_credits_purchased — admin_add_sms_credits top-ups. Never
--                                      touched by provisioning, never expires.
--   companies.sms_credits           — becomes a GENERATED column
--                                      (included + purchased). Every existing
--                                      read site (RPCs and frontend
--                                      `.select()`s) keeps working unchanged;
--                                      only the two write paths
--                                      (queue_outbound_sms, admin_add_sms_credits)
--                                      needed updating.
--
-- Idempotency: provisioning is keyed on company_subscriptions.id via the new
-- sms_allowance_grants table (UNIQUE). admin_set_company_subscription always
-- inserts a brand-new company_subscriptions row (even for a same-plan
-- "renewal" — that is the only renewal mechanism this schema has today; see
-- the report), and ensure_initial_company_subscription inserts exactly one
-- row per company's trial. Provisioning fires once per such row, reads the
-- row's plan_id's CURRENT monthly_sms_allowance from public.subscriptions
-- (never hardcoded), and is a guaranteed no-op if called again for the same
-- row — this is what makes "running provisioning twice" and "changing plans"
-- both safe against double-crediting.
--
-- Auth OTP is untouched by this migration: supabase/functions/auth-sms-hook
-- never references companies/sms_credits/sms_credit_ledger/queue_outbound_sms
-- at all (verified by inspection) — it is a Supabase Auth hook keyed on a
-- phone number, not a company. That separation is architectural, not
-- something this migration needs to enforce.

-- ---------------------------------------------------------------------------
-- Schema: split sms_credits into included (no rollover) + purchased (persists)
-- ---------------------------------------------------------------------------
ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS sms_credits_included INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS sms_credits_purchased INT NOT NULL DEFAULT 0;

-- Preserve every existing balance. Nothing but admin_add_sms_credits has ever
-- written to sms_credits, so any existing nonzero balance is, by definition,
-- prior manual top-ups — it belongs entirely in the "purchased" bucket.
UPDATE public.companies SET sms_credits_purchased = sms_credits;

ALTER TABLE public.companies DROP COLUMN sms_credits;

ALTER TABLE public.companies
  ADD COLUMN sms_credits INT GENERATED ALWAYS AS (sms_credits_included + sms_credits_purchased) STORED;

ALTER TABLE public.companies
  ADD CONSTRAINT companies_sms_credits_included_nonneg CHECK (sms_credits_included >= 0),
  ADD CONSTRAINT companies_sms_credits_purchased_nonneg CHECK (sms_credits_purchased >= 0);

-- Ledger provenance: which bucket a given delta applied to. Nullable —
-- entries recorded before this migration predate the bucket split and are
-- left NULL rather than guessed at.
ALTER TABLE public.sms_credit_ledger
  ADD COLUMN IF NOT EXISTS bucket TEXT;

DO $$ BEGIN
  ALTER TABLE public.sms_credit_ledger
    ADD CONSTRAINT sms_credit_ledger_bucket_check CHECK (bucket IS NULL OR bucket IN ('included', 'purchased'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Idempotency ledger for allowance grants: one row per company_subscriptions
-- lifecycle event that has actually been provisioned.
CREATE TABLE IF NOT EXISTS public.sms_allowance_grants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_subscription_id UUID NOT NULL UNIQUE REFERENCES public.company_subscriptions (id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  plan_id UUID NOT NULL REFERENCES public.subscriptions (id),
  amount INT NOT NULL,
  granted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sms_allowance_grants_company
  ON public.sms_allowance_grants (company_id, granted_at DESC);

ALTER TABLE public.sms_allowance_grants ENABLE ROW LEVEL SECURITY;

CREATE POLICY sms_allowance_grants_select ON public.sms_allowance_grants
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR company_id IN (SELECT public.user_company_ids())
  );

-- ---------------------------------------------------------------------------
-- Provisioning: grants the current plan's monthly_sms_allowance to a
-- company, once, for a given company_subscriptions row. Internal-only —
-- never called directly from the client, only from the subscription
-- lifecycle RPCs below.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.provision_company_sms_allowance(p_company_subscription_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cs public.company_subscriptions;
  v_plan public.subscriptions;
  v_old_included INT;
  v_balance INT;
BEGIN
  SELECT * INTO v_cs FROM public.company_subscriptions WHERE id = p_company_subscription_id;
  IF v_cs.id IS NULL THEN
    RAISE EXCEPTION 'company_subscription_not_found';
  END IF;

  -- Idempotent: a company_subscriptions row is provisioned at most once,
  -- regardless of how many times this is called for the same row.
  IF EXISTS (
    SELECT 1 FROM public.sms_allowance_grants WHERE company_subscription_id = p_company_subscription_id
  ) THEN
    RETURN false;
  END IF;

  SELECT * INTO v_plan FROM public.subscriptions WHERE id = v_cs.plan_id;
  IF v_plan.id IS NULL THEN
    RAISE EXCEPTION 'plan_not_found';
  END IF;

  SELECT sms_credits_included INTO v_old_included
  FROM public.companies WHERE id = v_cs.company_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'company_not_found';
  END IF;

  -- No rollover: forfeit whatever is left of the prior period's included
  -- allowance before granting the new one. Purchased credits are a
  -- completely separate column and are never touched here.
  IF v_old_included > 0 THEN
    UPDATE public.companies SET sms_credits_included = 0 WHERE id = v_cs.company_id;
    INSERT INTO public.sms_credit_ledger (company_id, delta, balance_after, reason, reference_id, bucket)
    SELECT v_cs.company_id, -v_old_included, sms_credits, 'included_allowance_expired', p_company_subscription_id, 'included'
    FROM public.companies WHERE id = v_cs.company_id;
  END IF;

  UPDATE public.companies
  SET sms_credits_included = v_plan.monthly_sms_allowance
  WHERE id = v_cs.company_id
  RETURNING sms_credits INTO v_balance;

  INSERT INTO public.sms_credit_ledger (company_id, delta, balance_after, reason, reference_id, bucket)
  VALUES (v_cs.company_id, v_plan.monthly_sms_allowance, v_balance, 'plan_allowance_provisioned', p_company_subscription_id, 'included');

  INSERT INTO public.sms_allowance_grants (company_subscription_id, company_id, plan_id, amount)
  VALUES (p_company_subscription_id, v_cs.company_id, v_plan.id, v_plan.monthly_sms_allowance);

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.provision_company_sms_allowance(UUID) FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- Wire provisioning into the two places a company_subscriptions row is
-- created. Both are CREATE OR REPLACE of the current (already-patched) body
-- plus one PERFORM — no other behavior changes.
-- ---------------------------------------------------------------------------

-- Trial creation (unchanged except the trailing PERFORM before RETURN).
CREATE OR REPLACE FUNCTION public.ensure_initial_company_subscription(p_company_id UUID)
RETURNS public.company_subscriptions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing public.company_subscriptions;
  v_row public.company_subscriptions;
  v_plan_id UUID;
  v_starts TIMESTAMPTZ := now();
  v_trial_end TIMESTAMPTZ;
BEGIN
  IF p_company_id IS NULL THEN
    RAISE EXCEPTION 'invalid company';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.companies c WHERE c.id = p_company_id) THEN
    RAISE EXCEPTION 'company_not_found';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('company_sub:' || p_company_id::text));

  PERFORM public.expire_elapsed_company_trials(p_company_id);

  v_existing := public.get_active_company_subscription(p_company_id);
  IF v_existing.id IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.company_subscriptions cs WHERE cs.company_id = p_company_id
  ) THEN
    SELECT cs.* INTO v_row
    FROM public.company_subscriptions cs
    WHERE cs.company_id = p_company_id
    ORDER BY cs.created_at DESC
    LIMIT 1;
    RETURN v_row;
  END IF;

  SELECT COALESCE(
    (SELECT c.subscription_id FROM public.companies c WHERE c.id = p_company_id),
    (SELECT s.id FROM public.subscriptions s WHERE s.slug = 'starter' AND s.is_active = true LIMIT 1)
  ) INTO v_plan_id;

  IF v_plan_id IS NULL THEN
    SELECT id INTO v_plan_id FROM public.subscriptions WHERE slug = 'starter' LIMIT 1;
  END IF;

  IF v_plan_id IS NULL THEN
    RAISE EXCEPTION 'starter plan not configured';
  END IF;

  v_trial_end := v_starts + INTERVAL '7 days';

  INSERT INTO public.company_subscriptions (
    company_id,
    plan_id,
    status,
    starts_at,
    current_period_start,
    current_period_end,
    trial_ends_at
  ) VALUES (
    p_company_id,
    v_plan_id,
    'trialing'::public.company_subscription_status,
    v_starts,
    v_starts,
    v_trial_end,
    v_trial_end
  )
  RETURNING * INTO v_row;

  UPDATE public.companies
  SET subscription_id = v_plan_id, updated_at = now()
  WHERE id = p_company_id;

  PERFORM public.provision_company_sms_allowance(v_row.id);

  RETURN v_row;
END;
$$;

-- Admin-operated subscription create/change/renew (unchanged except the
-- trailing PERFORM before RETURN). This is the only place a paid plan is
-- ever assigned, and — since it always inserts a fresh row, even for a
-- same-plan call — it is also this schema's only renewal mechanism today.
CREATE OR REPLACE FUNCTION public.admin_set_company_subscription(
  p_company_id UUID,
  p_plan_id UUID,
  p_status public.company_subscription_status,
  p_period_end TIMESTAMPTZ DEFAULT NULL
)
RETURNS public.company_subscriptions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.company_subscriptions;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE public.company_subscriptions
  SET status = 'cancelled', cancelled_at = now(), updated_at = now()
  WHERE company_id = p_company_id
    AND status IN ('trialing', 'active', 'past_due');

  INSERT INTO public.company_subscriptions (
    company_id, plan_id, status,
    current_period_start, current_period_end
  ) VALUES (
    p_company_id,
    p_plan_id,
    p_status,
    date_trunc('month', now() AT TIME ZONE 'Africa/Monrovia'),
    COALESCE(p_period_end, (date_trunc('month', now() AT TIME ZONE 'Africa/Monrovia') + INTERVAL '1 month'))
  )
  RETURNING * INTO v_row;

  UPDATE public.companies SET subscription_id = p_plan_id WHERE id = p_company_id;

  PERFORM public.provision_company_sms_allowance(v_row.id);

  PERFORM public.log_audit_event(
    p_company_id, 'subscription_changed', 'company_subscriptions', v_row.id, to_jsonb(v_row)
  );
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_set_company_subscription TO authenticated;

-- ---------------------------------------------------------------------------
-- Rewire the two existing writers of sms_credits onto the split columns.
-- sms_credits is now GENERATED and cannot be written directly.
-- ---------------------------------------------------------------------------

-- Consumption: draw from the expiring "included" bucket first, then the
-- persistent "purchased" bucket — this maximizes how much of the
-- non-rolling-over included allowance actually gets used before it's
-- forfeited at the next provisioning event.
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
  v_included INT;
  v_purchased INT;
  v_bucket TEXT;
  v_balance INT;
BEGIN
  IF NOT public.can_use_feature(p_company_id, 'sms_notifications') THEN
    RETURN false;
  END IF;

  IF p_phone IS NULL OR p_phone = '' OR p_body IS NULL OR p_body = '' THEN
    RETURN false;
  END IF;

  SELECT sms_credits_included, sms_credits_purchased INTO v_included, v_purchased
  FROM public.companies WHERE id = p_company_id FOR UPDATE;
  IF NOT FOUND OR (v_included + v_purchased) < 1 THEN
    RETURN false;
  END IF;

  IF v_included > 0 THEN
    v_bucket := 'included';
    UPDATE public.companies SET sms_credits_included = sms_credits_included - 1
    WHERE id = p_company_id
    RETURNING sms_credits INTO v_balance;
  ELSE
    v_bucket := 'purchased';
    UPDATE public.companies SET sms_credits_purchased = sms_credits_purchased - 1
    WHERE id = p_company_id
    RETURNING sms_credits INTO v_balance;
  END IF;

  INSERT INTO public.sms_credit_ledger (company_id, delta, balance_after, reason, reference_id, bucket)
  VALUES (p_company_id, -1, v_balance, 'outbound_sms', p_delivery_id, v_bucket);

  INSERT INTO public.sms_logs (company_id, direction, phone, body, credits_used, delivery_id)
  VALUES (p_company_id, 'outbound', p_phone, p_body, 1, p_delivery_id);

  INSERT INTO public.sms_outbox (company_id, phone, body, delivery_id, provider, status)
  VALUES (
    p_company_id, p_phone, p_body, p_delivery_id,
    COALESCE(current_setting('app.sms_provider', true), 'stub'),
    'pending'
  );

  INSERT INTO public.notification_logs (company_id, channel, recipient, body, status)
  VALUES (p_company_id, 'sms', p_phone, p_body, 'queued');

  RETURN true;
END;
$$;

-- Manual super-admin top-up: always purchased, never touches the plan's
-- included allowance — this is exactly what keeps provisioning from ever
-- overwriting a manual top-up, in either direction.
CREATE OR REPLACE FUNCTION public.admin_add_sms_credits(
  p_company_id UUID,
  p_amount INT,
  p_reason TEXT DEFAULT 'admin_top_up'
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_balance INT;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'amount must be positive';
  END IF;

  UPDATE public.companies SET sms_credits_purchased = sms_credits_purchased + p_amount
  WHERE id = p_company_id
  RETURNING sms_credits INTO v_balance;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'company not found';
  END IF;

  INSERT INTO public.sms_credit_ledger (company_id, delta, balance_after, reason, bucket)
  VALUES (p_company_id, p_amount, v_balance, p_reason, 'purchased');

  PERFORM public.log_audit_event(
    p_company_id, 'sms_credits_added', 'companies', p_company_id,
    jsonb_build_object('amount', p_amount, 'balance', v_balance, 'reason', p_reason)
  );

  RETURN v_balance;
END;
$$;

-- ---------------------------------------------------------------------------
-- Backfill: every existing company already has a company_subscriptions row
-- (from earlier migrations/backfills) that has never been through
-- provisioning. Grant it now so today's companies aren't left permanently
-- stuck at whatever sms_credits_purchased they happened to have.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_cs_id UUID;
BEGIN
  FOR v_cs_id IN
    SELECT cs.id
    FROM public.company_subscriptions cs
    WHERE cs.status IN ('trialing', 'active', 'past_due')
    ORDER BY cs.created_at
  LOOP
    PERFORM public.provision_company_sms_allowance(v_cs_id);
  END LOOP;
END;
$$;
