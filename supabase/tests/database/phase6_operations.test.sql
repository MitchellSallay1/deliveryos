-- Phase 6 operations pgTAP
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(10);

SELECT has_table('public', 'company_branches');
SELECT has_table('public', 'vehicles');
SELECT has_table('public', 'inventory_movements');
SELECT has_table('public', 'cash_settlements');
SELECT has_table('public', 'delivery_returns');

SELECT has_function('public', 'can_use_feature');
SELECT has_function('public', 'inventory_receive_stock');
SELECT has_function('public', 'reconcile_cash_settlement');

SELECT ok(
  NOT has_table_privilege('authenticated', 'public.inventory_movements', 'INSERT'),
  'no direct insert on inventory_movements'
);

SELECT ok(
  (SELECT COUNT(*) FROM public.company_branches) >= 1,
  'default branch backfill'
);

SELECT * FROM finish();
ROLLBACK;
