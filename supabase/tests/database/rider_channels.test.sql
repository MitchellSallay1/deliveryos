-- Rider channels pgTAP smoke checks
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(14);

SELECT has_enum('public', 'rider_access_mode');
SELECT has_enum('public', 'delivery_proof_method');

SELECT has_column('public', 'riders', 'access_mode');
SELECT has_column('public', 'riders', 'phone_normalized');
SELECT has_column('public', 'companies', 'enable_rider_sms');
SELECT has_column('public', 'deliveries', 'rider_job_sms_status');
SELECT has_column('public', 'delivery_status_history', 'transition_source');

SELECT has_table('public', 'ussd_sessions');
SELECT has_table('public', 'delivery_verification_otps');
SELECT has_table('public', 'rider_channel_events');

SELECT has_function('public', 'apply_rider_channel_command');
SELECT has_function('public', 'handle_ussd_request');
SELECT has_function('public', 'normalize_phone_lr');
SELECT has_function('public', 'resend_rider_job_sms');

SELECT * FROM finish();
ROLLBACK;
