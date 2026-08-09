-- DeliveryOS Phase 4 · database integration tests (pgTAP)
-- Run: npx supabase test db
-- Or: npm run test:db (Vitest + DATABASE_URL)

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(19);

-- Schema objects
SELECT has_table('public'::name, 'company_subscriptions'::name);
SELECT has_table('public'::name, 'invoices'::name);
SELECT has_table('public'::name, 'subscription_billing_payments'::name);
SELECT has_table('public'::name, 'audit_logs'::name);

SELECT has_function('public', 'can_use_feature', ARRAY['uuid', 'text']);
SELECT has_function('public', 'get_company_usage', ARRAY['uuid']);
SELECT has_function('public', 'get_delivery_tracking', ARRAY['text']);
SELECT has_function('public'::name, 'admin_record_billing_payment'::name);
SELECT has_function('public', 'log_audit_event', ARRAY['uuid', 'text', 'text', 'uuid', 'jsonb']);

-- RLS enabled on billing tables
SELECT policies_are(
  'public',
  'invoices',
  ARRAY['invoices_select']
);

SELECT policies_are(
  'public',
  'company_subscriptions',
  ARRAY['company_subscriptions_select']
);

SELECT policies_are(
  'public',
  'subscription_billing_payments',
  ARRAY['subscription_billing_payments_select']
);

SELECT policies_are(
  'public',
  'audit_logs',
  ARRAY['audit_logs_select']
);

-- Payments: no broad write policy (deposits via RPC)
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'payments'
      AND policyname = 'payments_write'
  ),
  'payments_write policy must not exist'
);

-- Plan catalog seeded
SELECT ok(
  (SELECT COUNT(*) FROM public.subscriptions WHERE slug IN ('starter', 'business', 'enterprise')) >= 3,
  'starter/business/enterprise plans exist'
);

-- Public tracking must not expose raw full addresses in function definition.
-- get_delivery_tracking(text) is now a thin wrapper around
-- get_public_delivery_tracking(text,text) (see 20260307210100_..._functions.sql
-- and 20260307240100_phase8_production_functions.sql) — the address
-- generalization actually happens in the latter, so that's what these check.
-- The function legitimately references `v_d.pickup_address` as INPUT to
-- generalize_address(); what must never appear is 'pickup_address' used as a
-- returned JSONB key (i.e. passed straight through instead of generalized).
SELECT ok(
  position('''pickup_address''' IN pg_get_functiondef('public.get_public_delivery_tracking(text,text)'::regprocedure)) = 0,
  'get_public_delivery_tracking should not return raw pickup_address column'
);

SELECT ok(
  position('generalize_address' IN pg_get_functiondef('public.get_public_delivery_tracking(text,text)'::regprocedure)) > 0,
  'get_public_delivery_tracking uses generalize_address'
);

-- Feature access denies when no active subscription row
SELECT ok(
  public.can_use_feature('00000000-0000-0000-0000-000000000099'::uuid, 'advanced_reports') = false,
  'can_use_feature false for unknown company'
);

-- Audit logs are not writable by authenticated role directly. The
-- authenticated role has a real GRANT INSERT (matching production's
-- platform-default grants — see 20260308190500_codify_anon_authenticated_table_grants.sql),
-- so has_table_privilege() alone no longer reflects the real security
-- boundary; RLS (no INSERT policy for audit_logs) is what actually blocks
-- this, so exercise that directly.
DO $$
DECLARE
  v_blocked BOOLEAN := false;
BEGIN
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
    INSERT INTO public.audit_logs (action, entity_type) VALUES ('test', 'test');
  EXCEPTION WHEN OTHERS THEN
    v_blocked := true;
  END;
  RESET ROLE;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'expected authenticated INSERT into audit_logs to be rejected';
  END IF;
END;
$$;

SELECT pass('authenticated cannot INSERT audit_logs directly');

SELECT * FROM finish();

ROLLBACK;
