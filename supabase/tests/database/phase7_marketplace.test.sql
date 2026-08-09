BEGIN;
SELECT plan(16);

SELECT has_type('public'::name, 'company_business_type'::name);
SELECT has_type('public'::name, 'delivery_request_status'::name);
SELECT has_type('public'::name, 'delivery_offer_status'::name);

SELECT has_table('public'::name, 'delivery_requests'::name);
SELECT has_table('public'::name, 'delivery_offers'::name);
SELECT has_table('public'::name, 'marketplace_transactions'::name);
SELECT has_table('public'::name, 'provider_marketplace_profiles'::name);

SELECT has_function('public', 'create_delivery_request', ARRAY['jsonb']);
SELECT has_function('public', 'publish_delivery_request', ARRAY['uuid', 'uuid']);
SELECT has_function('public', 'accept_marketplace_offer', ARRAY['uuid', 'uuid']);
SELECT has_function('public', 'compute_marketplace_fee_split', ARRAY['integer', 'uuid', 'uuid']);
SELECT has_function('public', 'get_marketplace_analytics', ARRAY['uuid', 'text']);
SELECT has_function('public', 'record_marketplace_settlement', ARRAY['jsonb']);

SELECT ok(
  EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'companies'
      AND column_name = 'business_type'
  ),
  'companies.business_type exists'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'subscriptions'
      AND column_name = 'marketplace_access'
  ),
  'subscriptions.marketplace_access exists'
);

SELECT ok(
  (SELECT business_type FROM public.companies LIMIT 1) IS NOT NULL
  OR NOT EXISTS (SELECT 1 FROM public.companies),
  'business_type default safe for existing rows'
);

SELECT * FROM finish();
ROLLBACK;
