-- DeliveryOS · workspace reports (RLS-safe aggregates)

CREATE OR REPLACE FUNCTION public.assert_company_member(p_company_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT (
    public.is_super_admin()
    OR p_company_id IN (SELECT public.user_company_ids())
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_workspace_report(
  p_company_id UUID,
  p_period TEXT DEFAULT 'day'
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_local TIMESTAMP;
  v_from TIMESTAMPTZ;
  v_to TIMESTAMPTZ;
  v_label TEXT;
  v_summary JSONB;
  v_riders JSONB;
BEGIN
  PERFORM public.assert_company_member(p_company_id);

  IF p_period NOT IN ('day', 'week', 'month') THEN
    RAISE EXCEPTION 'invalid period';
  END IF;

  v_local := (current_timestamp AT TIME ZONE 'Africa/Monrovia');

  IF p_period = 'week' THEN
    v_label := 'week';
    v_from := (date_trunc('day', v_local) - ((EXTRACT(ISODOW FROM v_local)::INT - 1) || ' days')::INTERVAL)
      AT TIME ZONE 'Africa/Monrovia';
    v_to := v_from + INTERVAL '7 days';
  ELSIF p_period = 'month' THEN
    v_label := 'month';
    v_from := (date_trunc('month', v_local) AT TIME ZONE 'Africa/Monrovia');
    v_to := v_from + INTERVAL '1 month';
  ELSE
    v_label := 'day';
    v_from := (date_trunc('day', v_local) AT TIME ZONE 'Africa/Monrovia');
    v_to := v_from + INTERVAL '1 day';
  END IF;

  SELECT jsonb_build_object(
    'period', v_label,
    'from', v_from,
    'to', v_to,
    'total', COUNT(*)::INT,
    'completed', COUNT(*) FILTER (WHERE status = 'delivered')::INT,
    'failed', COUNT(*) FILTER (WHERE status = 'failed')::INT,
    'cancelled', COUNT(*) FILTER (WHERE status = 'cancelled')::INT,
    'in_progress', COUNT(*) FILTER (
      WHERE status IN ('pending', 'assigned', 'accepted', 'picked_up', 'in_transit')
    )::INT,
    'cod_collected_lrd_cents', COALESCE(SUM(amount_to_collect_lrd_cents) FILTER (WHERE status = 'delivered'), 0)::INT,
    'delivery_fees_lrd_cents', COALESCE(SUM(delivery_fee_lrd_cents) FILTER (WHERE status = 'delivered'), 0)::INT,
    'avg_delivery_minutes', (
      SELECT (AVG(EXTRACT(EPOCH FROM (delivered_at - created_at)) / 60))::INT
      FROM public.deliveries d2
      WHERE d2.company_id = p_company_id
        AND d2.status = 'delivered'
        AND d2.delivered_at IS NOT NULL
        AND d2.created_at >= v_from
        AND d2.created_at < v_to
    )
  ) INTO v_summary
  FROM public.deliveries d
  WHERE d.company_id = p_company_id
    AND d.created_at >= v_from
    AND d.created_at < v_to;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'rider_code', rider_code,
        'full_name', full_name,
        'completed_deliveries', completed_deliveries,
        'rating', rating,
        'period_completed', period_completed
      )
      ORDER BY period_completed DESC
    ),
    '[]'::JSONB
  ) INTO v_riders
  FROM (
    SELECT
      r.rider_code,
      r.full_name,
      r.completed_deliveries,
      r.rating,
      COUNT(del.id) FILTER (WHERE del.status = 'delivered')::INT AS period_completed
    FROM public.riders r
    LEFT JOIN public.deliveries del ON del.rider_id = r.id
      AND del.created_at >= v_from
      AND del.created_at < v_to
    WHERE r.company_id = p_company_id
    GROUP BY r.id, r.rider_code, r.full_name, r.completed_deliveries, r.rating
    ORDER BY period_completed DESC
    LIMIT 5
  ) top;

  RETURN jsonb_build_object('summary', v_summary, 'top_riders', v_riders);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_workspace_report TO authenticated;
