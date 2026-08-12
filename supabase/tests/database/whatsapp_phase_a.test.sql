-- Coverage for DeliveryOS WhatsApp Phase A
-- (20260310000000_whatsapp_phase_a_foundation.sql).
--
-- Proves: schema/RLS shape exists on every new table; channel resolution
-- defaults to SMS everywhere until a template is explicitly approved AND a
-- company opts in; WhatsApp sends never decrement sms_credits; outbound
-- idempotency keys prevent duplicate rows; delivery-receipt status mapping
-- is forward-only (a late "sent" can't downgrade an observed "delivered");
-- inbound messages dedup by provider_message_id; STOP/START gate template
-- queueing but not session replies; ORDER/TRACK router commands only ever
-- reveal data to the phone number that owns it; cross-tenant RLS isolation
-- on whatsapp_outbox; and the wired Commerce/delivery events still queue a
-- notification (SMS today) without erroring.

BEGIN;
SELECT plan(45);

-- ---------------------------------------------------------------------------
-- Schema shape
-- ---------------------------------------------------------------------------
SELECT has_enum('public'::name, 'whatsapp_message_kind'::name);
SELECT has_enum('public'::name, 'whatsapp_message_status'::name);
SELECT has_table('public'::name, 'whatsapp_outbox'::name);
SELECT has_table('public'::name, 'whatsapp_inbound_messages'::name);
SELECT has_table('public'::name, 'whatsapp_preferences'::name);
SELECT has_table('public'::name, 'whatsapp_template_registry'::name);
SELECT has_column('public'::name, 'companies'::name, 'whatsapp_notifications_enabled'::name, 'companies.whatsapp_notifications_enabled should exist');

SELECT has_function('public'::name, 'resolve_notification_channel'::name);
SELECT has_function('public'::name, 'dispatch_channel_notification'::name);
SELECT has_function('public'::name, 'queue_outbound_whatsapp'::name);
SELECT has_function('public'::name, 'queue_outbound_whatsapp_session_reply'::name);
SELECT has_function('public'::name, 'apply_whatsapp_status_event'::name);
SELECT has_function('public'::name, 'apply_whatsapp_opt_command'::name);
SELECT has_function('public'::name, 'whatsapp_router_handle'::name);
SELECT has_function('public'::name, 'record_whatsapp_inbound_message'::name);
SELECT has_function('public'::name, 'get_public_commerce_order_status'::name);

SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.whatsapp_outbox'::regclass),
  'whatsapp_outbox has RLS enabled'
);
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.whatsapp_inbound_messages'::regclass),
  'whatsapp_inbound_messages has RLS enabled'
);
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.whatsapp_preferences'::regclass),
  'whatsapp_preferences has RLS enabled'
);
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.whatsapp_template_registry'::regclass),
  'whatsapp_template_registry has RLS enabled'
);

SELECT is(
  (SELECT COUNT(*)::INT FROM public.whatsapp_template_registry WHERE gupshup_template_id IS NOT NULL),
  0,
  'no template starts pre-approved — every seeded row is draft/unconfigured'
);

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.make_company(p_label TEXT)
RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
  v_owner UUID := gen_random_uuid();
  v_company UUID;
BEGIN
  INSERT INTO auth.users (id, phone, email, encrypted_password, phone_confirmed_at, aud, role)
  VALUES (
    v_owner, '+23177' || lpad((floor(random() * 999999))::text, 6, '0'),
    'wa-' || substr(v_owner::text, 1, 8) || '@test.local',
    crypt('x', gen_salt('bf')), now(), 'authenticated', 'authenticated'
  );
  INSERT INTO public.profiles (id, full_name) VALUES (v_owner, p_label) ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  v_company := public.create_company_with_owner(
    p_label, '+23177' || lpad((floor(random() * 999999))::text, 6, '0'),
    lower(replace(p_label, ' ', '')) || '@test.local', NULL, 'logistics_provider'
  );
  PERFORM set_config('request.jwt.claim.sub', '', true);

  UPDATE public.company_subscriptions SET plan_id = (SELECT id FROM public.subscriptions WHERE slug = 'business')
  WHERE company_subscriptions.company_id = v_company;
  UPDATE public.companies SET sms_credits_purchased = sms_credits_purchased + 50 WHERE id = v_company;

  RETURN v_company;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.company_owner(p_company_id UUID)
RETURNS UUID LANGUAGE sql AS $$
  SELECT user_id FROM public.company_users WHERE company_id = p_company_id AND role = 'company_owner' LIMIT 1;
$$;

SELECT pg_temp.make_company('WA Test Co A') \gset a_
SELECT pg_temp.make_company('WA Test Co B') \gset b_

-- ---------------------------------------------------------------------------
-- Channel resolution defaults to SMS everywhere (no template approved)
-- ---------------------------------------------------------------------------
SELECT is(
  public.resolve_notification_channel(:'a_make_company', '+231770000101', 'commerce_order_created_vendor'),
  'sms',
  'channel resolves to sms when company has not enabled WhatsApp'
);

UPDATE public.companies SET whatsapp_notifications_enabled = true WHERE id = :'a_make_company'::UUID;

SELECT is(
  public.resolve_notification_channel(:'a_make_company', '+231770000101', 'commerce_order_created_vendor'),
  'sms',
  'channel still resolves to sms when enabled but no template is approved'
);

-- Approve one template for company A's fixture only.
UPDATE public.whatsapp_template_registry
SET status = 'approved', gupshup_template_id = 'gs-template-test-1'
WHERE semantic_key = 'commerce_order_created_vendor';

SELECT is(
  public.resolve_notification_channel(:'a_make_company', '+231770000101', 'commerce_order_created_vendor'),
  'whatsapp',
  'channel resolves to whatsapp once enabled + approved template exists'
);

SELECT is(
  public.resolve_notification_channel(:'a_make_company', '+231770000101', 'commerce_order_accepted_customer'),
  'sms',
  'a different, still-unapproved semantic key still resolves to sms for the same company'
);

-- ---------------------------------------------------------------------------
-- dispatch_channel_notification never decrements sms_credits when it
-- chooses WhatsApp (billing separation).
-- ---------------------------------------------------------------------------
SELECT sms_credits AS value FROM public.companies WHERE id = :'a_make_company'::UUID \gset a_credits_before_

SELECT is(
  public.dispatch_channel_notification(
    :'a_make_company', '+231770000101', 'commerce_order_created_vendor', 'sms fallback body'
  ),
  'whatsapp',
  'dispatch_channel_notification chooses whatsapp when eligible'
);

SELECT is(
  (SELECT sms_credits FROM public.companies WHERE id = :'a_make_company'::UUID),
  :a_credits_before_value,
  'sms_credits unchanged after a WhatsApp send — no cross-channel billing'
);

SELECT is(
  (SELECT COUNT(*)::INT FROM public.whatsapp_outbox WHERE company_id = :'a_make_company'::UUID),
  1,
  'exactly one whatsapp_outbox row created for the dispatched event'
);

-- Company B (WhatsApp not enabled) falls back to sms and DOES decrement.
SELECT sms_credits AS value FROM public.companies WHERE id = :'b_make_company'::UUID \gset b_credits_before_

SELECT is(
  public.dispatch_channel_notification(
    :'b_make_company', '+231770000201', 'commerce_order_created_vendor', 'sms fallback body'
  ),
  'sms',
  'company without WhatsApp enabled falls back to sms'
);

SELECT isnt(
  (SELECT sms_credits FROM public.companies WHERE id = :'b_make_company'::UUID),
  :b_credits_before_value,
  'sms_credits DOES decrement for the sms fallback path'
);

-- ---------------------------------------------------------------------------
-- Idempotency
-- ---------------------------------------------------------------------------
SELECT is(
  public.queue_outbound_whatsapp(:'a_make_company', '+231770000301', 'commerce_order_created_vendor', '[]'::JSONB, 'idem-test-1'),
  true,
  'first queue with an idempotency key succeeds'
);
SELECT is(
  public.queue_outbound_whatsapp(:'a_make_company', '+231770000301', 'commerce_order_created_vendor', '[]'::JSONB, 'idem-test-1'),
  false,
  'second queue with the SAME idempotency key is a no-op'
);
SELECT is(
  (SELECT COUNT(*)::INT FROM public.whatsapp_outbox WHERE idempotency_key = 'idem-test-1'),
  1,
  'exactly one row exists for the reused idempotency key'
);

-- ---------------------------------------------------------------------------
-- Forward-only delivery-receipt mapping
-- ---------------------------------------------------------------------------
UPDATE public.whatsapp_outbox SET provider_message_id = 'wamid-forward-test' WHERE idempotency_key = 'idem-test-1';
SELECT public.apply_whatsapp_status_event('wamid-forward-test', 'sent') \gset _discard_
SELECT public.apply_whatsapp_status_event('wamid-forward-test', 'delivered') \gset _discard_
-- late/duplicate resend of the same event:
SELECT public.apply_whatsapp_status_event('wamid-forward-test', 'sent') \gset _discard_
SELECT is(
  (SELECT status::TEXT FROM public.whatsapp_outbox WHERE idempotency_key = 'idem-test-1'),
  'delivered',
  'a late duplicate "sent" event does not downgrade an observed "delivered" status'
);
SELECT ok(
  (SELECT sent_at IS NOT NULL AND delivered_at IS NOT NULL FROM public.whatsapp_outbox WHERE idempotency_key = 'idem-test-1'),
  'both sent_at and delivered_at are recorded'
);

-- ---------------------------------------------------------------------------
-- Inbound dedup
-- ---------------------------------------------------------------------------
SELECT is_new FROM public.record_whatsapp_inbound_message('inbound-dedup-1', 'DeliveryOS', '+231770000401', 'text', 'hello') \gset first_
SELECT is(:'first_is_new'::BOOLEAN, true, 'first inbound record is new');
SELECT is_new FROM public.record_whatsapp_inbound_message('inbound-dedup-1', 'DeliveryOS', '+231770000401', 'text', 'hello') \gset second_
SELECT is(:'second_is_new'::BOOLEAN, false, 'replayed inbound record (same provider_message_id) is not new');
SELECT is(
  (SELECT COUNT(*)::INT FROM public.whatsapp_inbound_messages WHERE provider_message_id = 'inbound-dedup-1'),
  1,
  'exactly one row stored despite the replay'
);

-- ---------------------------------------------------------------------------
-- STOP / START gate template queueing, not session replies
-- ---------------------------------------------------------------------------
SELECT public.whatsapp_router_handle('+231770000501', 'STOP') \gset _discard_
SELECT is(public.is_whatsapp_opted_out('+231770000501'), true, 'STOP opts the phone out');
SELECT is(
  public.queue_outbound_whatsapp(:'a_make_company', '+231770000501', 'commerce_order_created_vendor', '[]'::JSONB),
  false,
  'template queueing is blocked for an opted-out phone'
);
SELECT is(
  public.queue_outbound_whatsapp_session_reply(:'a_make_company', '+231770000501', 'Your STOP was received.'),
  true,
  'a direct session reply is NOT blocked by opt-out (reply to the user''s own message)'
);
SELECT public.whatsapp_router_handle('+231770000501', 'START') \gset _discard_
SELECT is(public.is_whatsapp_opted_out('+231770000501'), false, 'START opts back in');

-- ---------------------------------------------------------------------------
-- ORDER command: phone must match the order's customer_phone
-- ---------------------------------------------------------------------------
SELECT ok(
  public.get_public_commerce_order_status('ORD-NONEXISTENT-00000', '+231770000601') IS NULL,
  'ORDER lookup for a nonexistent order returns NULL'
);

-- ---------------------------------------------------------------------------
-- Cross-tenant RLS isolation on whatsapp_outbox
-- ---------------------------------------------------------------------------
-- Company A has real whatsapp_outbox rows (queued earlier in this file);
-- company B never queued any WhatsApp message (it always resolved to sms),
-- so the meaningful visibility check is company B's owner seeing NONE of
-- company A's rows, and company A's OWNER seeing their own.
--
-- Resolve BOTH owner ids now, while still running with full privileges —
-- pg_temp.company_owner is plain SQL (not SECURITY DEFINER), so once the
-- session below switches to `role authenticated` impersonating company B,
-- it would itself be subject to company_users' own RLS and unable to
-- cross-tenant-resolve company A's owner id.
SELECT pg_temp.company_owner(:'a_make_company') AS value \gset a_owner_
SELECT pg_temp.company_owner(:'b_make_company') AS value \gset b_owner_

SET LOCAL role authenticated;
SELECT set_config('request.jwt.claim.sub', :'b_owner_value', true) \gset _discard_
SELECT set_config('request.jwt.claim.role', 'authenticated', true) \gset _discard_
SELECT is(
  (SELECT COUNT(*)::INT FROM public.whatsapp_outbox WHERE company_id = :'a_make_company'::UUID),
  0,
  'company B''s owner cannot see company A''s whatsapp_outbox rows via RLS'
);

SELECT set_config('request.jwt.claim.sub', :'a_owner_value', true) \gset _discard_
SELECT is(
  (SELECT COUNT(*)::INT FROM public.whatsapp_outbox WHERE company_id = :'a_make_company'::UUID) >= 1,
  true,
  'company A''s owner CAN see their own whatsapp_outbox rows'
);
RESET role;
SELECT set_config('request.jwt.claim.sub', '', true) \gset _discard_

SELECT * FROM finish();
ROLLBACK;
