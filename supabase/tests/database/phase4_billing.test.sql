-- DeliveryOS Phase 4 · database integration tests (pgTAP)
-- Run: npx supabase test db
-- Or: npm run test:db (Vitest + DATABASE_URL)

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(24);

-- Schema objects
SELECT has_table('public', 'company_subscriptions');
SELECT has_table('public', 'invoices');
SELECT has_table('public', 'subscription_billing_payments');
SELECT has_table('public', 'audit_logs');

SELECT has_function('public', 'can_use_feature', ARRAY['uuid', 'text']);
SELECT has_function('public', 'get_company_usage', ARRAY['uuid']);
SELECT has_function('public', 'get_delivery_tracking', ARRAY['text']);
SELECT has_function('public', 'admin_record_billing_payment');
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

-- Public tracking must not expose raw full addresses in function definition
SELECT ok(
  position('pickup_address' IN pg_get_functiondef('public.get_delivery_tracking(text)'::regprocedure)) = 0,
  'get_delivery_tracking should not return pickup_address column'
);

SELECT ok(
  position('generalize_address' IN pg_get_functiondef('public.get_delivery_tracking(text)'::regprocedure)) > 0,
  'get_delivery_tracking uses generalize_address'
);

-- Feature access denies when no active subscription row
SELECT ok(
  public.can_use_feature('00000000-0000-0000-0000-000000000099'::uuid, 'advanced_reports') = false,
  'can_use_feature false for unknown company'
);

-- Audit logs are not writable by authenticated role directly
SELECT ok(
  NOT has_table_privilege('authenticated', 'public.audit_logs', 'INSERT'),
  'authenticated cannot INSERT audit_logs directly'
);

SELECT * FROM finish();

ROLLBACK;
