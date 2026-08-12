-- DeliveryOS Commerce — Phase F: End-to-End Production Readiness,
-- Operations Hardening & Gap Closure.
--
-- This migration does NOT redesign anything already built (Commerce order
-- state machine, delivery/rider engine, E1 ledger/settlement model, SMS
-- queue). It closes real, audited gaps discovered by re-tracing the full
-- COD lifecycle end-to-end before real MoMo money is connected:
--
--   1. Stock leak: a delivery that fails/is cancelled after
--      ready_for_pickup/handed_to_carrier flips the order to 'cancelled'
--      but never released the reserved stock — every OTHER cancellation
--      path (vendor reject, customer cancel, payment failure) already
--      does this; this was the one gap. Fixed in
--      trg_sync_commerce_order_fulfillment_from_delivery.
--   2. Finance read-RPC correctness: get_vendor_commerce_finance /
--      get_carrier_commerce_finance / get_admin_commerce_finance_overview
--      summed 'cod_collected' credits without ever netting a later
--      'reversal' event's offsetting debit entries. Not reachable via
--      COD alone today (reverse_commerce_order_financials' two callers
--      both require fulfillment_status='awaiting_vendor', which a COD
--      order can never be in once paid — see the E1 migration's own
--      comment), but it is a real latent correctness bug in the
--      aggregation formula that must not survive into the moment MoMo
--      pre-payment makes the reversal path reachable. Fixed by excluding
--      reversed orders from snapshot-based sums and netting credit/debit
--      ledger sums instead of summing credits alone.
--   3. Super Admin operational blind spots: no view of Commerce order
--      status/stuck orders, no carrier pricing-configuration visibility,
--      no paid-but-unrecognized reconciliation check, admin finance date/
--      vendor/carrier filters existed in the RPC but were never callable
--      with real filter arguments from anywhere admin-facing.
--   4. Vendor onboarding: get_company_onboarding_status never gained
--      Commerce-specific steps (store profile, first product, submit for
--      review) for merchant/hybrid companies.
--   5. Zero Commerce lifecycle SMS notifications existed (explicitly
--      deferred by a comment in the Phase A migration) — this wires the
--      highest-value ones through the EXISTING queue_outbound_sms/
--      sms_outbox/sms-dispatch path. Rider-assignment and pickup/transit/
--      delivered customer SMS already fire today because Commerce
--      deliveries reuse the same `deliveries` table as B2B — left as-is,
--      not duplicated.
--   6. store_profiles column-level exposure: Phase C's own header comment
--      already documented that `authenticated` (not just anon) could read
--      another store's status_reason/reviewed_by/reviewed_at via a raw
--      PostgREST column selection, because Postgres column grants aren't
--      row-aware. Closing it now by routing the vendor's own read through
--      a company-scoped RPC and revoking those columns from `authenticated`
--      too.
--
-- Product decisions made after the initial Phase F report, applied in this
-- same migration (still a draft at the time, so folded in directly rather
-- than as a separate migration):
--   - commerce_enabled IS now enforced server-side — see section 7 below.
--   - New merchant owners now land on /vendor (Commerce), not
--     /merchant/requests — see src/lib/post-auth-navigation.ts. B2B
--     delivery-request functionality is untouched and still reachable
--     from the sidebar.
--   - Vendor non-response cancellation remains MANUAL, intentionally.
--     awaiting_vendor orders have no automatic timeout; a customer can
--     self-cancel while still in that state (see customer_cancel_
--     commerce_order), but nothing auto-cancels an order the vendor never
--     acts on. This is a deliberate current business policy, not an
--     oversight — revisit if/when a vendor-response SLA is defined.
--   - Real geo-distance carrier matching remains explicitly deferred.
--     delivery_zones is a per-company label with a flat fee, not a
--     geographic boundary, and request_commerce_order_delivery never sets
--     zone_id on Commerce delivery_requests, so matching today is purely
--     eligibility-based. Preferred future direction: real coordinate-based
--     distance matching using the pickup/destination latitude/longitude
--     already captured on delivery_requests/deliveries but never read by
--     any matching function — not pretending the existing delivery_zones
--     rows are geographic boundaries, which they are not.
--
-- Still explicitly NOT done here: MTN MoMo / Orange Money / Tola
-- integration.

-- =============================================================================
-- 1) Stock leak fix: release reserved stock when a delivery fails/cancels
--    after the order has already moved past vendor acceptance.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.trg_sync_commerce_order_fulfillment_from_delivery()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_updated_rows INT;
  v_item RECORD;
  v_order public.commerce_orders;
BEGIN
  IF NEW.commerce_order_id IS NULL OR OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;

  IF NEW.status = 'picked_up' THEN
    UPDATE public.commerce_orders SET fulfillment_status = 'handed_to_carrier', updated_at = now()
    WHERE id = NEW.commerce_order_id AND fulfillment_status = 'ready_for_pickup';

  ELSIF NEW.status = 'delivered' THEN
    UPDATE public.commerce_orders SET fulfillment_status = 'completed', updated_at = now()
    WHERE id = NEW.commerce_order_id AND fulfillment_status IN ('ready_for_pickup', 'handed_to_carrier')
    RETURNING * INTO v_order;

    GET DIAGNOSTICS v_updated_rows = ROW_COUNT;
    IF v_updated_rows > 0 THEN
      PERFORM public.notify_vendor_commerce_delivery_completed(v_order);
    END IF;

  ELSIF NEW.status IN ('failed', 'cancelled') THEN
    UPDATE public.commerce_orders SET
      fulfillment_status = 'cancelled',
      cancellation_reason = COALESCE(cancellation_reason, 'delivery_' || NEW.status),
      cancelled_at = now(),
      updated_at = now()
    WHERE id = NEW.commerce_order_id AND fulfillment_status IN ('ready_for_pickup', 'handed_to_carrier');

    GET DIAGNOSTICS v_updated_rows = ROW_COUNT;

    -- Every OTHER cancellation path (vendor reject, customer cancel,
    -- payment failure) already releases reserved stock; a delivery
    -- failing/being cancelled at this later stage was the one gap — stock
    -- reserved at checkout would otherwise never be freed again, since
    -- COD payment_status is still 'pending_payment' here (COD only becomes
    -- 'paid' at the 'delivered' transition, which is mutually exclusive
    -- with this branch), so mark_commerce_order_paid's own stock-decrement
    -- can never run for this order either.
    IF v_updated_rows > 0 THEN
      FOR v_item IN
        SELECT oi.product_id, oi.quantity, o.vendor_company_id
        FROM public.commerce_order_items oi
        JOIN public.products p ON p.id = oi.product_id
        JOIN public.commerce_orders o ON o.id = oi.order_id
        WHERE oi.order_id = NEW.commerce_order_id AND p.tracks_inventory = true
      LOOP
        UPDATE public.product_stock SET
          quantity_reserved = GREATEST(quantity_reserved - v_item.quantity, 0), updated_at = now()
        WHERE product_id = v_item.product_id;

        INSERT INTO public.product_stock_movements (
          product_id, company_id, quantity, movement_type, reference_type, reference_id, notes
        ) VALUES (
          v_item.product_id, v_item.vendor_company_id, v_item.quantity, 'release', 'commerce_order',
          NEW.commerce_order_id, 'delivery_' || NEW.status
        );
      END LOOP;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- =============================================================================
-- 2) Commerce lifecycle SMS notifications — reuse the existing
--    queue_outbound_sms / sms_outbox / sms-dispatch path exactly as-is.
--    queue_outbound_sms already returns boolean (never raises) on missing
--    phone/body or zero allowance, so a PERFORM here can never fail the
--    surrounding business transaction if SMS is unavailable/out of credit.
--    Idempotency: every call site below sits inside an RPC that already
--    guards a one-way fulfillment_status transition with a precondition
--    check (e.g. "fulfillment_status <> 'awaiting_vendor' THEN RAISE") —
--    a retried call hits that guard and raises before ever reaching the
--    notify call a second time, the same mechanism that already protects
--    financial recognition and rider-assignment SMS from duplication in
--    this codebase, not a new/weaker idempotency story.
-- =============================================================================

-- Vendor: new order. Charged to the vendor's own company — they are the
-- one who benefits from being notified promptly of their own new order.
CREATE OR REPLACE FUNCTION public.notify_vendor_new_commerce_order(p_order public.commerce_orders)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_phone TEXT;
  v_body TEXT;
BEGIN
  SELECT phone INTO v_phone FROM public.companies WHERE id = p_order.vendor_company_id;
  IF v_phone IS NULL OR v_phone = '' THEN RETURN; END IF;
  v_body := format(
    E'New DeliveryOS order #%s from %s. Total LRD %s. Open your vendor dashboard to accept.',
    p_order.order_number, COALESCE(p_order.customer_name, 'a customer'),
    to_char(p_order.total_lrd_cents / 100.0, 'FM999999990.00')
  );
  PERFORM public.queue_outbound_sms(p_order.vendor_company_id, v_phone, v_body, NULL);
END;
$$;

-- Customer: order accepted / rejected / ready. Charged to the vendor's
-- company — it is the vendor's own operational action driving each of
-- these, mirroring "the company whose action causes the event pays"
-- already established for rider-assignment SMS.
CREATE OR REPLACE FUNCTION public.notify_customer_commerce_order(p_order public.commerce_orders, p_body TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_order.customer_phone IS NULL OR p_order.customer_phone = '' THEN RETURN; END IF;
  PERFORM public.queue_outbound_sms(p_order.vendor_company_id, p_order.customer_phone, p_body, p_order.delivery_id);
END;
$$;

-- Vendor: delivery completed. Charged to the vendor's own company.
CREATE OR REPLACE FUNCTION public.notify_vendor_commerce_delivery_completed(p_order public.commerce_orders)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_phone TEXT;
  v_body TEXT;
BEGIN
  SELECT phone INTO v_phone FROM public.companies WHERE id = p_order.vendor_company_id;
  IF v_phone IS NULL OR v_phone = '' THEN RETURN; END IF;
  v_body := format(E'Order #%s has been delivered.', p_order.order_number);
  PERFORM public.queue_outbound_sms(p_order.vendor_company_id, v_phone, v_body, p_order.delivery_id);
END;
$$;

REVOKE ALL ON FUNCTION public.notify_vendor_new_commerce_order(public.commerce_orders) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.notify_customer_commerce_order(public.commerce_orders, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.notify_vendor_commerce_delivery_completed(public.commerce_orders) FROM PUBLIC;

-- submit_commerce_order: identical body to the Phase B.5 version, plus one
-- notify call at the end. Same 8-parameter signature — plain CREATE OR
-- REPLACE is safe (no DROP needed, unlike Phase B.5's own note about
-- changing parameter COUNT).
CREATE OR REPLACE FUNCTION public.submit_commerce_order(
  p_cart_id UUID,
  p_customer_name TEXT,
  p_delivery_address TEXT DEFAULT NULL,
  p_delivery_area_summary TEXT DEFAULT NULL,
  p_delivery_latitude DOUBLE PRECISION DEFAULT NULL,
  p_delivery_longitude DOUBLE PRECISION DEFAULT NULL,
  p_delivery_instructions TEXT DEFAULT NULL,
  p_payment_method TEXT DEFAULT 'cod'
)
RETURNS public.commerce_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_phone_confirmed TIMESTAMPTZ;
  v_auth_phone TEXT;
  v_cart public.carts;
  v_item RECORD;
  v_product public.products;
  v_stock public.product_stock;
  v_available NUMERIC;
  v_option_delta INT;
  v_option_snapshot JSONB;
  v_unit_price INT;
  v_line_total INT;
  v_subtotal INT := 0;
  v_order public.commerce_orders;
  v_payment_method public.commerce_payment_method;
  v_allow_cod BOOLEAN;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT phone, phone_confirmed_at INTO v_auth_phone, v_phone_confirmed
  FROM auth.users WHERE id = auth.uid();
  IF v_phone_confirmed IS NULL THEN
    RAISE EXCEPTION 'phone_not_verified';
  END IF;

  SELECT * INTO v_cart FROM public.carts WHERE id = p_cart_id AND customer_id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'cart_not_found';
  END IF;
  IF v_cart.status <> 'open' THEN
    RAISE EXCEPTION 'cart_not_open';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.cart_items WHERE cart_id = v_cart.id) THEN
    RAISE EXCEPTION 'cart_empty';
  END IF;
  IF NOT public.store_is_publicly_visible(v_cart.vendor_company_id) THEN
    RAISE EXCEPTION 'vendor_not_available';
  END IF;
  IF NOT public.can_use_feature(v_cart.vendor_company_id, 'commerce_enabled') THEN
    RAISE EXCEPTION 'commerce_not_enabled';
  END IF;

  IF p_payment_method NOT IN ('cod', 'mtn_momo', 'orange_money') THEN
    RAISE EXCEPTION 'invalid_payment_method';
  END IF;
  IF p_payment_method <> 'cod' THEN
    RAISE EXCEPTION 'payment_method_not_available';
  END IF;
  v_payment_method := p_payment_method::public.commerce_payment_method;

  SELECT allow_cash_on_delivery INTO v_allow_cod
  FROM public.store_profiles WHERE company_id = v_cart.vendor_company_id;
  IF v_payment_method = 'cod' AND NOT COALESCE(v_allow_cod, false) THEN
    RAISE EXCEPTION 'cod_not_allowed';
  END IF;

  INSERT INTO public.commerce_orders (
    customer_id, vendor_company_id, cart_id, customer_name, customer_phone,
    delivery_address, delivery_area_summary, delivery_latitude, delivery_longitude, delivery_instructions,
    payment_method
  ) VALUES (
    auth.uid(), v_cart.vendor_company_id, v_cart.id,
    NULLIF(trim(p_customer_name), ''), public.normalize_phone_lr(v_auth_phone),
    p_delivery_address, p_delivery_area_summary, p_delivery_latitude, p_delivery_longitude, p_delivery_instructions,
    v_payment_method
  )
  RETURNING * INTO v_order;

  IF v_order.customer_name IS NULL THEN
    RAISE EXCEPTION 'customer_name_required';
  END IF;

  FOR v_item IN SELECT * FROM public.cart_items WHERE cart_id = v_cart.id LOOP
    SELECT * INTO v_product FROM public.products WHERE id = v_item.product_id;
    IF NOT FOUND OR v_product.status <> 'active' OR v_product.company_id <> v_cart.vendor_company_id THEN
      RAISE EXCEPTION 'product_not_available';
    END IF;

    PERFORM public.assert_valid_product_options(v_product.id, v_item.selected_options);

    v_unit_price := v_product.price_lrd_cents;
    v_option_snapshot := '[]'::JSONB;

    IF COALESCE(jsonb_array_length(v_item.selected_options), 0) > 0 THEN
      SELECT COALESCE(SUM(po.price_delta_lrd_cents), 0),
             COALESCE(jsonb_agg(jsonb_build_object('name', po.name, 'price_delta_lrd_cents', po.price_delta_lrd_cents)), '[]'::JSONB)
      INTO v_option_delta, v_option_snapshot
      FROM public.product_options po
      WHERE po.id IN (SELECT (jsonb_array_elements_text(v_item.selected_options))::UUID);

      v_unit_price := v_unit_price + COALESCE(v_option_delta, 0);
    END IF;

    v_line_total := v_unit_price * v_item.quantity;
    v_subtotal := v_subtotal + v_line_total;

    INSERT INTO public.commerce_order_items (
      order_id, product_id, product_name, unit_price_lrd_cents, quantity, selected_options, line_total_lrd_cents
    ) VALUES (
      v_order.id, v_product.id, v_product.name, v_unit_price, v_item.quantity, v_option_snapshot, v_line_total
    );

    IF v_product.tracks_inventory THEN
      SELECT * INTO v_stock FROM public.product_stock WHERE product_id = v_product.id FOR UPDATE;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'stock_not_configured';
      END IF;
      v_available := v_stock.quantity_on_hand - v_stock.quantity_reserved;
      IF v_available < v_item.quantity THEN
        RAISE EXCEPTION 'insufficient_stock';
      END IF;

      UPDATE public.product_stock SET
        quantity_reserved = quantity_reserved + v_item.quantity, updated_at = now()
      WHERE product_id = v_product.id;

      INSERT INTO public.product_stock_movements (
        product_id, company_id, quantity, movement_type, reference_type, reference_id, actor_user_id
      ) VALUES (
        v_product.id, v_cart.vendor_company_id, v_item.quantity, 'reservation', 'commerce_order', v_order.id, auth.uid()
      );
    END IF;
  END LOOP;

  UPDATE public.commerce_orders SET
    subtotal_lrd_cents = v_subtotal,
    total_lrd_cents = v_subtotal + delivery_fee_lrd_cents
  WHERE id = v_order.id
  RETURNING * INTO v_order;

  UPDATE public.carts SET status = 'converted', updated_at = now() WHERE id = v_cart.id;

  PERFORM public.notify_vendor_new_commerce_order(v_order);

  RETURN v_order;
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_commerce_order TO authenticated;

-- vendor_accept_commerce_order: identical body to the Phase B.5 version,
-- plus a customer notification.
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
  IF NOT public.commerce_order_payment_eligible_for_acceptance(v_order.id) THEN
    RAISE EXCEPTION 'payment_not_confirmed';
  END IF;

  UPDATE public.commerce_orders SET fulfillment_status = 'vendor_accepted', updated_at = now()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  PERFORM public.log_audit_event(
    v_order.vendor_company_id, 'commerce_order_accepted', 'commerce_orders', v_order.id, to_jsonb(v_order)
  );

  PERFORM public.notify_customer_commerce_order(
    v_order, format(E'Your DeliveryOS order #%s has been accepted and is being prepared.', v_order.order_number)
  );

  RETURN v_order;
END;
$$;

GRANT EXECUTE ON FUNCTION public.vendor_accept_commerce_order TO authenticated;

-- vendor_reject_commerce_order: identical body to the E1 version (which
-- already added the stock release + reversal wiring), plus a customer
-- notification.
CREATE OR REPLACE FUNCTION public.vendor_reject_commerce_order(p_order_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS public.commerce_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.commerce_orders;
  v_item RECORD;
  v_was_paid BOOLEAN;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT * INTO v_order FROM public.commerce_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'order_not_found'; END IF;

  PERFORM public.assert_vendor_order_actor(v_order.vendor_company_id);

  IF v_order.fulfillment_status <> 'awaiting_vendor' THEN
    RAISE EXCEPTION 'invalid_fulfillment_state';
  END IF;

  v_was_paid := (v_order.payment_status = 'paid');

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

  IF v_was_paid THEN
    PERFORM public.reverse_commerce_order_financials(v_order.id, 'vendor_rejected_after_payment');
  END IF;

  PERFORM public.log_audit_event(
    v_order.vendor_company_id, 'commerce_order_rejected', 'commerce_orders', v_order.id,
    jsonb_build_object('reason', p_reason)
  );

  PERFORM public.notify_customer_commerce_order(
    v_order, format(E'Your DeliveryOS order #%s could not be accepted by the store.', v_order.order_number)
  );

  RETURN v_order;
END;
$$;

GRANT EXECUTE ON FUNCTION public.vendor_reject_commerce_order TO authenticated;

-- vendor_mark_order_ready: identical body to the Phase B version, plus a
-- customer notification.
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

  PERFORM public.notify_customer_commerce_order(
    v_order, format(E'Your DeliveryOS order #%s is ready and waiting for a carrier.', v_order.order_number)
  );

  RETURN v_order;
END;
$$;

GRANT EXECUTE ON FUNCTION public.vendor_mark_order_ready TO authenticated;

-- accept_marketplace_offer: identical body to the Phase D version, plus a
-- customer notification for the Commerce-specific branch only (B2B
-- delivery-request flow, where v_commerce_order.id IS NULL, is untouched).
-- Charged to the CARRIER's company, not the vendor's — it is the
-- carrier's own action causing the need to inform the customer.
CREATE OR REPLACE FUNCTION public.accept_marketplace_offer(
  p_offer_id UUID,
  p_provider_company_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_offer public.delivery_offers;
  v_req public.delivery_requests;
  v_delivery public.deliveries;
  v_merchant_name TEXT;
  v_fee RECORD;
  v_tx public.marketplace_transactions;
  v_commerce_order public.commerce_orders;
  v_amount_to_collect INT;
BEGIN
  PERFORM public.assert_provider_marketplace(p_provider_company_id);
  IF NOT public.has_company_role(p_provider_company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[]) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT * INTO v_offer FROM public.delivery_offers
  WHERE id = p_offer_id AND provider_company_id = p_provider_company_id
  FOR UPDATE;

  IF NOT FOUND OR v_offer.status <> 'pending' THEN
    RAISE EXCEPTION 'invalid_offer';
  END IF;

  SELECT * INTO v_req FROM public.delivery_requests WHERE id = v_offer.delivery_request_id FOR UPDATE;
  IF v_req.status NOT IN ('open', 'offered') THEN
    RAISE EXCEPTION 'request_not_available';
  END IF;

  SELECT * INTO v_commerce_order FROM public.commerce_orders WHERE delivery_request_id = v_req.id FOR UPDATE;
  IF v_commerce_order.id IS NOT NULL AND v_offer.selected_by_customer_at IS NULL THEN
    RAISE EXCEPTION 'offer_not_selected_by_customer';
  END IF;

  UPDATE public.delivery_offers SET status = 'accepted', accepted_at = now() WHERE id = p_offer_id;

  UPDATE public.delivery_offers SET status = 'expired'
  WHERE delivery_request_id = v_req.id AND id <> p_offer_id AND status = 'pending';

  UPDATE public.delivery_requests SET
    status = 'accepted',
    selected_provider_id = p_provider_company_id,
    quoted_amount_lrd_cents = v_offer.quoted_amount_lrd_cents,
    accepted_at = now()
  WHERE id = v_req.id
  RETURNING * INTO v_req;

  SELECT name INTO v_merchant_name FROM public.companies WHERE id = v_req.merchant_company_id;

  v_amount_to_collect := CASE
    WHEN v_commerce_order.id IS NOT NULL THEN v_commerce_order.subtotal_lrd_cents + v_offer.quoted_amount_lrd_cents
    ELSE v_req.cod_amount_lrd_cents
  END;

  INSERT INTO public.deliveries (
    company_id, merchant_company_id, delivery_request_id,
    tracking_code, pickup_business_name, pickup_address,
    customer_id, customer_name, customer_phone, destination_address,
    package_description, amount_to_collect_lrd_cents, delivery_fee_lrd_cents,
    delivery_zone_id, status, created_by, commerce_order_id
  ) VALUES (
    p_provider_company_id, v_req.merchant_company_id, v_req.id,
    public.generate_tracking_code(),
    COALESCE(v_merchant_name, 'Merchant pickup'),
    v_req.pickup_address,
    v_req.customer_id,
    COALESCE(v_req.customer_name, 'Customer'),
    COALESCE(v_req.customer_phone, ''),
    v_req.destination_address,
    v_req.package_description,
    v_amount_to_collect,
    v_offer.quoted_amount_lrd_cents,
    v_req.zone_id,
    'pending',
    auth.uid(),
    v_commerce_order.id
  )
  RETURNING * INTO v_delivery;

  UPDATE public.delivery_requests SET status = 'converted', converted_delivery_id = v_delivery.id WHERE id = v_req.id;

  IF v_commerce_order.id IS NOT NULL THEN
    UPDATE public.commerce_orders SET
      delivery_id = v_delivery.id,
      delivery_fee_lrd_cents = v_offer.quoted_amount_lrd_cents,
      total_lrd_cents = subtotal_lrd_cents + v_offer.quoted_amount_lrd_cents,
      updated_at = now()
    WHERE id = v_commerce_order.id
    RETURNING * INTO v_commerce_order;

    IF v_commerce_order.customer_phone IS NOT NULL AND v_commerce_order.customer_phone <> '' THEN
      PERFORM public.queue_outbound_sms(
        p_provider_company_id, v_commerce_order.customer_phone,
        format(E'A carrier has accepted your DeliveryOS order #%s. You will be notified when it is picked up.', v_commerce_order.order_number),
        v_delivery.id
      );
    END IF;
  END IF;

  SELECT * INTO v_fee FROM public.compute_marketplace_fee_split(
    v_offer.quoted_amount_lrd_cents, v_req.merchant_company_id, p_provider_company_id
  );

  INSERT INTO public.marketplace_transactions (
    delivery_request_id, merchant_company_id, provider_company_id, delivery_id,
    gross_amount_lrd_cents, platform_fee_lrd_cents, provider_amount_lrd_cents, status
  ) VALUES (
    v_req.id, v_req.merchant_company_id, p_provider_company_id, v_delivery.id,
    v_offer.quoted_amount_lrd_cents, v_fee.platform_fee_lrd_cents, v_fee.provider_amount_lrd_cents, 'pending'
  )
  RETURNING * INTO v_tx;

  INSERT INTO public.marketplace_ledger_entries (company_id, account_type, marketplace_transaction_id, amount_lrd_cents, description)
  VALUES
    (v_req.merchant_company_id, 'merchant_payable', v_tx.id, v_offer.quoted_amount_lrd_cents, 'Marketplace delivery accepted'),
    (p_provider_company_id, 'provider_receivable', v_tx.id, v_fee.provider_amount_lrd_cents, 'Provider earnings'),
    (NULL, 'platform_revenue', v_tx.id, v_fee.platform_fee_lrd_cents, 'Platform fee');

  PERFORM public.enqueue_webhook_event(v_req.merchant_company_id, 'delivery_request.accepted', v_req.id,
    jsonb_build_object('request', to_jsonb(v_req), 'delivery_id', v_delivery.id));
  PERFORM public.enqueue_webhook_event(p_provider_company_id, 'marketplace_job.accepted', v_req.id,
    jsonb_build_object('delivery_id', v_delivery.id));
  PERFORM public.enqueue_webhook_event(v_req.merchant_company_id, 'marketplace.offer.accepted', v_offer.id, to_jsonb(v_offer));

  RETURN jsonb_build_object('delivery_request', to_jsonb(v_req), 'delivery', to_jsonb(v_delivery), 'transaction', to_jsonb(v_tx));
END;
$$;

GRANT EXECUTE ON FUNCTION public.accept_marketplace_offer TO authenticated;

-- =============================================================================
-- 3) Finance read-RPC correctness: exclude reversed orders from snapshot-
--    based aggregates, and net credit/debit ledger sums instead of summing
--    credit entries alone (a reversal's offsetting debit entry otherwise
--    stays invisible to every "how much is owed/earned" calculation).
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_vendor_commerce_finance(p_vendor_company_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gross INT; v_fees INT; v_net INT; v_settled INT; v_pending INT;
  v_orders JSONB;
BEGIN
  PERFORM public.assert_vendor_order_actor(p_vendor_company_id, false);

  SELECT
    COALESCE(SUM((snapshot ->> 'vendor_gross_lrd_cents')::INT), 0),
    COALESCE(SUM((snapshot ->> 'vendor_platform_fee_lrd_cents')::INT), 0),
    COALESCE(SUM((snapshot ->> 'vendor_net_lrd_cents')::INT), 0)
  INTO v_gross, v_fees, v_net
  FROM public.commerce_financial_events e
  JOIN public.commerce_orders o ON o.id = e.commerce_order_id
  WHERE o.vendor_company_id = p_vendor_company_id AND e.event_type = 'cod_collected'
    AND NOT EXISTS (
      SELECT 1 FROM public.commerce_financial_events r
      WHERE r.commerce_order_id = e.commerce_order_id AND r.event_type = 'reversal'
    );

  SELECT
    COALESCE(SUM(amount_lrd_cents) FILTER (WHERE direction = 'credit' AND settlement_id IS NOT NULL), 0)
      - COALESCE(SUM(amount_lrd_cents) FILTER (WHERE direction = 'debit' AND settlement_id IS NOT NULL), 0),
    COALESCE(SUM(amount_lrd_cents) FILTER (WHERE direction = 'credit' AND settlement_id IS NULL), 0)
      - COALESCE(SUM(amount_lrd_cents) FILTER (WHERE direction = 'debit' AND settlement_id IS NULL), 0)
  INTO v_settled, v_pending
  FROM public.commerce_ledger_entries
  WHERE company_id = p_vendor_company_id AND account_type = 'vendor_payable';

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'order_id', o.id, 'order_number', o.order_number,
    'vendor_gross_lrd_cents', (e.snapshot ->> 'vendor_gross_lrd_cents')::INT,
    'vendor_platform_fee_lrd_cents', (e.snapshot ->> 'vendor_platform_fee_lrd_cents')::INT,
    'vendor_net_lrd_cents', (e.snapshot ->> 'vendor_net_lrd_cents')::INT,
    'recognized_at', e.created_at
  ) ORDER BY e.created_at DESC), '[]'::JSONB)
  INTO v_orders
  FROM public.commerce_financial_events e
  JOIN public.commerce_orders o ON o.id = e.commerce_order_id
  WHERE o.vendor_company_id = p_vendor_company_id AND e.event_type = 'cod_collected'
    AND NOT EXISTS (
      SELECT 1 FROM public.commerce_financial_events r
      WHERE r.commerce_order_id = e.commerce_order_id AND r.event_type = 'reversal'
    )
  LIMIT 100;

  RETURN jsonb_build_object(
    'vendor_gross_lrd_cents', v_gross,
    'platform_fees_lrd_cents', v_fees,
    'net_earnings_lrd_cents', v_net,
    'settled_lrd_cents', v_settled,
    'pending_settlement_lrd_cents', v_pending,
    'orders', v_orders
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_vendor_commerce_finance(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_vendor_commerce_finance(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_carrier_commerce_finance(p_carrier_company_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gross INT; v_fees INT; v_net INT; v_settled INT; v_pending INT;
  v_deliveries JSONB;
BEGIN
  IF NOT public.has_company_role(p_carrier_company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[])
     AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT
    COALESCE(SUM((snapshot ->> 'carrier_gross_lrd_cents')::INT), 0),
    COALESCE(SUM((snapshot ->> 'carrier_platform_fee_lrd_cents')::INT), 0),
    COALESCE(SUM((snapshot ->> 'carrier_net_lrd_cents')::INT), 0)
  INTO v_gross, v_fees, v_net
  FROM public.commerce_financial_events e
  JOIN public.deliveries d ON d.id = e.delivery_id
  WHERE d.company_id = p_carrier_company_id AND e.event_type = 'cod_collected'
    AND NOT EXISTS (
      SELECT 1 FROM public.commerce_financial_events r
      WHERE r.commerce_order_id = e.commerce_order_id AND r.event_type = 'reversal'
    );

  SELECT
    COALESCE(SUM(amount_lrd_cents) FILTER (WHERE direction = 'credit' AND settlement_id IS NOT NULL), 0)
      - COALESCE(SUM(amount_lrd_cents) FILTER (WHERE direction = 'debit' AND settlement_id IS NOT NULL), 0),
    COALESCE(SUM(amount_lrd_cents) FILTER (WHERE direction = 'credit' AND settlement_id IS NULL), 0)
      - COALESCE(SUM(amount_lrd_cents) FILTER (WHERE direction = 'debit' AND settlement_id IS NULL), 0)
  INTO v_settled, v_pending
  FROM public.commerce_ledger_entries
  WHERE company_id = p_carrier_company_id AND account_type = 'carrier_payable';

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'delivery_id', d.id, 'tracking_code', d.tracking_code,
    'carrier_gross_lrd_cents', (e.snapshot ->> 'carrier_gross_lrd_cents')::INT,
    'carrier_platform_fee_lrd_cents', (e.snapshot ->> 'carrier_platform_fee_lrd_cents')::INT,
    'carrier_net_lrd_cents', (e.snapshot ->> 'carrier_net_lrd_cents')::INT,
    'recognized_at', e.created_at
  ) ORDER BY e.created_at DESC), '[]'::JSONB)
  INTO v_deliveries
  FROM public.commerce_financial_events e
  JOIN public.deliveries d ON d.id = e.delivery_id
  WHERE d.company_id = p_carrier_company_id AND e.event_type = 'cod_collected'
    AND NOT EXISTS (
      SELECT 1 FROM public.commerce_financial_events r
      WHERE r.commerce_order_id = e.commerce_order_id AND r.event_type = 'reversal'
    )
  LIMIT 100;

  RETURN jsonb_build_object(
    'carrier_gross_lrd_cents', v_gross,
    'platform_fees_lrd_cents', v_fees,
    'net_earnings_lrd_cents', v_net,
    'settled_lrd_cents', v_settled,
    'pending_settlement_lrd_cents', v_pending,
    'deliveries', v_deliveries
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_carrier_commerce_finance(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_carrier_commerce_finance(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_admin_commerce_finance_overview(
  p_from TIMESTAMPTZ DEFAULT NULL,
  p_to TIMESTAMPTZ DEFAULT NULL,
  p_vendor_company_id UUID DEFAULT NULL,
  p_carrier_company_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gmv INT; v_cod_collected INT; v_platform_revenue INT;
  v_vendor_unsettled INT; v_carrier_unsettled INT;
  v_settled_count INT; v_failed_count INT; v_reversal_count INT;
  v_pending_count INT; v_processing_count INT;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT COALESCE(SUM((e.snapshot ->> 'total_collected_lrd_cents')::INT), 0),
         COALESCE(SUM((e.snapshot ->> 'total_collected_lrd_cents')::INT), 0)
  INTO v_gmv, v_cod_collected
  FROM public.commerce_financial_events e
  JOIN public.commerce_orders o ON o.id = e.commerce_order_id
  WHERE e.event_type = 'cod_collected'
    AND (p_from IS NULL OR e.created_at >= p_from)
    AND (p_to IS NULL OR e.created_at < p_to)
    AND (p_vendor_company_id IS NULL OR o.vendor_company_id = p_vendor_company_id)
    AND (p_carrier_company_id IS NULL OR EXISTS (SELECT 1 FROM public.deliveries d WHERE d.id = e.delivery_id AND d.company_id = p_carrier_company_id))
    AND NOT EXISTS (
      SELECT 1 FROM public.commerce_financial_events r
      WHERE r.commerce_order_id = e.commerce_order_id AND r.event_type = 'reversal'
    );

  SELECT
    COALESCE(SUM(amount_lrd_cents) FILTER (WHERE direction = 'credit'), 0)
      - COALESCE(SUM(amount_lrd_cents) FILTER (WHERE direction = 'debit'), 0)
  INTO v_platform_revenue
  FROM public.commerce_ledger_entries le
  JOIN public.commerce_financial_events e ON e.id = le.financial_event_id
  WHERE le.account_type = 'platform_revenue'
    AND (p_from IS NULL OR le.created_at >= p_from)
    AND (p_to IS NULL OR le.created_at < p_to);

  SELECT
    COALESCE(SUM(amount_lrd_cents) FILTER (WHERE direction = 'credit'), 0)
      - COALESCE(SUM(amount_lrd_cents) FILTER (WHERE direction = 'debit'), 0)
  INTO v_vendor_unsettled
  FROM public.commerce_ledger_entries
  WHERE account_type = 'vendor_payable' AND settlement_id IS NULL
    AND (p_vendor_company_id IS NULL OR company_id = p_vendor_company_id);

  SELECT
    COALESCE(SUM(amount_lrd_cents) FILTER (WHERE direction = 'credit'), 0)
      - COALESCE(SUM(amount_lrd_cents) FILTER (WHERE direction = 'debit'), 0)
  INTO v_carrier_unsettled
  FROM public.commerce_ledger_entries
  WHERE account_type = 'carrier_payable' AND settlement_id IS NULL
    AND (p_carrier_company_id IS NULL OR company_id = p_carrier_company_id);

  SELECT COUNT(*) FILTER (WHERE status = 'pending'), COUNT(*) FILTER (WHERE status = 'processing'),
         COUNT(*) FILTER (WHERE status = 'settled'), COUNT(*) FILTER (WHERE status = 'failed')
  INTO v_pending_count, v_processing_count, v_settled_count, v_failed_count
  FROM public.commerce_settlements;

  SELECT COUNT(*) INTO v_reversal_count FROM public.commerce_financial_events WHERE event_type = 'reversal';

  RETURN jsonb_build_object(
    'commerce_gmv_lrd_cents', v_gmv,
    'cod_collected_lrd_cents', v_cod_collected,
    'platform_revenue_lrd_cents', v_platform_revenue,
    'vendor_unsettled_lrd_cents', v_vendor_unsettled,
    'carrier_unsettled_lrd_cents', v_carrier_unsettled,
    'settlements_pending', v_pending_count,
    'settlements_processing', v_processing_count,
    'settlements_completed', v_settled_count,
    'settlements_failed', v_failed_count,
    'reversals_count', v_reversal_count
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_admin_commerce_finance_overview(TIMESTAMPTZ, TIMESTAMPTZ, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_admin_commerce_finance_overview(TIMESTAMPTZ, TIMESTAMPTZ, UUID, UUID) TO authenticated;

-- admin_list_commerce_financial_events: adding filter parameters changes
-- the function's signature, so the old (INT, INT) overload must be
-- dropped explicitly first, or CREATE OR REPLACE would leave it as a
-- separate, orphaned overload instead of replacing it.
DROP FUNCTION IF EXISTS public.admin_list_commerce_financial_events(INT, INT);

CREATE OR REPLACE FUNCTION public.admin_list_commerce_financial_events(
  p_limit INT DEFAULT 25,
  p_offset INT DEFAULT 0,
  p_from TIMESTAMPTZ DEFAULT NULL,
  p_to TIMESTAMPTZ DEFAULT NULL,
  p_vendor_company_id UUID DEFAULT NULL,
  p_event_type TEXT DEFAULT NULL
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
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT COUNT(*)::INT INTO v_total
  FROM public.commerce_financial_events e
  JOIN public.commerce_orders o ON o.id = e.commerce_order_id
  WHERE (p_from IS NULL OR e.created_at >= p_from)
    AND (p_to IS NULL OR e.created_at < p_to)
    AND (p_vendor_company_id IS NULL OR o.vendor_company_id = p_vendor_company_id)
    AND (p_event_type IS NULL OR e.event_type::TEXT = p_event_type);

  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::JSONB) INTO v_rows
  FROM (
    SELECT e.*, o.order_number, o.vendor_company_id
    FROM public.commerce_financial_events e
    JOIN public.commerce_orders o ON o.id = e.commerce_order_id
    WHERE (p_from IS NULL OR e.created_at >= p_from)
      AND (p_to IS NULL OR e.created_at < p_to)
      AND (p_vendor_company_id IS NULL OR o.vendor_company_id = p_vendor_company_id)
      AND (p_event_type IS NULL OR e.event_type::TEXT = p_event_type)
    ORDER BY e.created_at DESC
    LIMIT LEAST(GREATEST(p_limit, 1), 100)
    OFFSET GREATEST(p_offset, 0)
  ) t;

  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_commerce_financial_events(INT, INT, TIMESTAMPTZ, TIMESTAMPTZ, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_commerce_financial_events(INT, INT, TIMESTAMPTZ, TIMESTAMPTZ, UUID, TEXT) TO authenticated;

-- =============================================================================
-- 4) Super Admin Commerce operational visibility: order status/stuck
--    orders, carrier pricing-configuration readiness, paid-but-not-
--    recognized reconciliation check. "Stuck" is admin-adjustable at query
--    time (p_stuck_after_hours), not a buried hardcoded policy.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.admin_get_commerce_orders_summary(p_stuck_after_hours INT DEFAULT 24)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_counts JSONB;
  v_stuck_count INT;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT COALESCE(jsonb_object_agg(s.fulfillment_status, s.cnt), '{}'::JSONB) INTO v_counts
  FROM (
    SELECT fulfillment_status::TEXT, COUNT(*) AS cnt
    FROM public.commerce_orders
    GROUP BY fulfillment_status
  ) s;

  SELECT COUNT(*) INTO v_stuck_count
  FROM public.commerce_orders
  WHERE fulfillment_status::TEXT IN ('awaiting_vendor', 'vendor_accepted', 'preparing', 'ready_for_pickup', 'handed_to_carrier')
    AND updated_at < now() - (p_stuck_after_hours || ' hours')::INTERVAL;

  RETURN jsonb_build_object('by_status', v_counts, 'stuck_count', v_stuck_count);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_commerce_orders_summary(INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_commerce_orders_summary(INT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_list_commerce_orders_page(
  p_fulfillment_statuses TEXT[] DEFAULT NULL,
  p_stuck_only BOOLEAN DEFAULT false,
  p_stuck_after_hours INT DEFAULT 24,
  p_search TEXT DEFAULT NULL,
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
  v_active_statuses TEXT[] := ARRAY['awaiting_vendor', 'vendor_accepted', 'preparing', 'ready_for_pickup', 'handed_to_carrier'];
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT COUNT(*)::INT INTO v_total
  FROM public.commerce_orders o
  JOIN public.companies vc ON vc.id = o.vendor_company_id
  WHERE (p_fulfillment_statuses IS NULL OR o.fulfillment_status::TEXT = ANY(p_fulfillment_statuses))
    AND (NOT p_stuck_only OR (o.fulfillment_status::TEXT = ANY(v_active_statuses) AND o.updated_at < now() - (p_stuck_after_hours || ' hours')::INTERVAL))
    AND (p_search IS NULL OR p_search = '' OR o.order_number ILIKE '%' || p_search || '%' OR vc.name ILIKE '%' || p_search || '%' OR o.customer_name ILIKE '%' || p_search || '%');

  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::JSONB) INTO v_rows
  FROM (
    SELECT
      o.id, o.order_number, o.fulfillment_status, o.payment_status, o.payment_method,
      o.customer_name, o.total_lrd_cents, o.created_at, o.updated_at,
      vc.name AS vendor_name, o.vendor_company_id,
      d.status AS delivery_status, d.company_id AS carrier_company_id, cc.name AS carrier_name,
      (o.fulfillment_status::TEXT = ANY(v_active_statuses) AND o.updated_at < now() - (p_stuck_after_hours || ' hours')::INTERVAL) AS is_stuck,
      ROUND(EXTRACT(EPOCH FROM (now() - o.updated_at)) / 3600.0, 1) AS hours_since_update
    FROM public.commerce_orders o
    JOIN public.companies vc ON vc.id = o.vendor_company_id
    LEFT JOIN public.deliveries d ON d.id = o.delivery_id
    LEFT JOIN public.companies cc ON cc.id = d.company_id
    WHERE (p_fulfillment_statuses IS NULL OR o.fulfillment_status::TEXT = ANY(p_fulfillment_statuses))
      AND (NOT p_stuck_only OR (o.fulfillment_status::TEXT = ANY(v_active_statuses) AND o.updated_at < now() - (p_stuck_after_hours || ' hours')::INTERVAL))
      AND (p_search IS NULL OR p_search = '' OR o.order_number ILIKE '%' || p_search || '%' OR vc.name ILIKE '%' || p_search || '%' OR o.customer_name ILIKE '%' || p_search || '%')
    ORDER BY o.created_at DESC
    LIMIT LEAST(GREATEST(p_limit, 1), 100)
    OFFSET GREATEST(p_offset, 0)
  ) t;

  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_commerce_orders_page(TEXT[], BOOLEAN, INT, TEXT, INT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_commerce_orders_page(TEXT[], BOOLEAN, INT, TEXT, INT, INT) TO authenticated;

-- Carrier pricing-configuration readiness — the exact gap Phase D/E1's
-- zero-fee hardening created a signal for (delivery_pricing_configured_at)
-- but nothing admin-facing ever surfaced it.
CREATE OR REPLACE FUNCTION public.admin_list_commerce_providers_page(
  p_search TEXT DEFAULT NULL,
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
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT COUNT(*)::INT INTO v_total
  FROM public.provider_marketplace_profiles p
  JOIN public.companies c ON c.id = p.company_id
  WHERE c.business_type IN ('logistics_provider', 'hybrid')
    AND (p_search IS NULL OR p_search = '' OR c.name ILIKE '%' || p_search || '%');

  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::JSONB) INTO v_rows
  FROM (
    SELECT
      c.id AS company_id, c.name AS company_name, c.status AS company_status,
      p.marketplace_enabled, p.accepting_jobs, p.minimum_delivery_fee_lrd_cents,
      p.delivery_pricing_configured_at, p.admin_marketplace_disabled,
      (SELECT COUNT(*) FROM public.riders r WHERE r.company_id = c.id AND r.status = 'available') AS available_riders,
      (SELECT COUNT(*) FROM public.riders r WHERE r.company_id = c.id) AS total_riders
    FROM public.provider_marketplace_profiles p
    JOIN public.companies c ON c.id = p.company_id
    WHERE c.business_type IN ('logistics_provider', 'hybrid')
      AND (p_search IS NULL OR p_search = '' OR c.name ILIKE '%' || p_search || '%')
    ORDER BY p.delivery_pricing_configured_at ASC NULLS FIRST, c.name ASC
    LIMIT LEAST(GREATEST(p_limit, 1), 100)
    OFFSET GREATEST(p_offset, 0)
  ) t;

  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_commerce_providers_page(TEXT, INT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_commerce_providers_page(TEXT, INT, INT) TO authenticated;

-- Reconciliation check: a COD order marked paid with no corresponding
-- cod_collected financial event would mean the trigger seam silently
-- failed to fire — this makes that failure mode visible instead of
-- invisible.
CREATE OR REPLACE FUNCTION public.admin_commerce_reconciliation_gaps(p_limit INT DEFAULT 50)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows JSONB;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::JSONB) INTO v_rows
  FROM (
    SELECT o.id, o.order_number, o.vendor_company_id, o.payment_status, o.payment_method, o.total_lrd_cents, o.updated_at
    FROM public.commerce_orders o
    WHERE o.payment_status = 'paid'
      AND NOT EXISTS (
        SELECT 1 FROM public.commerce_financial_events e
        WHERE e.commerce_order_id = o.id AND e.event_type = 'cod_collected'
      )
    ORDER BY o.updated_at DESC
    LIMIT LEAST(GREATEST(p_limit, 1), 200)
  ) t;

  RETURN jsonb_build_object('rows', v_rows, 'count', jsonb_array_length(v_rows));
END;
$$;

REVOKE ALL ON FUNCTION public.admin_commerce_reconciliation_gaps(INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_commerce_reconciliation_gaps(INT) TO authenticated;

-- =============================================================================
-- 5) Vendor onboarding: add Commerce-specific steps for merchant/hybrid
--    companies. Additive only — the existing 'zone'/'rider'/'delivery'/
--    'request' steps and their hrefs are untouched, so nothing that reads
--    this RPC elsewhere breaks.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_company_onboarding_status(p_company_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type public.company_business_type;
  v_has_rider BOOLEAN;
  v_has_delivery BOOLEAN;
  v_has_customer BOOLEAN;
  v_has_zone BOOLEAN;
  v_has_request BOOLEAN;
  v_has_store_profile BOOLEAN;
  v_has_product BOOLEAN;
  v_store_submitted BOOLEAN;
BEGIN
  IF NOT public.has_company_role(p_company_id, ARRAY['company_owner', 'dispatcher', 'support_staff']::public.company_role[])
     AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT business_type INTO v_type FROM public.companies WHERE id = p_company_id;

  SELECT EXISTS (SELECT 1 FROM public.riders r WHERE r.company_id = p_company_id) INTO v_has_rider;
  SELECT EXISTS (SELECT 1 FROM public.deliveries d WHERE d.company_id = p_company_id) INTO v_has_delivery;
  SELECT EXISTS (SELECT 1 FROM public.customers c WHERE c.company_id = p_company_id) INTO v_has_customer;
  SELECT EXISTS (SELECT 1 FROM public.delivery_zones z WHERE z.company_id = p_company_id) INTO v_has_zone;
  SELECT EXISTS (
    SELECT 1 FROM public.delivery_requests dr WHERE dr.merchant_company_id = p_company_id
  ) INTO v_has_request;

  SELECT EXISTS (SELECT 1 FROM public.store_profiles sp WHERE sp.company_id = p_company_id) INTO v_has_store_profile;
  SELECT EXISTS (SELECT 1 FROM public.products p WHERE p.company_id = p_company_id) INTO v_has_product;
  SELECT EXISTS (
    SELECT 1 FROM public.store_profiles sp WHERE sp.company_id = p_company_id AND sp.status <> 'draft'
  ) INTO v_store_submitted;

  RETURN jsonb_build_object(
    'business_type', v_type,
    'has_rider', v_has_rider,
    'has_delivery', v_has_delivery,
    'has_customer', v_has_customer,
    'has_zone', v_has_zone,
    'has_marketplace_request', v_has_request,
    'has_store_profile', v_has_store_profile,
    'has_product', v_has_product,
    'store_submitted', v_store_submitted,
    'steps', CASE v_type
      WHEN 'merchant' THEN jsonb_build_array(
        jsonb_build_object('key', 'commerce_store_profile', 'done', v_has_store_profile, 'href', '/vendor/settings'),
        jsonb_build_object('key', 'commerce_product', 'done', v_has_product, 'href', '/vendor/products'),
        jsonb_build_object('key', 'commerce_store_review', 'done', v_store_submitted, 'href', '/vendor/settings'),
        jsonb_build_object('key', 'customer', 'done', v_has_customer, 'href', '/customers'),
        jsonb_build_object('key', 'request', 'done', v_has_request, 'href', '/merchant/requests')
      )
      WHEN 'hybrid' THEN jsonb_build_array(
        jsonb_build_object('key', 'zone', 'done', v_has_zone, 'href', '/settings'),
        jsonb_build_object('key', 'rider', 'done', v_has_rider, 'href', '/riders'),
        jsonb_build_object('key', 'delivery', 'done', v_has_delivery, 'href', '/deliveries'),
        jsonb_build_object('key', 'request', 'done', v_has_request, 'href', '/merchant/requests'),
        jsonb_build_object('key', 'commerce_store_profile', 'done', v_has_store_profile, 'href', '/vendor/settings'),
        jsonb_build_object('key', 'commerce_product', 'done', v_has_product, 'href', '/vendor/products')
      )
      ELSE jsonb_build_array(
        jsonb_build_object('key', 'zone', 'done', v_has_zone, 'href', '/settings'),
        jsonb_build_object('key', 'rider', 'done', v_has_rider, 'href', '/riders'),
        jsonb_build_object('key', 'delivery', 'done', v_has_delivery, 'href', '/deliveries')
      )
    END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_company_onboarding_status TO authenticated;

-- =============================================================================
-- 6) store_profiles column-level exposure fix: an authenticated (not just
--    anon) customer session could read another store's status_reason/
--    reviewed_by/reviewed_at via a raw PostgREST column selection on an
--    active row, since Postgres column grants aren't row-aware — Phase C's
--    own header comment already documented this as a known residual for
--    `authenticated` specifically because the deployed vendor settings
--    page read those columns directly from the table. Closing it now by
--    moving that read behind a company-scoped RPC and revoking the
--    columns from `authenticated` too, matching the existing `anon` revoke.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_vendor_store_profile(p_company_id UUID)
RETURNS public.store_profiles
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.store_profiles;
BEGIN
  IF NOT public.has_company_role(p_company_id, ARRAY['company_owner', 'dispatcher', 'support_staff']::public.company_role[])
     AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT * INTO v_row FROM public.store_profiles WHERE company_id = p_company_id;
  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.get_vendor_store_profile(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_vendor_store_profile(UUID) TO authenticated;

-- Postgres column privileges are ADDITIVE on top of table-level
-- privileges, not subtractive — a column-level REVOKE alone cannot carve
-- an exception out of the existing table-level GRANT SELECT ... TO
-- authenticated (from 20260308190500_codify_anon_authenticated_table_
-- grants.sql), which still covers every column regardless. The only way
-- to actually narrow it is to revoke the table-level grant entirely and
-- re-grant SELECT on just the safe column list — exactly the same fix
-- Phase C already applied for `anon` for the same reason (see that
-- migration's own comment). fetchStoreProfile and fetchStoreBrief are the
-- only two frontend call sites reading store_profiles directly as
-- `authenticated`, and both only ever use columns in this safe list; the
-- vendor's own full row (including status_reason) now goes through
-- get_vendor_store_profile above instead.
REVOKE SELECT ON public.store_profiles FROM authenticated;
GRANT SELECT (
  company_id, slug, display_name, description, logo_url, banner_url,
  business_hours, allow_cash_on_delivery, status, created_at, updated_at
) ON public.store_profiles TO authenticated;

-- =============================================================================
-- 7) Enforce commerce_enabled server-side. The subscriptions plan catalog
--    (Super-Admin-controlled, already seeded so only business/enterprise
--    plans have commerce_enabled=true — see this migration's own header
--    for why that seed was never actually read anywhere until now) is the
--    single source of truth via the existing can_use_feature() gate — no
--    plan slug is hardcoded here.
--
--    Enforced at exactly two existing, already-centralized chokepoints
--    rather than scattered per-RPC:
--      - assert_vendor_manager: gates every vendor CATALOG write (store
--        profile, products, categories, options, images, stock) — every
--        caller is a write, so the whole function is gated.
--      - assert_vendor_order_actor: gates every vendor ORDER write
--        (accept/reject/preparing/ready/request-delivery) but is ALSO
--        used by three read-only RPCs (list orders, overview, finance).
--        Gating those too would lock a vendor out of viewing their own
--        already-earned history the moment a plan lapses, which has no
--        precedent anywhere else in this codebase — get_carrier_commerce_
--        finance, for comparison, has never gated carrier finance reads on
--        provider_network. A new p_require_commerce_enabled parameter
--        (default true, so every existing write call site is gated with
--        zero changes) lets the three read RPCs opt out explicitly,
--        keeping the check in ONE place instead of duplicating it.
--      - submit_commerce_order: the actual customer-facing purchase
--        boundary — gated directly, since it is a customer action, not a
--        vendor one, and never goes through either assert_* function.
--
--    Super Admin is exempt from the commerce_enabled check specifically
--    (not from the business_type check) in both assert_* functions, so
--    platform support/ops work on a vendor's storefront is never blocked
--    by that vendor's own plan — matching "do not break Super Admin
--    operational access." None of the new admin_* RPCs from this same
--    migration call either assert_* function at all, so Commerce
--    Operations / Commerce Finance / vendor approval are unaffected
--    regardless.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.assert_vendor_manager(p_company_id UUID)
RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type public.company_business_type;
BEGIN
  IF NOT public.has_company_role(p_company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[])
     AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  SELECT business_type INTO v_type FROM public.companies WHERE id = p_company_id;
  IF v_type NOT IN ('merchant', 'hybrid') THEN
    RAISE EXCEPTION 'not_a_vendor_company';
  END IF;
  IF NOT public.is_super_admin() AND NOT public.can_use_feature(p_company_id, 'commerce_enabled') THEN
    RAISE EXCEPTION 'commerce_not_enabled';
  END IF;
END;
$$;

-- Adding a parameter changes this function's identity to Postgres (a
-- different argument-type list), so CREATE OR REPLACE alone would leave
-- the old 1-arg version as an orphaned, ungated second overload rather
-- than replacing it — the same class of bug already fixed once this
-- session for submit_commerce_order's parameter count change.
DROP FUNCTION IF EXISTS public.assert_vendor_order_actor(UUID);

CREATE OR REPLACE FUNCTION public.assert_vendor_order_actor(
  p_company_id UUID,
  p_require_commerce_enabled BOOLEAN DEFAULT true
)
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
  IF p_require_commerce_enabled AND NOT public.is_super_admin()
     AND NOT public.can_use_feature(p_company_id, 'commerce_enabled') THEN
    RAISE EXCEPTION 'commerce_not_enabled';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.assert_vendor_order_actor(UUID, BOOLEAN) FROM PUBLIC;

-- Every existing WRITE call site (vendor_accept/reject/preparing/ready,
-- request_commerce_order_delivery) calls assert_vendor_order_actor with
-- just the company id and is untouched by this migration — it now
-- resolves to the 2-arg function above via the default (true), so it's
-- gated with no call-site changes needed. Only the three READ call sites
-- below are redefined, to pass false explicitly.
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
  PERFORM public.assert_vendor_order_actor(p_vendor_company_id, false);

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
      d.status AS delivery_status,
      dr.status AS delivery_request_status,
      (
        SELECT COUNT(*)::INT FROM public.delivery_offers doff
        WHERE doff.delivery_request_id = o.delivery_request_id AND doff.status = 'pending'
      ) AS pending_offers_count,
      carrier.name AS carrier_name
    FROM public.commerce_orders o
    LEFT JOIN public.deliveries d ON d.id = o.delivery_id
    LEFT JOIN public.delivery_requests dr ON dr.id = o.delivery_request_id
    LEFT JOIN public.companies carrier ON carrier.id = d.company_id
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

-- get_vendor_commerce_overview: unchanged body, plus a real
-- commerce_enabled flag in the response — this is what the frontend uses
-- to show a proactive plan-upgrade banner instead of only reacting to a
-- failed write.
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
  v_commerce_enabled BOOLEAN;
BEGIN
  PERFORM public.assert_vendor_order_actor(p_vendor_company_id, false);

  v_commerce_enabled := public.can_use_feature(p_vendor_company_id, 'commerce_enabled');

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
    'commerce_enabled', v_commerce_enabled,
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
