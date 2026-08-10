-- ---------------------------------------------------------------------------
-- Tenant dashboard rebuild: a real day-by-day delivery trend for the
-- authenticated company workspace. The existing get_workspace_report('week')
-- only returns one aggregate summary for the whole week — there is no
-- per-day series anywhere for tenants, which is why the old dashboard used
-- hardcoded placeholder bars for 6 of 7 days. This replaces that with real
-- data.
--
-- Deliberately NOT gated by the 'advanced_reports' feature (unlike
-- get_workspace_report for non-'day' periods): a basic volume trend is core
-- operational visibility on the main dashboard every plan sees, not a
-- premium analytics feature. No billing/plan enforcement is changed —
-- reads only, same tenant-membership gate as every other report RPC, no
-- write access, no RLS change.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_company_delivery_trend(
  p_company_id UUID,
  p_days INT DEFAULT 7
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_days INT := GREATEST(1, LEAST(p_days, 30));
  v_local_today DATE;
  v_series JSONB;
BEGIN
  PERFORM public.assert_company_member(p_company_id);

  v_local_today := (current_timestamp AT TIME ZONE 'Africa/Monrovia')::DATE;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'date', d.day,
    'total', COALESCE(c.total, 0),
    'completed', COALESCE(c.completed, 0),
    'failed', COALESCE(c.failed, 0)
  ) ORDER BY d.day), '[]'::JSONB)
  INTO v_series
  FROM generate_series(v_local_today - (v_days - 1), v_local_today, INTERVAL '1 day') AS d(day)
  LEFT JOIN LATERAL (
    SELECT
      COUNT(*)::INT AS total,
      COUNT(*) FILTER (WHERE status = 'delivered')::INT AS completed,
      COUNT(*) FILTER (WHERE status = 'failed')::INT AS failed
    FROM public.deliveries del
    WHERE del.company_id = p_company_id
      AND (del.created_at AT TIME ZONE 'Africa/Monrovia')::DATE = d.day::DATE
  ) c ON true;

  RETURN jsonb_build_object('days', v_series);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_company_delivery_trend TO authenticated;
