-- DeliveryOS · WhatsApp Phase A — Gupshup transport, webhook, outbox,
-- templates, delivery receipts, and routing foundation.
--
-- Reuses rather than duplicates: normalize_phone_lr / phone_matches_msisdn
-- (phone utilities), get_public_delivery_tracking (TRACK command — same
-- rate-limited public tracking RPC the /track page uses, not a new privileged
-- lookup), the queue/dispatch/outbox SHAPE already established by
-- sms_outbox + sms-dispatch (mirrored, not shared — WhatsApp has its own
-- provider, template, and delivery-receipt model that doesn't fit the SMS
-- table), and is_super_admin()/user_company_ids() for RLS.
--
-- Does NOT touch: Auth OTP (auth-sms-hook, Send SMS Hook), sms_outbox,
-- sms-dispatch, WinAggregator, sms_credit_ledger/sms_credits_*, MoMo.
--
-- Rollout safety: every new table starts empty, every template-registry row
-- starts 'draft' with gupshup_template_id = NULL, and every company starts
-- with whatsapp_notifications_enabled = false. resolve_notification_channel
-- (below) can only ever return 'whatsapp' when all three of those are
-- flipped on for a given company + template — so this migration is a no-op
-- for existing behavior until a human explicitly turns each piece on.

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE public.whatsapp_message_kind AS ENUM ('template', 'session');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  -- 'submitted' = Gupshup's HTTP response accepted the send request. This is
  -- NOT delivery — see apply_whatsapp_status_event below. 'sent'/'delivered'/
  -- 'read'/'failed' only ever come from a webhook message-event.
  CREATE TYPE public.whatsapp_message_status AS ENUM (
    'pending', 'submitted', 'sent', 'delivered', 'read', 'failed', 'dead'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ---------------------------------------------------------------------------
-- Template registry — semantic DeliveryOS event key -> Gupshup template.
-- Seeded 'draft' with no gupshup_template_id: no template is approved yet,
-- so this table is inert (see resolve_notification_channel) until a human
-- fills in real approved template ids after submitting them to Gupshup/Meta.
-- See docs/WHATSAPP_TEMPLATE_PLAN.md for the proposed wording per key.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.whatsapp_template_registry (
  semantic_key TEXT PRIMARY KEY,
  gupshup_template_name TEXT NOT NULL,
  gupshup_template_id TEXT,
  category TEXT NOT NULL DEFAULT 'UTILITY',
  language TEXT NOT NULL DEFAULT 'en',
  status TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'pending_submission', 'submitted', 'approved', 'rejected', 'disabled')),
  is_sandbox BOOLEAN NOT NULL DEFAULT false,
  body_preview TEXT NOT NULL,
  param_count INT NOT NULL DEFAULT 0,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.trg_whatsapp_template_registry_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS whatsapp_template_registry_updated_at ON public.whatsapp_template_registry;
CREATE TRIGGER whatsapp_template_registry_updated_at
  BEFORE UPDATE ON public.whatsapp_template_registry
  FOR EACH ROW EXECUTE FUNCTION public.trg_whatsapp_template_registry_updated_at();

INSERT INTO public.whatsapp_template_registry (semantic_key, gupshup_template_name, body_preview, param_count, category)
VALUES
  ('commerce_order_created_vendor', 'deliveryos_order_created_vendor', 'New DeliveryOS order #{{1}} from {{2}}. Total LRD {{3}}. Open your vendor dashboard to accept.', 3, 'UTILITY'),
  ('commerce_order_accepted_customer', 'deliveryos_order_accepted_customer', 'Your DeliveryOS order #{{1}} has been accepted and is being prepared.', 1, 'UTILITY'),
  ('commerce_order_rejected_customer', 'deliveryos_order_rejected_customer', 'Your DeliveryOS order #{{1}} could not be accepted. {{2}}', 2, 'UTILITY'),
  ('commerce_order_ready_customer', 'deliveryos_order_ready_customer', 'Your DeliveryOS order #{{1}} is ready and waiting for a carrier.', 1, 'UTILITY'),
  ('carrier_selected', 'deliveryos_carrier_selected', 'A carrier has been selected for order #{{1}}.', 1, 'UTILITY'),
  ('carrier_accepted_customer', 'deliveryos_carrier_accepted_customer', 'A carrier has accepted your DeliveryOS order #{{1}}. You will be notified when it is picked up.', 1, 'UTILITY'),
  ('rider_assigned_customer', 'deliveryos_rider_assigned_customer', 'A rider has been assigned to your delivery {{1}}.', 1, 'UTILITY'),
  ('delivery_picked_up_customer', 'deliveryos_delivery_picked_up', 'Your package for {{1}} has been picked up and is on the way.', 1, 'UTILITY'),
  ('delivery_in_transit_customer', 'deliveryos_delivery_in_transit', 'Your package for {{1}} is in transit. Track: {{2}}', 2, 'UTILITY'),
  ('delivery_delivered_customer', 'deliveryos_delivery_delivered', 'Your package for {{1}} was delivered. Thank you for using DeliveryOS!', 1, 'UTILITY'),
  ('delivery_failed_customer', 'deliveryos_delivery_failed', 'We were unable to deliver your package for {{1}}. {{2}}', 2, 'UTILITY')
ON CONFLICT (semantic_key) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Outbound outbox — mirrors sms_outbox's role (durable queue, polled by an
-- Edge Function), not its schema: WhatsApp messages carry a template/session
-- distinction and a richer delivery-receipt lifecycle SMS doesn't have.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.whatsapp_outbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID REFERENCES public.companies (id) ON DELETE CASCADE,
  recipient_phone TEXT NOT NULL,
  message_kind public.whatsapp_message_kind NOT NULL,
  -- Template sends store the semantic key, not a denormalized template id —
  -- the real Gupshup template id is resolved at SEND time (whatsapp-dispatch
  -- joins whatsapp_template_registry), so a template approved after a
  -- message was queued but before it's dispatched still sends correctly.
  semantic_event_key TEXT REFERENCES public.whatsapp_template_registry (semantic_key),
  template_params JSONB NOT NULL DEFAULT '[]'::JSONB,
  body_text TEXT,
  status public.whatsapp_message_status NOT NULL DEFAULT 'pending',
  attempt_count INT NOT NULL DEFAULT 0,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_error TEXT,
  provider TEXT NOT NULL DEFAULT 'gupshup',
  provider_message_id TEXT,
  idempotency_key TEXT,
  delivery_id UUID REFERENCES public.deliveries (id) ON DELETE SET NULL,
  commerce_order_id UUID REFERENCES public.commerce_orders (id) ON DELETE SET NULL,
  submitted_at TIMESTAMPTZ,
  sent_at TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  read_at TIMESTAMPTZ,
  failed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT whatsapp_outbox_kind_shape CHECK (
    (message_kind = 'template' AND semantic_event_key IS NOT NULL)
    OR (message_kind = 'session' AND body_text IS NOT NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_whatsapp_outbox_idempotency
  ON public.whatsapp_outbox (idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_whatsapp_outbox_pending
  ON public.whatsapp_outbox (status, next_attempt_at) WHERE status IN ('pending', 'failed');
CREATE INDEX IF NOT EXISTS idx_whatsapp_outbox_company
  ON public.whatsapp_outbox (company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_whatsapp_outbox_provider_message
  ON public.whatsapp_outbox (provider_message_id) WHERE provider_message_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Inbound messages — durable storage, processed asynchronously by the
-- router (webhook persists first, acknowledges, then the router runs).
-- Media: provider reference only (id/mime/caption), never the binary.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.whatsapp_inbound_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_message_id TEXT NOT NULL,
  app_name TEXT,
  sender_phone TEXT NOT NULL,
  sender_phone_normalized TEXT NOT NULL,
  message_type TEXT NOT NULL,
  message_text TEXT,
  media_reference JSONB,
  company_id UUID REFERENCES public.companies (id) ON DELETE SET NULL,
  resolved_identity_type TEXT,
  resolved_identity_id UUID,
  resolved_delivery_id UUID REFERENCES public.deliveries (id) ON DELETE SET NULL,
  resolved_commerce_order_id UUID REFERENCES public.commerce_orders (id) ON DELETE SET NULL,
  processing_status TEXT NOT NULL DEFAULT 'pending'
    CHECK (processing_status IN ('pending', 'processed', 'error', 'ignored')),
  processing_error TEXT,
  router_reply_sent BOOLEAN NOT NULL DEFAULT false,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_whatsapp_inbound_provider_message
  ON public.whatsapp_inbound_messages (provider_message_id);
CREATE INDEX IF NOT EXISTS idx_whatsapp_inbound_sender
  ON public.whatsapp_inbound_messages (sender_phone_normalized, created_at DESC);

-- ---------------------------------------------------------------------------
-- Opt-in/opt-out preferences — GLOBAL by phone, not per-company. Customers
-- message ONE shared DeliveryOS WhatsApp number regardless of which tenant's
-- order/delivery they're messaging about; "STOP" means stop everything from
-- that number, not "stop from company X" (a distinction that would be
-- invisible to the person texting STOP). SMS opt-in/out is intentionally
-- separate (different channel, different table, sms_outbox is unaffected).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.whatsapp_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone TEXT NOT NULL,
  phone_normalized TEXT NOT NULL,
  opted_in_at TIMESTAMPTZ,
  opted_out_at TIMESTAMPTZ,
  opt_in_source TEXT,
  opt_out_source TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_whatsapp_preferences_phone
  ON public.whatsapp_preferences (phone_normalized);

-- ---------------------------------------------------------------------------
-- Tenant settings (data model only — see report section 18 for why no
-- company-facing UI toggle ships in Phase A: with every template still
-- 'draft', flipping this on would have no visible effect yet, which is
-- exactly the "confusing configuration" the spec says not to add).
-- ---------------------------------------------------------------------------
ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS whatsapp_notifications_enabled BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS whatsapp_sms_fallback_enabled BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS preferred_operational_channel TEXT NOT NULL DEFAULT 'sms'
    CHECK (preferred_operational_channel IN ('sms', 'whatsapp'));

-- ---------------------------------------------------------------------------
-- RLS — every new table: enabled, SELECT-only policy, no INSERT/UPDATE/
-- DELETE policy for anon/authenticated. This matters concretely here: the
-- platform bootstrap grants SELECT/INSERT/UPDATE/DELETE on every table to
-- anon+authenticated (see 20260308190500_codify_anon_authenticated_table_
-- grants.sql; RLS is the ONLY access control, not grants) and ALTER DEFAULT
-- PRIVILEGES makes that automatic for new tables too — so without RLS here,
-- any authenticated user could INSERT/UPDATE whatsapp_outbox directly and
-- either spam arbitrary WhatsApp sends or forge delivery/read receipts. All
-- real writes go through the SECURITY DEFINER functions below, executed by
-- service_role (which bypasses RLS) or, where noted, authenticated callers
-- who are re-checked inside the function body.
-- ---------------------------------------------------------------------------
ALTER TABLE public.whatsapp_template_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.whatsapp_outbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.whatsapp_inbound_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.whatsapp_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY whatsapp_template_registry_super_admin_select ON public.whatsapp_template_registry
  FOR SELECT TO authenticated
  USING (public.is_super_admin());

CREATE POLICY whatsapp_outbox_tenant_select ON public.whatsapp_outbox
  FOR SELECT TO authenticated
  USING (public.is_super_admin() OR company_id IN (SELECT public.user_company_ids()));

CREATE POLICY whatsapp_inbound_messages_tenant_select ON public.whatsapp_inbound_messages
  FOR SELECT TO authenticated
  USING (public.is_super_admin() OR company_id IN (SELECT public.user_company_ids()));

-- Not company-scoped (see table comment above) — a phone number's opt-out
-- status isn't owned by any one tenant, so only Super Admin can read it.
CREATE POLICY whatsapp_preferences_super_admin_select ON public.whatsapp_preferences
  FOR SELECT TO authenticated
  USING (public.is_super_admin());

-- ---------------------------------------------------------------------------
-- Phone / opt-in helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_whatsapp_opted_out(p_phone TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (
      SELECT opted_out_at IS NOT NULL AND (opted_in_at IS NULL OR opted_in_at < opted_out_at)
      FROM public.whatsapp_preferences
      WHERE phone_normalized = public.normalize_phone_lr(p_phone)
    ),
    false
  );
$$;

REVOKE ALL ON FUNCTION public.is_whatsapp_opted_out FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_whatsapp_opted_out TO service_role, authenticated;

CREATE OR REPLACE FUNCTION public.apply_whatsapp_opt_command(
  p_phone TEXT,
  p_command TEXT
)
RETURNS public.whatsapp_preferences
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_norm TEXT := public.normalize_phone_lr(p_phone);
  v_row public.whatsapp_preferences;
BEGIN
  IF v_norm = '' THEN
    RAISE EXCEPTION 'invalid phone';
  END IF;

  INSERT INTO public.whatsapp_preferences (phone, phone_normalized)
  VALUES (p_phone, v_norm)
  ON CONFLICT (phone_normalized) DO NOTHING;

  IF upper(p_command) = 'STOP' THEN
    UPDATE public.whatsapp_preferences SET
      opted_out_at = now(), opt_out_source = 'inbound_stop', updated_at = now()
    WHERE phone_normalized = v_norm
    RETURNING * INTO v_row;
  ELSIF upper(p_command) = 'START' THEN
    UPDATE public.whatsapp_preferences SET
      opted_in_at = now(), opted_out_at = NULL, opt_in_source = 'inbound_start', updated_at = now()
    WHERE phone_normalized = v_norm
    RETURNING * INTO v_row;
  ELSE
    RAISE EXCEPTION 'unknown opt command %', p_command;
  END IF;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.apply_whatsapp_opt_command FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.apply_whatsapp_opt_command TO service_role;

-- ---------------------------------------------------------------------------
-- Outbound queueing
-- ---------------------------------------------------------------------------

-- Low-level insert, shared by the template and session helpers below.
-- Idempotent via a partial unique index on idempotency_key: a retried
-- Edge Function invocation or a retried RPC call with the same key inserts
-- nothing the second time, so no duplicate user-visible WhatsApp message.
CREATE OR REPLACE FUNCTION public.queue_outbound_whatsapp(
  p_company_id UUID,
  p_phone TEXT,
  p_semantic_event_key TEXT,
  p_template_params JSONB DEFAULT '[]'::JSONB,
  p_idempotency_key TEXT DEFAULT NULL,
  p_delivery_id UUID DEFAULT NULL,
  p_commerce_order_id UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inserted UUID;
BEGIN
  IF p_phone IS NULL OR p_phone = '' THEN RETURN false; END IF;
  IF public.is_whatsapp_opted_out(p_phone) THEN RETURN false; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.whatsapp_template_registry WHERE semantic_key = p_semantic_event_key) THEN
    RETURN false;
  END IF;

  INSERT INTO public.whatsapp_outbox (
    company_id, recipient_phone, message_kind, semantic_event_key,
    template_params, status, idempotency_key, delivery_id, commerce_order_id
  ) VALUES (
    p_company_id, p_phone, 'template', p_semantic_event_key,
    COALESCE(p_template_params, '[]'::JSONB), 'pending',
    p_idempotency_key, p_delivery_id, p_commerce_order_id
  )
  ON CONFLICT (idempotency_key) WHERE idempotency_key IS NOT NULL DO NOTHING
  RETURNING id INTO v_inserted;

  RETURN v_inserted IS NOT NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.queue_outbound_whatsapp FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.queue_outbound_whatsapp TO service_role;

-- Session (free-form) replies — direct responses to an inbound message
-- within the 24h customer-service window. Deliberately NOT gated by
-- is_whatsapp_opted_out: opt-out governs business-initiated template
-- notifications, not a direct reply to a message the user just sent (e.g.
-- their own STOP confirmation, or a HELP/TRACK reply).
CREATE OR REPLACE FUNCTION public.queue_outbound_whatsapp_session_reply(
  p_company_id UUID,
  p_phone TEXT,
  p_body_text TEXT,
  p_idempotency_key TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inserted UUID;
BEGIN
  IF p_phone IS NULL OR p_phone = '' OR p_body_text IS NULL OR p_body_text = '' THEN
    RETURN false;
  END IF;

  INSERT INTO public.whatsapp_outbox (
    company_id, recipient_phone, message_kind, body_text, status, idempotency_key
  ) VALUES (
    p_company_id, p_phone, 'session', p_body_text, 'pending', p_idempotency_key
  )
  ON CONFLICT (idempotency_key) WHERE idempotency_key IS NOT NULL DO NOTHING
  RETURNING id INTO v_inserted;

  RETURN v_inserted IS NOT NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.queue_outbound_whatsapp_session_reply FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.queue_outbound_whatsapp_session_reply TO service_role;

-- ---------------------------------------------------------------------------
-- Channel policy — the ONE place that decides WhatsApp vs SMS. WhatsApp is
-- only chosen when the company has explicitly enabled it, the phone hasn't
-- opted out, AND the template is 'approved' with a real gupshup_template_id
-- — since every seeded template starts 'draft'/NULL, this returns 'sms' for
-- every company today, unconditionally. Turning WhatsApp on for real is a
-- data change (approve a template, set its id, flip the company flag), not
-- a code change.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resolve_notification_channel(
  p_company_id UUID,
  p_phone TEXT,
  p_semantic_event_key TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company public.companies;
  v_template public.whatsapp_template_registry;
BEGIN
  SELECT * INTO v_company FROM public.companies WHERE id = p_company_id;
  IF NOT FOUND OR NOT v_company.whatsapp_notifications_enabled THEN
    RETURN 'sms';
  END IF;

  IF p_phone IS NULL OR p_phone = '' OR public.is_whatsapp_opted_out(p_phone) THEN
    RETURN 'sms';
  END IF;

  SELECT * INTO v_template FROM public.whatsapp_template_registry WHERE semantic_key = p_semantic_event_key;
  IF NOT FOUND OR v_template.status <> 'approved' OR v_template.gupshup_template_id IS NULL THEN
    RETURN 'sms';
  END IF;

  RETURN 'whatsapp';
END;
$$;

REVOKE ALL ON FUNCTION public.resolve_notification_channel FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_notification_channel TO service_role;

-- Single call site business-event notify functions use: decide channel,
-- queue exactly one message, never both. Falls back to SMS if WhatsApp
-- queueing itself failed (e.g. opted out) so the underlying business event
-- is never silently un-notified just because WhatsApp wasn't eligible.
CREATE OR REPLACE FUNCTION public.dispatch_channel_notification(
  p_company_id UUID,
  p_phone TEXT,
  p_semantic_event_key TEXT,
  p_sms_body TEXT,
  p_template_params JSONB DEFAULT '[]'::JSONB,
  p_delivery_id UUID DEFAULT NULL,
  p_commerce_order_id UUID DEFAULT NULL,
  p_idempotency_key TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_channel TEXT;
BEGIN
  v_channel := public.resolve_notification_channel(p_company_id, p_phone, p_semantic_event_key);

  IF v_channel = 'whatsapp' THEN
    IF public.queue_outbound_whatsapp(
      p_company_id, p_phone, p_semantic_event_key, p_template_params,
      p_idempotency_key, p_delivery_id, p_commerce_order_id
    ) THEN
      RETURN 'whatsapp';
    END IF;
  END IF;

  IF public.queue_outbound_sms(p_company_id, p_phone, p_sms_body, p_delivery_id) THEN
    RETURN 'sms';
  END IF;

  RETURN 'none';
END;
$$;

REVOKE ALL ON FUNCTION public.dispatch_channel_notification FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dispatch_channel_notification TO service_role, authenticated;

-- ---------------------------------------------------------------------------
-- Delivery-receipt mapping — forward-only. A late/duplicate 'sent' webhook
-- event must never downgrade an already-observed 'delivered'/'read' state,
-- and re-delivering the SAME event (webhook replay) is a safe no-op, not a
-- duplicate side effect, because this only ever SETs columns, never appends.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.apply_whatsapp_status_event(
  p_provider_message_id TEXT,
  p_status TEXT,
  p_error_reason TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.whatsapp_outbox;
  v_rank JSONB := '{"pending":0,"submitted":1,"sent":2,"delivered":3,"read":4,"failed":5,"dead":5}'::JSONB;
  v_new_status public.whatsapp_message_status;
BEGIN
  IF p_provider_message_id IS NULL OR p_provider_message_id = '' THEN RETURN false; END IF;

  v_new_status := CASE lower(COALESCE(p_status, ''))
    WHEN 'enqueued' THEN 'submitted'::public.whatsapp_message_status
    WHEN 'sent' THEN 'sent'::public.whatsapp_message_status
    WHEN 'delivered' THEN 'delivered'::public.whatsapp_message_status
    WHEN 'read' THEN 'read'::public.whatsapp_message_status
    WHEN 'failed' THEN 'failed'::public.whatsapp_message_status
    ELSE NULL
  END;
  IF v_new_status IS NULL THEN RETURN false; END IF;

  SELECT * INTO v_row FROM public.whatsapp_outbox
  WHERE provider_message_id = p_provider_message_id
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN RETURN false; END IF;

  IF COALESCE((v_rank -> v_row.status::TEXT)::INT, 0) > COALESCE((v_rank -> v_new_status::TEXT)::INT, 0) THEN
    RETURN true;
  END IF;

  UPDATE public.whatsapp_outbox SET
    status = v_new_status,
    submitted_at = CASE WHEN v_new_status = 'submitted' THEN COALESCE(submitted_at, now()) ELSE submitted_at END,
    sent_at = CASE WHEN v_new_status = 'sent' THEN COALESCE(sent_at, now()) ELSE sent_at END,
    delivered_at = CASE WHEN v_new_status = 'delivered' THEN COALESCE(delivered_at, now()) ELSE delivered_at END,
    read_at = CASE WHEN v_new_status = 'read' THEN COALESCE(read_at, now()) ELSE read_at END,
    failed_at = CASE WHEN v_new_status = 'failed' THEN COALESCE(failed_at, now()) ELSE failed_at END,
    last_error = CASE WHEN v_new_status = 'failed' THEN p_error_reason ELSE last_error END
  WHERE id = v_row.id;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.apply_whatsapp_status_event FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.apply_whatsapp_status_event TO service_role;

-- ---------------------------------------------------------------------------
-- Inbound message recording — dedup by provider_message_id so a webhook
-- replay never processes (or double-replies to) the same inbound message.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_whatsapp_inbound_message(
  p_provider_message_id TEXT,
  p_app_name TEXT,
  p_sender_phone TEXT,
  p_message_type TEXT,
  p_message_text TEXT,
  p_media_reference JSONB DEFAULT NULL
)
RETURNS TABLE (id UUID, is_new BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO public.whatsapp_inbound_messages (
    provider_message_id, app_name, sender_phone, sender_phone_normalized,
    message_type, message_text, media_reference
  ) VALUES (
    p_provider_message_id, p_app_name, p_sender_phone, public.normalize_phone_lr(p_sender_phone),
    p_message_type, left(COALESCE(p_message_text, ''), 2000), p_media_reference
  )
  ON CONFLICT (provider_message_id) DO NOTHING
  RETURNING whatsapp_inbound_messages.id INTO v_id;

  IF v_id IS NOT NULL THEN
    RETURN QUERY SELECT v_id, true;
    RETURN;
  END IF;

  SELECT wim.id INTO v_id FROM public.whatsapp_inbound_messages wim
  WHERE wim.provider_message_id = p_provider_message_id;
  RETURN QUERY SELECT v_id, false;
END;
$$;

REVOKE ALL ON FUNCTION public.record_whatsapp_inbound_message FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_whatsapp_inbound_message TO service_role;

CREATE OR REPLACE FUNCTION public.mark_whatsapp_inbound_processed(
  p_id UUID,
  p_status TEXT,
  p_error TEXT DEFAULT NULL,
  p_reply_sent BOOLEAN DEFAULT false
)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.whatsapp_inbound_messages
  SET processing_status = p_status, processing_error = p_error, router_reply_sent = p_reply_sent
  WHERE id = p_id;
$$;

REVOKE ALL ON FUNCTION public.mark_whatsapp_inbound_processed FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_whatsapp_inbound_processed TO service_role;

-- ---------------------------------------------------------------------------
-- Public order-status lookup for the ORDER command — same security shape as
-- get_public_delivery_tracking: the requester must prove they know BOTH the
-- order number AND the phone number on file for it (phone_matches_msisdn),
-- so guessing an order number alone reveals nothing.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_public_commerce_order_status(
  p_order_number TEXT,
  p_requesting_phone TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.commerce_orders;
BEGIN
  IF p_order_number IS NULL OR trim(p_order_number) = '' OR p_requesting_phone IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_order FROM public.commerce_orders
  WHERE order_number = upper(trim(p_order_number));

  IF NOT FOUND THEN RETURN NULL; END IF;
  IF NOT public.phone_matches_msisdn(v_order.customer_phone, p_requesting_phone) THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object(
    'order_number', v_order.order_number,
    'fulfillment_status', v_order.fulfillment_status,
    'payment_status', v_order.payment_status,
    'created_at', v_order.created_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_public_commerce_order_status FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_commerce_order_status TO service_role;

-- ---------------------------------------------------------------------------
-- Inbound command router — deterministic, Phase A commands only (no AI).
-- STOP/START apply globally by phone (any sender: customer, vendor, rider —
-- WhatsApp opt-out is not rider-specific, unlike the SMS/USSD rider-channel
-- command set in apply_rider_channel_command, which this deliberately does
-- NOT reuse: different audience, different commands).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.whatsapp_router_handle(
  p_phone TEXT,
  p_text TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_norm TEXT := public.normalize_phone_lr(p_phone);
  v_parts TEXT[];
  v_cmd TEXT;
  v_arg TEXT;
  v_tracking JSONB;
  v_order JSONB;
BEGIN
  v_parts := regexp_split_to_array(trim(COALESCE(p_text, '')), '\s+');
  v_cmd := upper(COALESCE(v_parts[1], ''));
  v_arg := CASE WHEN array_length(v_parts, 1) >= 2 THEN v_parts[2] ELSE NULL END;

  IF v_cmd = 'STOP' THEN
    PERFORM public.apply_whatsapp_opt_command(p_phone, 'STOP');
    RETURN jsonb_build_object(
      'reply_message',
      'You will no longer receive non-essential WhatsApp messages from DeliveryOS. Reply START to resume.'
    );
  ELSIF v_cmd = 'START' THEN
    PERFORM public.apply_whatsapp_opt_command(p_phone, 'START');
    RETURN jsonb_build_object('reply_message', 'You are now opted in to WhatsApp messages from DeliveryOS.');
  ELSIF v_cmd = 'HELP' OR v_cmd = '' THEN
    RETURN jsonb_build_object(
      'reply_message',
      E'DeliveryOS WhatsApp help:\nTRACK <code> - delivery status\nORDER <code> - order status\nSTOP - opt out\nSTART - opt back in'
    );
  ELSIF v_cmd = 'TRACK' THEN
    IF v_arg IS NULL THEN
      RETURN jsonb_build_object('reply_message', 'Reply TRACK followed by your tracking code, e.g. TRACK DLV-ABC123.');
    END IF;
    BEGIN
      v_tracking := public.get_public_delivery_tracking(v_arg, 'whatsapp:' || v_norm);
    EXCEPTION WHEN OTHERS THEN
      RETURN jsonb_build_object('reply_message', 'Too many requests. Please try again in a few minutes.');
    END;
    IF v_tracking IS NULL THEN
      RETURN jsonb_build_object('reply_message', format('No delivery found for tracking code %s.', v_arg));
    END IF;
    RETURN jsonb_build_object(
      'reply_message',
      format(
        E'Tracking %s\nStatus: %s\nFrom: %s\nTo: %s',
        v_tracking ->> 'tracking_code',
        replace(COALESCE(v_tracking ->> 'status', ''), '_', ' '),
        COALESCE(v_tracking ->> 'pickup_area', 'n/a'),
        COALESCE(v_tracking ->> 'destination_area', 'n/a')
      )
    );
  ELSIF v_cmd = 'ORDER' THEN
    IF v_arg IS NULL THEN
      RETURN jsonb_build_object('reply_message', 'Reply ORDER followed by your order number, e.g. ORDER ORD-202608-00001.');
    END IF;
    v_order := public.get_public_commerce_order_status(v_arg, p_phone);
    IF v_order IS NULL THEN
      RETURN jsonb_build_object('reply_message', 'No matching order found for this phone number.');
    END IF;
    RETURN jsonb_build_object(
      'reply_message',
      format(E'Order %s\nStatus: %s', v_order ->> 'order_number', replace(COALESCE(v_order ->> 'fulfillment_status', ''), '_', ' '))
    );
  ELSE
    RETURN jsonb_build_object('reply_message', 'Sorry, I did not understand that. Reply HELP for options.');
  END IF;
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('reply_message', 'Sorry, something went wrong. Reply HELP for options.');
END;
$$;

REVOKE ALL ON FUNCTION public.whatsapp_router_handle FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.whatsapp_router_handle TO service_role;

-- ---------------------------------------------------------------------------
-- Super Admin visibility
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_get_whatsapp_summary(p_days INT DEFAULT 7)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_since TIMESTAMPTZ := now() - make_interval(days => GREATEST(LEAST(p_days, 90), 1));
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  RETURN jsonb_build_object(
    'by_status', (
      SELECT COALESCE(jsonb_object_agg(status, cnt), '{}'::JSONB)
      FROM (
        SELECT status::TEXT AS status, COUNT(*)::INT AS cnt
        FROM public.whatsapp_outbox
        WHERE created_at >= v_since
        GROUP BY status
      ) q
    ),
    'by_template', (
      SELECT COALESCE(jsonb_object_agg(COALESCE(semantic_event_key, 'session'), cnt), '{}'::JSONB)
      FROM (
        SELECT semantic_event_key, COUNT(*)::INT AS cnt
        FROM public.whatsapp_outbox
        WHERE created_at >= v_since
        GROUP BY semantic_event_key
      ) q
    ),
    'inbound_messages', (SELECT COUNT(*)::INT FROM public.whatsapp_inbound_messages WHERE created_at >= v_since),
    'opted_out_total', (
      SELECT COUNT(*)::INT FROM public.whatsapp_preferences
      WHERE opted_out_at IS NOT NULL AND (opted_in_at IS NULL OR opted_in_at < opted_out_at)
    ),
    'templates_approved', (SELECT COUNT(*)::INT FROM public.whatsapp_template_registry WHERE status = 'approved'),
    'templates_total', (SELECT COUNT(*)::INT FROM public.whatsapp_template_registry)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_get_whatsapp_summary TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_list_whatsapp_templates()
RETURNS SETOF public.whatsapp_template_registry
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;
  RETURN QUERY SELECT * FROM public.whatsapp_template_registry ORDER BY semantic_key;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_list_whatsapp_templates TO authenticated;

-- Deliberately excludes body_text/template_params (message content) and
-- masks the phone to its last 4 digits — visibility into delivery status
-- and provider errors, not into what was said or the full recipient number.
CREATE OR REPLACE FUNCTION public.admin_list_whatsapp_outbox_page(
  p_status TEXT[] DEFAULT NULL,
  p_limit INT DEFAULT 50,
  p_offset INT DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  company_id UUID,
  company_name TEXT,
  recipient_phone_masked TEXT,
  message_kind public.whatsapp_message_kind,
  semantic_event_key TEXT,
  status public.whatsapp_message_status,
  attempt_count INT,
  last_error TEXT,
  provider_message_id TEXT,
  created_at TIMESTAMPTZ,
  submitted_at TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  read_at TIMESTAMPTZ,
  failed_at TIMESTAMPTZ,
  total_count BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  RETURN QUERY
  SELECT
    w.id, w.company_id, c.name,
    CASE WHEN length(w.recipient_phone) > 4 THEN '***' || right(w.recipient_phone, 4) ELSE '***' END,
    w.message_kind, w.semantic_event_key, w.status, w.attempt_count, w.last_error,
    w.provider_message_id, w.created_at, w.submitted_at, w.delivered_at, w.read_at, w.failed_at,
    COUNT(*) OVER ()::BIGINT
  FROM public.whatsapp_outbox w
  LEFT JOIN public.companies c ON c.id = w.company_id
  WHERE (p_status IS NULL OR w.status::TEXT = ANY (p_status))
  ORDER BY w.created_at DESC
  LIMIT LEAST(GREATEST(p_limit, 1), 200)
  OFFSET GREATEST(p_offset, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_list_whatsapp_outbox_page TO authenticated;

-- Fold a WhatsApp block into the existing communications summary rather
-- than a second, disconnected admin surface.
CREATE OR REPLACE FUNCTION public.get_admin_communications_summary(p_days INT DEFAULT 7)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_since TIMESTAMPTZ := now() - make_interval(days => GREATEST(LEAST(p_days, 90), 1));
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  RETURN jsonb_build_object(
    'sms', jsonb_build_object(
      'queued', (SELECT COUNT(*)::INT FROM public.sms_outbox WHERE status IN ('pending', 'processing')),
      'sent', (SELECT COUNT(*)::INT FROM public.sms_logs WHERE direction = 'outbound' AND created_at >= v_since),
      'failed', (SELECT COUNT(*)::INT FROM public.sms_outbox WHERE status = 'failed' AND created_at >= v_since),
      'inbound_commands', (SELECT COUNT(*)::INT FROM public.sms_logs WHERE direction = 'inbound' AND created_at >= v_since)
    ),
    'email', jsonb_build_object(
      'pending', (SELECT COUNT(*)::INT FROM public.email_outbox WHERE status IN ('pending', 'failed')),
      'sent', (SELECT COUNT(*)::INT FROM public.email_outbox WHERE status = 'sent' AND created_at >= v_since)
    ),
    'whatsapp', jsonb_build_object(
      'queued', (SELECT COUNT(*)::INT FROM public.whatsapp_outbox WHERE status IN ('pending', 'submitted')),
      'sent', (SELECT COUNT(*)::INT FROM public.whatsapp_outbox WHERE status IN ('sent', 'delivered', 'read') AND created_at >= v_since),
      'delivered', (SELECT COUNT(*)::INT FROM public.whatsapp_outbox WHERE status IN ('delivered', 'read') AND created_at >= v_since),
      'read', (SELECT COUNT(*)::INT FROM public.whatsapp_outbox WHERE status = 'read' AND created_at >= v_since),
      'failed', (SELECT COUNT(*)::INT FROM public.whatsapp_outbox WHERE status IN ('failed', 'dead') AND created_at >= v_since),
      'inbound', (SELECT COUNT(*)::INT FROM public.whatsapp_inbound_messages WHERE created_at >= v_since)
    ),
    'notifications', (
      SELECT COUNT(*)::INT FROM public.notification_logs WHERE created_at >= v_since
    ),
    'notifications_by_channel', (
      SELECT COALESCE(jsonb_object_agg(channel, cnt), '{}'::JSONB)
      FROM (
        SELECT channel, COUNT(*)::INT AS cnt
        FROM public.notification_logs
        WHERE created_at >= v_since
        GROUP BY channel
      ) q
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_admin_communications_summary TO authenticated;

-- ---------------------------------------------------------------------------
-- Wire the first 5 production-safe events through dispatch_channel_notification.
-- Every one of these keeps its EXACT existing SMS wording/behavior as the
-- SMS-fallback body — resolve_notification_channel returns 'sms' for all of
-- them today (no template approved), so this is a behavior-preserving
-- redefinition until a human approves templates and flips a company's
-- whatsapp_notifications_enabled on.
-- ---------------------------------------------------------------------------

-- 1) Vendor: new Commerce order.
CREATE OR REPLACE FUNCTION public.notify_vendor_new_commerce_order(p_order public.commerce_orders)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_phone TEXT;
  v_body TEXT;
BEGIN
  SELECT phone INTO v_phone FROM public.companies WHERE id = p_order.vendor_company_id;
  IF v_phone IS NULL OR v_phone = '' THEN RETURN; END IF;
  v_body := format(
    E'New DeliveryOS order #%s from %s. Total LRD %s. Open your vendor dashboard to accept.',
    p_order.order_number, COALESCE(p_order.customer_name, 'a customer'),
    to_char(p_order.total_lrd_cents / 100.0, 'FM999999990.00')
  );
  PERFORM public.dispatch_channel_notification(
    p_order.vendor_company_id, v_phone, 'commerce_order_created_vendor', v_body,
    jsonb_build_array(p_order.order_number, COALESCE(p_order.customer_name, 'a customer'), to_char(p_order.total_lrd_cents / 100.0, 'FM999999990.00')),
    NULL, p_order.id,
    'commerce_order_created_vendor:' || p_order.id::TEXT
  );
END;
$$;

-- 2/3) Customer: order accepted / rejected / ready. p_semantic_event_key
-- defaults to NULL so vendor_reject_commerce_order's existing 2-arg call
-- (unchanged, still SMS-only in Phase A) keeps working identically.
-- CREATE OR REPLACE cannot widen a function's parameter list into a new
-- overload in place — it would leave the old 2-arg version in the catalog
-- alongside this one, and a 2-arg call site becomes ambiguous between them
-- (confirmed: this exact failure mode broke commerce_phase_b.test.sql on
-- first pass). Drop the old signature first, matching the precedent set by
-- delivery_transition_core's own parameter-list change in rider_channels.sql.
DROP FUNCTION IF EXISTS public.notify_customer_commerce_order(public.commerce_orders, TEXT);

CREATE OR REPLACE FUNCTION public.notify_customer_commerce_order(
  p_order public.commerce_orders,
  p_body TEXT,
  p_semantic_event_key TEXT DEFAULT NULL,
  p_template_params JSONB DEFAULT '[]'::JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_order.customer_phone IS NULL OR p_order.customer_phone = '' THEN RETURN; END IF;
  IF p_semantic_event_key IS NOT NULL THEN
    PERFORM public.dispatch_channel_notification(
      p_order.vendor_company_id, p_order.customer_phone, p_semantic_event_key, p_body,
      p_template_params, p_order.delivery_id, p_order.id,
      p_semantic_event_key || ':' || p_order.id::TEXT
    );
  ELSE
    PERFORM public.queue_outbound_sms(p_order.vendor_company_id, p_order.customer_phone, p_body, p_order.delivery_id);
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_vendor_new_commerce_order(public.commerce_orders) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.notify_customer_commerce_order(public.commerce_orders, TEXT, TEXT, JSONB) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.vendor_accept_commerce_order(p_order_id UUID)
RETURNS public.commerce_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.commerce_orders;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT * INTO v_order FROM public.commerce_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'order_not_found'; END IF;

  PERFORM public.assert_vendor_order_actor(v_order.vendor_company_id);

  IF v_order.fulfillment_status <> 'awaiting_vendor' THEN
    RAISE EXCEPTION 'invalid_fulfillment_state';
  END IF;
  IF NOT public.commerce_order_payment_eligible_for_acceptance(v_order.id) THEN
    RAISE EXCEPTION 'payment_not_confirmed';
  END IF;

  UPDATE public.commerce_orders SET fulfillment_status = 'vendor_accepted', updated_at = now()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  PERFORM public.log_audit_event(
    v_order.vendor_company_id, 'commerce_order_accepted', 'commerce_orders', v_order.id, to_jsonb(v_order)
  );

  PERFORM public.notify_customer_commerce_order(
    v_order,
    format(E'Your DeliveryOS order #%s has been accepted and is being prepared.', v_order.order_number),
    'commerce_order_accepted_customer',
    jsonb_build_array(v_order.order_number)
  );

  RETURN v_order;
END;
$$;

GRANT EXECUTE ON FUNCTION public.vendor_accept_commerce_order TO authenticated;

CREATE OR REPLACE FUNCTION public.vendor_mark_order_ready(p_order_id UUID)
RETURNS public.commerce_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.commerce_orders;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT * INTO v_order FROM public.commerce_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'order_not_found'; END IF;

  PERFORM public.assert_vendor_order_actor(v_order.vendor_company_id);

  IF v_order.fulfillment_status <> 'preparing' THEN
    RAISE EXCEPTION 'invalid_fulfillment_state';
  END IF;

  UPDATE public.commerce_orders SET fulfillment_status = 'ready_for_pickup', updated_at = now()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  PERFORM public.notify_customer_commerce_order(
    v_order,
    format(E'Your DeliveryOS order #%s is ready and waiting for a carrier.', v_order.order_number),
    'commerce_order_ready_customer',
    jsonb_build_array(v_order.order_number)
  );

  RETURN v_order;
END;
$$;

GRANT EXECUTE ON FUNCTION public.vendor_mark_order_ready TO authenticated;

-- 4) Customer: carrier accepted. Identical body to the Phase F version
-- (see 20260309210000_commerce_phase_f_production_readiness.sql), with only
-- the notification call swapped for dispatch_channel_notification.
CREATE OR REPLACE FUNCTION public.accept_marketplace_offer(
  p_offer_id UUID,
  p_provider_company_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_offer public.delivery_offers;
  v_req public.delivery_requests;
  v_delivery public.deliveries;
  v_merchant_name TEXT;
  v_fee RECORD;
  v_tx public.marketplace_transactions;
  v_commerce_order public.commerce_orders;
  v_amount_to_collect INT;
BEGIN
  PERFORM public.assert_provider_marketplace(p_provider_company_id);
  IF NOT public.has_company_role(p_provider_company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[]) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT * INTO v_offer FROM public.delivery_offers
  WHERE id = p_offer_id AND provider_company_id = p_provider_company_id
  FOR UPDATE;

  IF NOT FOUND OR v_offer.status <> 'pending' THEN
    RAISE EXCEPTION 'invalid_offer';
  END IF;

  SELECT * INTO v_req FROM public.delivery_requests WHERE id = v_offer.delivery_request_id FOR UPDATE;
  IF v_req.status NOT IN ('open', 'offered') THEN
    RAISE EXCEPTION 'request_not_available';
  END IF;

  SELECT * INTO v_commerce_order FROM public.commerce_orders WHERE delivery_request_id = v_req.id FOR UPDATE;
  IF v_commerce_order.id IS NOT NULL AND v_offer.selected_by_customer_at IS NULL THEN
    RAISE EXCEPTION 'offer_not_selected_by_customer';
  END IF;

  UPDATE public.delivery_offers SET status = 'accepted', accepted_at = now() WHERE id = p_offer_id;

  UPDATE public.delivery_offers SET status = 'expired'
  WHERE delivery_request_id = v_req.id AND id <> p_offer_id AND status = 'pending';

  UPDATE public.delivery_requests SET
    status = 'accepted',
    selected_provider_id = p_provider_company_id,
    quoted_amount_lrd_cents = v_offer.quoted_amount_lrd_cents,
    accepted_at = now()
  WHERE id = v_req.id
  RETURNING * INTO v_req;

  SELECT name INTO v_merchant_name FROM public.companies WHERE id = v_req.merchant_company_id;

  v_amount_to_collect := CASE
    WHEN v_commerce_order.id IS NOT NULL THEN v_commerce_order.subtotal_lrd_cents + v_offer.quoted_amount_lrd_cents
    ELSE v_req.cod_amount_lrd_cents
  END;

  INSERT INTO public.deliveries (
    company_id, merchant_company_id, delivery_request_id,
    tracking_code, pickup_business_name, pickup_address,
    customer_id, customer_name, customer_phone, destination_address,
    package_description, amount_to_collect_lrd_cents, delivery_fee_lrd_cents,
    delivery_zone_id, status, created_by, commerce_order_id
  ) VALUES (
    p_provider_company_id, v_req.merchant_company_id, v_req.id,
    public.generate_tracking_code(),
    COALESCE(v_merchant_name, 'Merchant pickup'),
    v_req.pickup_address,
    v_req.customer_id,
    COALESCE(v_req.customer_name, 'Customer'),
    COALESCE(v_req.customer_phone, ''),
    v_req.destination_address,
    v_req.package_description,
    v_amount_to_collect,
    v_offer.quoted_amount_lrd_cents,
    v_req.zone_id,
    'pending',
    auth.uid(),
    v_commerce_order.id
  )
  RETURNING * INTO v_delivery;

  UPDATE public.delivery_requests SET status = 'converted', converted_delivery_id = v_delivery.id WHERE id = v_req.id;

  IF v_commerce_order.id IS NOT NULL THEN
    UPDATE public.commerce_orders SET
      delivery_id = v_delivery.id,
      delivery_fee_lrd_cents = v_offer.quoted_amount_lrd_cents,
      total_lrd_cents = subtotal_lrd_cents + v_offer.quoted_amount_lrd_cents,
      updated_at = now()
    WHERE id = v_commerce_order.id
    RETURNING * INTO v_commerce_order;

    IF v_commerce_order.customer_phone IS NOT NULL AND v_commerce_order.customer_phone <> '' THEN
      PERFORM public.dispatch_channel_notification(
        p_provider_company_id, v_commerce_order.customer_phone, 'carrier_accepted_customer',
        format(E'A carrier has accepted your DeliveryOS order #%s. You will be notified when it is picked up.', v_commerce_order.order_number),
        jsonb_build_array(v_commerce_order.order_number),
        v_delivery.id, v_commerce_order.id,
        'carrier_accepted_customer:' || v_commerce_order.id::TEXT
      );
    END IF;
  END IF;

  SELECT * INTO v_fee FROM public.compute_marketplace_fee_split(
    v_offer.quoted_amount_lrd_cents, v_req.merchant_company_id, p_provider_company_id
  );

  INSERT INTO public.marketplace_transactions (
    delivery_request_id, merchant_company_id, provider_company_id, delivery_id,
    gross_amount_lrd_cents, platform_fee_lrd_cents, provider_amount_lrd_cents, status
  ) VALUES (
    v_req.id, v_req.merchant_company_id, p_provider_company_id, v_delivery.id,
    v_offer.quoted_amount_lrd_cents, v_fee.platform_fee_lrd_cents, v_fee.provider_amount_lrd_cents, 'pending'
  )
  RETURNING * INTO v_tx;

  INSERT INTO public.marketplace_ledger_entries (company_id, account_type, marketplace_transaction_id, amount_lrd_cents, description)
  VALUES
    (v_req.merchant_company_id, 'merchant_payable', v_tx.id, v_offer.quoted_amount_lrd_cents, 'Marketplace delivery accepted'),
    (p_provider_company_id, 'provider_receivable', v_tx.id, v_fee.provider_amount_lrd_cents, 'Provider earnings'),
    (NULL, 'platform_revenue', v_tx.id, v_fee.platform_fee_lrd_cents, 'Platform fee');

  PERFORM public.enqueue_webhook_event(v_req.merchant_company_id, 'delivery_request.accepted', v_req.id,
    jsonb_build_object('request', to_jsonb(v_req), 'delivery_id', v_delivery.id));
  PERFORM public.enqueue_webhook_event(p_provider_company_id, 'marketplace_job.accepted', v_req.id,
    jsonb_build_object('delivery_id', v_delivery.id));
  PERFORM public.enqueue_webhook_event(v_req.merchant_company_id, 'marketplace.offer.accepted', v_offer.id, to_jsonb(v_offer));

  RETURN jsonb_build_object('delivery_request', to_jsonb(v_req), 'delivery', to_jsonb(v_delivery), 'transaction', to_jsonb(v_tx));
END;
$$;

GRANT EXECUTE ON FUNCTION public.accept_marketplace_offer TO authenticated;

-- 5) Customer: delivery delivered. picked_up/in_transit are left on plain
-- SMS in Phase A (their semantic keys exist in the registry for a future
-- phase, but are not actively wired here — conservative "first 5" scope).
CREATE OR REPLACE FUNCTION public.notify_customer_tracking(
  p_delivery public.deliveries,
  p_status public.delivery_status
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_body TEXT;
  v_base_url TEXT;
  v_track TEXT;
BEGIN
  v_base_url := public.get_platform_setting('public_app_url');
  v_track := CASE WHEN v_base_url IS NOT NULL THEN v_base_url || '/track/' || p_delivery.tracking_code ELSE NULL END;

  IF p_status IN ('picked_up', 'in_transit') THEN
    IF v_track IS NOT NULL THEN
      v_body := format(
        E'Hello %s\nYour package is on the way.\nStatus: %s\nTrack: %s',
        p_delivery.customer_name,
        replace(p_status::TEXT, '_', ' '),
        v_track
      );
    ELSE
      v_body := format(
        E'Hello %s\nYour package is on the way.\nStatus: %s',
        p_delivery.customer_name,
        replace(p_status::TEXT, '_', ' ')
      );
    END IF;
    PERFORM public.queue_outbound_sms(p_delivery.company_id, p_delivery.customer_phone, v_body, p_delivery.id);
  ELSIF p_status = 'delivered' THEN
    v_body := format(E'Hello %s\nYour package was delivered. Thank you!', p_delivery.customer_name);
    PERFORM public.dispatch_channel_notification(
      p_delivery.company_id, p_delivery.customer_phone, 'delivery_delivered_customer', v_body,
      jsonb_build_array(p_delivery.tracking_code),
      p_delivery.id, NULL,
      'delivery_delivered_customer:' || p_delivery.id::TEXT
    );
  ELSE
    RETURN;
  END IF;
END;
$$;
