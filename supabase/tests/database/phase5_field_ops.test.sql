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

-- authenticated has a real GRANT INSERT (matches production's platform
-- default — 20260308190500_codify_anon_authenticated_table_grants.sql), so
-- has_table_privilege() no longer reflects the real boundary; RLS (no
-- INSERT policy on api_keys) is what actually blocks this.
DO $$
DECLARE
  v_blocked BOOLEAN := false;
BEGIN
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
    INSERT INTO public.api_keys (company_id, name, key_prefix, hashed_key)
    VALUES (gen_random_uuid(), 'test', 'test', 'test');
  EXCEPTION WHEN OTHERS THEN
    v_blocked := true;
  END;
  RESET ROLE;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'expected authenticated INSERT into api_keys to be rejected';
  END IF;
END;
$$;

SELECT pass('authenticated cannot insert api_keys directly');

SELECT policies_are('public', 'rider_locations', ARRAY['rider_locations_select']);

SELECT * FROM finish();
ROLLBACK;
