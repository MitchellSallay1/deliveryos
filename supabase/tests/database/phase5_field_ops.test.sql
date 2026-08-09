-- Phase 5 field ops pgTAP checks
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(12);

SELECT has_table('public', 'rider_locations');
SELECT has_table('public', 'delivery_zones');
SELECT has_table('public', 'api_keys');
SELECT has_table('public', 'webhook_endpoints');
SELECT has_table('public', 'webhook_deliveries');
SELECT has_table('public', 'sms_outbox');

SELECT has_function('public', 'record_rider_location');
SELECT has_function('public', 'get_public_delivery_tracking');
SELECT has_function('public', 'verify_api_key');
SELECT has_function('public', 'get_operational_analytics');

SELECT ok(
  NOT has_table_privilege('authenticated', 'public.api_keys', 'INSERT'),
  'authenticated cannot insert api_keys directly'
);

SELECT policies_are('public', 'rider_locations', ARRAY['rider_locations_select']);

SELECT * FROM finish();
ROLLBACK;
