-- Auth personas pgTAP smoke checks
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(6);

SELECT has_column('public'::name, 'riders'::name, 'invite_code'::name, 'riders.invite_code should exist');
SELECT has_function('public'::name, 'link_rider_account'::name);
SELECT has_function('public'::name, 'generate_rider_invite_code'::name);
SELECT has_function('public'::name, 'regenerate_rider_invite_code'::name);
SELECT has_function('public'::name, 'get_rider_invite_preview'::name);

SELECT ok(
  (SELECT COUNT(*) FROM pg_indexes WHERE indexname = 'idx_riders_invite_code_unique') >= 1,
  'unique invite code index exists'
);

SELECT * FROM finish();
ROLLBACK;
