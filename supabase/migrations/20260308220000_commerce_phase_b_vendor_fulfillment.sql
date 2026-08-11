-- DeliveryOS Commerce — Phase B: vendor order fulfillment RPCs.
--
-- Phase A deliberately left order fulfillment (accept/reject/preparing/
-- ready) unbuilt. This migration adds exactly those four transitions, with
-- a strict server-side state machine (no arbitrary jumps) and no bypass of
-- payment security.
--
-- Payment-gating decision (see the Phase B report for full context): Phase
-- A's commerce_order_payment_status has no client-reachable path to 'paid'
-- — mark_commerce_order_paid/mark_commerce_order_payment_failed are
-- REVOKE ALL FROM PUBLIC, reserved for the future MoMo webhook (Phase E).
-- Phase A's schema also defines no COD payment status or payment method
-- column at all. Per instruction, this migration does NOT invent a COD
-- state or otherwise bypass the payment_status='paid' requirement:
-- vendor_accept_commerce_order enforces it exactly as specified. The
-- practical consequence — no order can be accepted end-to-end until Phase
-- E ships, or until a COD design is explicitly approved — is intentional
-- and is called out prominently in the Phase B report, not hidden here.
-- Rejection does not require payment_status='paid' (declining an order,
-- paid or not, is never a value-granting action and needs no extra gate).

CREATE OR REPLACE FUNCTION public.assert_vendor_order_actor(p_company_id UUID)
RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type public.company_business_type;
BEGIN
  IF NOT public.has_company_role(p_company_id, ARRAY['company_owner', 'dispatcher', 'support_staff']::public.company_role[])
     AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  SELECT business_type INTO v_type FROM public.companies WHERE id = p_company_id;
  IF v_type NOT IN ('merchant', 'hybrid') THEN
    RAISE EXCEPTION 'not_a_vendor_company';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.assert_vendor_order_actor(UUID) FROM PUBLIC;

-- awaiting_vendor -> vendor_accepted (requires payment_status = 'paid')
CREATE OR REPLACE FUNCTION public.vendor_accept_commerce_order(p_order_id UUID)
RETURNS public.commerce_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.commerce_orders;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT * INTO v_order FROM public.commerce_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'order_not_found'; END IF;

  PERFORM public.assert_vendor_order_actor(v_order.vendor_company_id);

  IF v_order.fulfillment_status <> 'awaiting_vendor' THEN
    RAISE EXCEPTION 'invalid_fulfillment_state';
  END IF;
  IF v_order.payment_status <> 'paid' THEN
    RAISE EXCEPTION 'payment_not_confirmed';
  END IF;

  UPDATE public.commerce_orders SET fulfillment_status = 'vendor_accepted', updated_at = now()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  PERFORM public.log_audit_event(
    v_order.vendor_company_id, 'commerce_order_accepted', 'commerce_orders', v_order.id, to_jsonb(v_order)
  );

  RETURN v_order;
END;
$$;

GRANT EXECUTE ON FUNCTION public.vendor_accept_commerce_order TO authenticated;

-- awaiting_vendor -> vendor_rejected. Releases any reserved stock and, if
-- the order had somehow already been marked paid, flags refund_pending —
-- the same payment-status handling already used by
-- customer_cancel_commerce_order in Phase A, kept consistent here.
CREATE OR REPLACE FUNCTION public.vendor_reject_commerce_order(p_order_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS public.commerce_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.commerce_orders;
  v_item RECORD;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT * INTO v_order FROM public.commerce_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'order_not_found'; END IF;

  PERFORM public.assert_vendor_order_actor(v_order.vendor_company_id);

  IF v_order.fulfillment_status <> 'awaiting_vendor' THEN
    RAISE EXCEPTION 'invalid_fulfillment_state';
  END IF;

  FOR v_item IN
    SELECT oi.product_id, oi.quantity
    FROM public.commerce_order_items oi
    JOIN public.products p ON p.id = oi.product_id
    WHERE oi.order_id = v_order.id AND p.tracks_inventory = true
  LOOP
    UPDATE public.product_stock SET
      quantity_reserved = GREATEST(quantity_reserved - v_item.quantity, 0), updated_at = now()
    WHERE product_id = v_item.product_id;

    INSERT INTO public.product_stock_movements (
      product_id, company_id, quantity, movement_type, reference_type, reference_id, actor_user_id, notes
    ) VALUES (
      v_item.product_id, v_order.vendor_company_id, v_item.quantity, 'release', 'commerce_order', v_order.id, auth.uid(), 'vendor_rejected'
    );
  END LOOP;

  UPDATE public.commerce_orders SET
    fulfillment_status = 'vendor_rejected',
    payment_status = CASE WHEN payment_status = 'paid' THEN 'refund_pending' ELSE payment_status END,
    cancelled_at = now(),
    cancellation_reason = p_reason,
    updated_at = now()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  PERFORM public.log_audit_event(
    v_order.vendor_company_id, 'commerce_order_rejected', 'commerce_orders', v_order.id,
    jsonb_build_object('reason', p_reason)
  );

  RETURN v_order;
END;
$$;

GRANT EXECUTE ON FUNCTION public.vendor_reject_commerce_order TO authenticated;

-- vendor_accepted -> preparing
CREATE OR REPLACE FUNCTION public.vendor_mark_order_preparing(p_order_id UUID)
RETURNS public.commerce_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.commerce_orders;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT * INTO v_order FROM public.commerce_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'order_not_found'; END IF;

  PERFORM public.assert_vendor_order_actor(v_order.vendor_company_id);

  IF v_order.fulfillment_status <> 'vendor_accepted' THEN
    RAISE EXCEPTION 'invalid_fulfillment_state';
  END IF;

  UPDATE public.commerce_orders SET fulfillment_status = 'preparing', updated_at = now()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  RETURN v_order;
END;
$$;

GRANT EXECUTE ON FUNCTION public.vendor_mark_order_preparing TO authenticated;

-- preparing -> ready_for_pickup
CREATE OR REPLACE FUNCTION public.vendor_mark_order_ready(p_order_id UUID)
RETURNS public.commerce_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.commerce_orders;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT * INTO v_order FROM public.commerce_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'order_not_found'; END IF;

  PERFORM public.assert_vendor_order_actor(v_order.vendor_company_id);

  IF v_order.fulfillment_status <> 'preparing' THEN
    RAISE EXCEPTION 'invalid_fulfillment_state';
  END IF;

  UPDATE public.commerce_orders SET fulfillment_status = 'ready_for_pickup', updated_at = now()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  RETURN v_order;
END;
$$;

GRANT EXECUTE ON FUNCTION public.vendor_mark_order_ready TO authenticated;

-- ---------------------------------------------------------------------------
-- Vendor order inbox listing (paginated, tab/status-filterable) — mirrors
-- list_marketplace_jobs_page/list_delivery_requests_page's {total, rows}
-- shape. Reads only from commerce_orders/commerce_order_items (frozen
-- snapshots) and the linked delivery's status, never live product pricing.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_vendor_commerce_orders_page(
  p_vendor_company_id UUID,
  p_fulfillment_statuses TEXT[] DEFAULT NULL,
  p_limit INT DEFAULT 25,
  p_offset INT DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total INT;
  v_rows JSONB;
BEGIN
  PERFORM public.assert_vendor_order_actor(p_vendor_company_id);

  SELECT COUNT(*)::INT INTO v_total
  FROM public.commerce_orders o
  WHERE o.vendor_company_id = p_vendor_company_id
    AND (p_fulfillment_statuses IS NULL OR o.fulfillment_status::TEXT = ANY(p_fulfillment_statuses));

  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::JSONB) INTO v_rows
  FROM (
    SELECT
      o.*,
      (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'id', oi.id, 'product_name', oi.product_name, 'unit_price_lrd_cents', oi.unit_price_lrd_cents,
          'quantity', oi.quantity, 'selected_options', oi.selected_options, 'line_total_lrd_cents', oi.line_total_lrd_cents
        ) ORDER BY oi.created_at), '[]'::JSONB)
        FROM public.commerce_order_items oi WHERE oi.order_id = o.id
      ) AS items,
      d.status AS delivery_status
    FROM public.commerce_orders o
    LEFT JOIN public.deliveries d ON d.id = o.delivery_id
    WHERE o.vendor_company_id = p_vendor_company_id
      AND (p_fulfillment_statuses IS NULL OR o.fulfillment_status::TEXT = ANY(p_fulfillment_statuses))
    ORDER BY o.created_at DESC
    LIMIT LEAST(GREATEST(p_limit, 1), 100)
    OFFSET GREATEST(p_offset, 0)
  ) t;

  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_vendor_commerce_orders_page TO authenticated;

-- ---------------------------------------------------------------------------
-- Vendor overview metrics — real counts only, no GMV/revenue (finance/
-- payments are not built yet). Mirrors get_marketplace_analytics'
-- honesty discipline: every number here is a COUNT of real rows.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_vendor_commerce_overview(p_vendor_company_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_store public.store_profiles;
  v_new_orders INT;
  v_preparing INT;
  v_ready INT;
  v_completed INT;
  v_cancelled INT;
  v_product_count INT;
  v_out_of_stock INT;
  v_low_stock INT;
BEGIN
  PERFORM public.assert_vendor_order_actor(p_vendor_company_id);

  SELECT * INTO v_store FROM public.store_profiles WHERE company_id = p_vendor_company_id;

  SELECT COUNT(*)::INT INTO v_new_orders
  FROM public.commerce_orders WHERE vendor_company_id = p_vendor_company_id AND fulfillment_status = 'awaiting_vendor';

  SELECT COUNT(*)::INT INTO v_preparing
  FROM public.commerce_orders WHERE vendor_company_id = p_vendor_company_id
    AND fulfillment_status IN ('vendor_accepted', 'preparing');

  SELECT COUNT(*)::INT INTO v_ready
  FROM public.commerce_orders WHERE vendor_company_id = p_vendor_company_id AND fulfillment_status = 'ready_for_pickup';

  SELECT COUNT(*)::INT INTO v_completed
  FROM public.commerce_orders WHERE vendor_company_id = p_vendor_company_id AND fulfillment_status = 'completed';

  SELECT COUNT(*)::INT INTO v_cancelled
  FROM public.commerce_orders WHERE vendor_company_id = p_vendor_company_id
    AND fulfillment_status IN ('vendor_rejected', 'cancelled');

  SELECT COUNT(*)::INT INTO v_product_count
  FROM public.products WHERE company_id = p_vendor_company_id;

  SELECT COUNT(*)::INT INTO v_out_of_stock
  FROM public.products p
  JOIN public.product_stock s ON s.product_id = p.id
  WHERE p.company_id = p_vendor_company_id AND p.tracks_inventory = true
    AND (s.quantity_on_hand - s.quantity_reserved) <= 0;

  SELECT COUNT(*)::INT INTO v_low_stock
  FROM public.products p
  JOIN public.product_stock s ON s.product_id = p.id
  WHERE p.company_id = p_vendor_company_id AND p.tracks_inventory = true
    AND (s.quantity_on_hand - s.quantity_reserved) > 0
    AND (s.quantity_on_hand - s.quantity_reserved) <= 5;

  RETURN jsonb_build_object(
    'store', to_jsonb(v_store),
    'orders', jsonb_build_object(
      'new', v_new_orders,
      'preparing', v_preparing,
      'ready_for_pickup', v_ready,
      'completed', v_completed,
      'cancelled', v_cancelled
    ),
    'catalog', jsonb_build_object(
      'product_count', v_product_count,
      'out_of_stock', v_out_of_stock,
      'low_stock', v_low_stock
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_vendor_commerce_overview TO authenticated;
