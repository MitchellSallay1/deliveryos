-- Production readiness audit (C4, completed while verifying C3): the schema
-- diff against the linked project (`supabase db diff --linked`) showed
-- production grants SELECT/INSERT/UPDATE/DELETE on essentially every public
-- table to anon and authenticated — this is Supabase's platform bootstrap
-- applied at project creation, not something any migration in this repo
-- ever issued. RLS is therefore the ONLY access control on production, by
-- design (see ARCHITECTURE.md's security model).
--
-- The local Supabase CLI dev stack does not replicate that bootstrap, so
-- `authenticated`/`anon` locally have NO table grants at all. This silently
-- broke tests/db/rls-security.test.ts and tests/db/integration.test.ts —
-- every one of their `SET LOCAL role authenticated` queries failed with a
-- base "permission denied for table X" before RLS was ever evaluated, which
-- is a different failure than an RLS policy actually being tested. That
-- suite could never have passed locally regardless of policy correctness.
--
-- This migration codifies production's actual grant model so local/CI runs
-- match it (closing the drift found during the audit) and RLS can finally
-- be exercised locally. It intentionally excludes public_tracking_rate_limits,
-- which 20260308190000_public_tracking_rate_limits_rls.sql deliberately
-- locked down to internal-only access.

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT c.relname
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('r', 'p')
      AND c.relname <> 'public_tracking_rate_limits'
  LOOP
    EXECUTE format(
      'GRANT SELECT, INSERT, UPDATE, DELETE ON public.%I TO anon, authenticated',
      r.relname
    );
  END LOOP;
END;
$$;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO anon, authenticated;

-- Re-assert the internal-only table stays locked down regardless of
-- migration ordering.
REVOKE ALL ON public.public_tracking_rate_limits FROM anon, authenticated;
