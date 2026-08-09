-- Phase 6 operations pgTAP
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(10);

SELECT has_table('public'::name, 'company_branches'::name);
SELECT has_table('public'::name, 'vehicles'::name);
SELECT has_table('public'::name, 'inventory_movements'::name);
SELECT has_table('public'::name, 'cash_settlements'::name);
SELECT has_table('public'::name, 'delivery_returns'::name);

SELECT has_function('public'::name, 'can_use_feature'::name);
SELECT has_function('public'::name, 'inventory_receive_stock'::name);
SELECT has_function('public'::name, 'reconcile_cash_settlement'::name);

SELECT ok(
  NOT has_table_privilege('authenticated', 'public.inventory_movements', 'INSERT'),
  'no direct insert on inventory_movements'
);

-- The "default branch" backfill (20260307220000_phase6_operations_schema.sql)
-- only ran once, at migration time, against companies that existed then — a
-- fresh test database has none, so this exercises the same backfill SQL
-- pattern in isolation against one throwaway company instead of assuming
-- pre-existing data.
DO $$
DECLARE
  v_company UUID := gen_random_uuid();
  v_plan UUID;
BEGIN
  SELECT id INTO v_plan FROM public.subscriptions WHERE slug = 'starter' LIMIT 1;
  INSERT INTO public.companies (id, name, slug, phone, email, status, subscription_id)
  VALUES (v_company, 'Branch Backfill Co', 'branch-bf-' || substr(v_company::text, 1, 8), '+231770000098', 'branch-bf@test.local', 'active', v_plan);

  INSERT INTO public.company_branches (company_id, name, code, city, is_active)
  SELECT c.id, c.name || ' Main', 'MAIN', 'Monrovia', true
  FROM public.companies c
  WHERE c.id = v_company
    AND NOT EXISTS (SELECT 1 FROM public.company_branches b WHERE b.company_id = c.id);

  UPDATE public.companies c
  SET default_branch_id = b.id
  FROM public.company_branches b
  WHERE b.company_id = c.id AND c.id = v_company AND b.code = 'MAIN' AND c.default_branch_id IS NULL;

  IF (SELECT COUNT(*) FROM public.company_branches WHERE company_id = v_company) <> 1 THEN
    RAISE EXCEPTION 'expected exactly one backfilled branch';
  END IF;

  IF (SELECT default_branch_id FROM public.companies WHERE id = v_company) IS NULL THEN
    RAISE EXCEPTION 'expected default_branch_id to be set';
  END IF;

  DELETE FROM public.companies WHERE id = v_company;
END;
$$;

SELECT pass('default branch backfill pattern creates and links a MAIN branch');

SELECT * FROM finish();
ROLLBACK;
