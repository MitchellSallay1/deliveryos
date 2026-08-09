-- Production readiness audit (C4): a schema diff against the linked project
-- (`supabase db diff --linked`) found the "pg_net" extension enabled on the
-- live database with no corresponding migration anywhere in this repo, and
-- no application code (Edge Functions or SQL) references it (`net.http_*`).
--
-- This migration does not change behavior — it only brings the migration
-- history in line with what is already running in production, so a fresh
-- `supabase db reset` / new environment matches production instead of
-- silently drifting from it. It is intentionally NOT dropped here: removing
-- an extension from a live database without knowing why it was enabled is a
-- production risk this audit is not authorized to take. If nothing in your
-- ops tooling (webhooks, notifications, other Supabase features configured
-- via the dashboard) depends on it, it can be dropped in a follow-up
-- migration after confirming that with the team.

CREATE EXTENSION IF NOT EXISTS pg_net;
