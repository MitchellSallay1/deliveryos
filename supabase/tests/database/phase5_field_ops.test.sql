-- Phase 5 field ops pgTAP checks
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(12);

SELECT has_table('public'::name, 'rider_locations'::name);
SELECT has_table('public'::name, 'delivery_zones'::name);
SELECT has_table('public'::name, 'api_keys'::name);
SELECT has_table('public'::name, 'webhook_endpoints'::name);
SELECT has_table('public'::name, 'webhook_deliveries'::name);
SELECT has_table('public'::name, 'sms_outbox'::name);

SELECT has_function('public'::name, 'record_rider_location'::name);
SELECT has_function('public'::name, 'get_public_delivery_tracking'::name);
SELECT has_function('public'::name, 'verify_api_key'::name);
SELECT has_function('public'::name, 'get_operational_analytics'::name);

SELECT ok(
  NOT has_table_privilege('authenticated', 'public.api_keys', 'INSERT'),
  'authenticated cannot insert api_keys directly'
);

SELECT policies_are('public', 'rider_locations', ARRAY['rider_locations_select']);

SELECT * FROM finish();
ROLLBACK;
