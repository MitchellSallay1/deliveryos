-- Production readiness audit (C4): public_tracking_rate_limits was the only
-- table in the schema created without RLS. It is only ever read/written by
-- the SECURITY DEFINER function check_public_tracking_rate_limit (already
-- REVOKE PUBLIC — see docs/SECURITY_FUNCTION_AUDIT.md), which executes with
-- the function owner's privileges and bypasses RLS regardless of policy, so
-- this migration cannot break that path. Enabling RLS with zero policies
-- makes it deny-by-default for anon/authenticated/PostgREST direct access,
-- matching every other internal-only table in this schema (e.g. audit_logs,
-- api_auth_events, email_outbox).

ALTER TABLE public.public_tracking_rate_limits ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.public_tracking_rate_limits FROM anon, authenticated;
