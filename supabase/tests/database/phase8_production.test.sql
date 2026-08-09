BEGIN;
SELECT plan(8);

SELECT has_function('public', 'run_scheduled_maintenance_jobs');
SELECT has_function('public', 'assert_subscription_operational', ARRAY['uuid']);
SELECT has_function('public', 'check_public_tracking_rate_limit', ARRAY['text']);
SELECT has_function('public', 'get_company_onboarding_status', ARRAY['uuid']);
SELECT has_function('public', 'admin_list_webhook_failures');
SELECT has_table('public', 'email_outbox');
SELECT has_table('public', 'public_tracking_rate_limits');

SELECT ok(
  (SELECT length(public.generate_tracking_code()) >= 16),
  'tracking codes have increased entropy'
);

SELECT * FROM finish();
ROLLBACK;
