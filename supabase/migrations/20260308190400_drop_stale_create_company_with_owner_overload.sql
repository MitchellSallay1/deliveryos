-- Production readiness audit (C3, discovered while fixing the DB test
-- suite): create_company_with_owner has two live overloads —
--   (text, text, text, text DEFAULT NULL)                          -- original, initial_schema.sql
--   (text, text, text, text DEFAULT NULL, company_business_type DEFAULT ...) -- current, phone_auth.sql
-- Every later migration re-defined the 5-parameter form (CREATE OR REPLACE
-- only replaces a function with an IDENTICAL parameter signature), so the
-- original 4-parameter form was never dropped and still lives alongside it.
-- Calling the function with exactly 3 or exactly 4 positional/unnamed
-- arguments is ambiguous ("function ... is not unique") — reproduced while
-- fixing tests/db/onboarding-subscription.test.ts.
--
-- The frontend (src/services/onboarding-service.ts) always calls with all
-- five named parameters, including p_business_type, so it only ever matches
-- the current 5-parameter overload and is unaffected. Nothing else in this
-- repo references the 4-parameter form. Dropping the superseded overload
-- removes a landmine for any future caller (scripts, admin tools, future
-- Edge Functions) that omits p_business_type.

DROP FUNCTION IF EXISTS public.create_company_with_owner(TEXT, TEXT, TEXT, TEXT);
