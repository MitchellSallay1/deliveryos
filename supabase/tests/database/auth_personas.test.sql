-- Auth personas pgTAP smoke checks
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(6);

SELECT has_column('public', 'riders', 'invite_code');
SELECT has_function('public', 'link_rider_account');
SELECT has_function('public', 'generate_rider_invite_code');
SELECT has_function('public', 'regenerate_rider_invite_code');
SELECT has_function('public', 'get_rider_invite_preview');

SELECT ok(
  (SELECT COUNT(*) FROM pg_indexes WHERE indexname = 'idx_riders_invite_code_unique') >= 1,
  'unique invite code index exists'
);

SELECT * FROM finish();
ROLLBACK;
