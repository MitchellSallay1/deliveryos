-- Production readiness audit (C3, discovered while fixing the DB test
-- suite): same class of bug as 20260308190400 — create_delivery has two
-- live overloads (10-parameter original from
-- 20260307130000_deliveries_functions.sql, and the current 12-parameter
-- form adding p_delivery_zone_id/p_fee_manual_override from
-- 20260307240100_phase8_production_functions.sql). CREATE OR REPLACE never
-- dropped the original when the signature grew, so calling with just the
-- shared 6 required parameters is ambiguous ("function ... is not unique").
--
-- Both the frontend (src/services/delivery-service.ts) and the public API
-- (supabase/functions/api-v1) always pass all twelve named parameters, so
-- they only ever match the current overload and are unaffected. Nothing
-- else references the 10-parameter form.

DROP FUNCTION IF EXISTS public.create_delivery(
  UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INT, INT, UUID
);
