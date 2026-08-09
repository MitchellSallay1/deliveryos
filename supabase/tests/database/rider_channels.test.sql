-- Rider channels pgTAP smoke checks
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(14);

SELECT has_enum('public'::name, 'rider_access_mode'::name);
SELECT has_enum('public'::name, 'delivery_proof_method'::name);

SELECT has_column('public'::name, 'riders'::name, 'access_mode'::name, 'riders.access_mode should exist');
SELECT has_column('public'::name, 'riders'::name, 'phone_normalized'::name, 'riders.phone_normalized should exist');
SELECT has_column('public'::name, 'companies'::name, 'enable_rider_sms'::name, 'companies.enable_rider_sms should exist');
SELECT has_column('public'::name, 'deliveries'::name, 'rider_job_sms_status'::name, 'deliveries.rider_job_sms_status should exist');
SELECT has_column('public'::name, 'delivery_status_history'::name, 'transition_source'::name, 'delivery_status_history.transition_source should exist');

SELECT has_table('public'::name, 'ussd_sessions'::name);
SELECT has_table('public'::name, 'delivery_verification_otps'::name);
SELECT has_table('public'::name, 'rider_channel_events'::name);

SELECT has_function('public'::name, 'apply_rider_channel_command'::name);
SELECT has_function('public'::name, 'handle_ussd_request'::name);
SELECT has_function('public'::name, 'normalize_phone_lr'::name);
SELECT has_function('public'::name, 'resend_rider_job_sms'::name);

SELECT * FROM finish();
ROLLBACK;
