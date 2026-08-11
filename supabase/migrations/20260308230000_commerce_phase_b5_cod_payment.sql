-- DeliveryOS Commerce — Phase B.5: Payment Method Foundation + COD
--
-- Gives Commerce orders a real, honest fulfillment path before MTN MoMo /
-- Orange Money exist. COD is the only currently-usable payment method;
-- MoMo/Orange are modeled in the schema (so they plug in later without a
-- redesign) but rejected at order-submission time until their integrations
-- are actually built (Phase E).
--
-- Design decisions (see the Phase B.5 report for full rationale):
--   - New public.commerce_payment_method enum, NOT a reuse of
--     billing_payment_method — that enum is subscription-billing's payment
--     method (a different bounded context: platform <-> tenant company),
--     not a commerce customer's order payment method. Conflating them would
--     let a future subscription-billing method leak into checkout options
--     and vice versa. The *shape* (a small closed enum of payment rails) is
--     reused; the *type* is not.
--   - COD orders are never marked payment_status = 'paid' at submission —
--     they stay 'pending_payment' (cash is genuinely still owed) and
--     acceptance eligibility is computed by a dedicated, server-only
--     function rather than adding a new enum value. Adding an enum value
--     here would need ALTER TYPE ... ADD VALUE, which this codebase has
--     never used (Postgres restricts using a freshly-added enum value in
--     the same transaction it was added in) — avoided as an unnecessary
--     risk for a distinction the eligibility function already expresses
--     correctly and testably.
--   - vendor_accept_commerce_order's payment_status = 'paid' requirement is
--     replaced by commerce_order_payment_eligible_for_acceptance(), the
--     single source of truth the frontend never re-implements.
--   - A trigger on the EXISTING payments table (the same one that already
--     drives payment.collected webhooks) synchronizes a COD commerce
--     order to 'paid' the moment the rider's cash collection is recorded.
--     It is real, tested code — but dormant in practice today, because
--     nothing yet populates deliveries.commerce_order_id (that's Phase D).
--     This is the "seam" requested: designed and tested now, not faked.

-- ---------------------------------------------------------------------------
-- Payment method + per-store COD opt-in
-- ---------------------------------------------------------------------------
CREATE TYPE public.commerce_payment_method AS ENUM ('cod', 'mtn_momo', 'orange_money');

ALTER TABLE public.commerce_orders ADD COLUMN payment_method public.commerce_payment_method;
UPDATE public.commerce_orders SET payment_method = 'cod' WHERE payment_method IS NULL;
ALTER TABLE public.commerce_orders ALTER COLUMN payment_method SET NOT NULL;

-- Conservative default: a vendor must explicitly opt in before any order
-- (COD or otherwise) can be placed against their store, matching the
-- existing "draft until reviewed" posture already used for store_profiles.
ALTER TABLE public.store_profiles
  ADD COLUMN IF NOT EXISTS allow_cash_on_delivery BOOLEAN NOT NULL DEFAULT false;

-- ---------------------------------------------------------------------------
-- Vendor-editable: extend upsert_store_profile to cover the new flag.
-- Reproduces the current full body (Phase A) plus this one field.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.upsert_store_profile(p_payload JSONB)
RETURNS public.store_profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID := (p_payload ->> 'company_id')::UUID;
  v_row public.store_profiles;
BEGIN
  PERFORM public.assert_vendor_manager(v_company_id);

  INSERT INTO public.store_profiles (
    company_id, slug, display_name, description, logo_url, banner_url, business_hours, allow_cash_on_delivery
  ) VALUES (
    v_company_id,
    p_payload ->> 'slug',
    p_payload ->> 'display_name',
    p_payload ->> 'description',
    p_payload ->> 'logo_url',
    p_payload ->> 'banner_url',
    COALESCE(p_payload -> 'business_hours', '{}'::JSONB),
    COALESCE((p_payload ->> 'allow_cash_on_delivery')::BOOLEAN, false)
  )
  ON CONFLICT (company_id) DO UPDATE SET
    slug = COALESCE(NULLIF(p_payload ->> 'slug', ''), store_profiles.slug),
    display_name = COALESCE(NULLIF(p_payload ->> 'display_name', ''), store_profiles.display_name),
    description = COALESCE(p_payload ->> 'description', store_profiles.description),
    logo_url = COALESCE(p_payload ->> 'logo_url', store_profiles.logo_url),
    banner_url = COALESCE(p_payload ->> 'banner_url', store_profiles.banner_url),
    business_hours = COALESCE(p_payload -> 'business_hours', store_profiles.business_hours),
    allow_cash_on_delivery = COALESCE((p_payload ->> 'allow_cash_on_delivery')::BOOLEAN, store_profiles.allow_cash_on_delivery)
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_store_profile TO authenticated;

-- ---------------------------------------------------------------------------
-- Server-authoritative acceptance eligibility — the single source of truth
-- vendor_accept_commerce_order defers to. Online methods must be confirmed
-- paid; COD is eligible as soon as it exists (payment is legitimately due
-- on delivery, not blocked).
--
-- Internal helper only — no client ever needs to call this directly (the
-- frontend just calls vendor_accept_commerce_order and handles the
-- payment_not_confirmed error). REVOKE ALL FROM PUBLIC with no GRANT to
-- authenticated keeps it unreachable by any client role, matching the
-- mark_commerce_order_paid/mark_commerce_order_payment_failed pattern.
-- vendor_accept_commerce_order (SECURITY DEFINER, itself GRANTed to
-- authenticated) can still call it internally regardless of this revoke —
-- the effective role inside a SECURITY DEFINER function is the function
-- owner, unaffected by grants revoked from PUBLIC/authenticated.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.commerce_order_payment_eligible_for_acceptance(p_order_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  -- COD: eligible while payment is legitimately still due on delivery
  -- ('pending_payment') AND if it has already been marked 'paid' (e.g. the
  -- cod-collection sync trigger fired before the vendor got to it, or an
  -- admin override) — being already paid must never BLOCK acceptance.
  -- 'payment_failed' / 'refund_pending' / 'refunded' correctly stay
  -- ineligible for both methods.
  SELECT CASE
    WHEN o.payment_method = 'cod' THEN o.payment_status IN ('pending_payment', 'paid')
    ELSE o.payment_status = 'paid'
  END
  FROM public.commerce_orders o
  WHERE o.id = p_order_id;
$$;

REVOKE ALL ON FUNCTION public.commerce_order_payment_eligible_for_acceptance(UUID) FROM PUBLIC;

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

  RETURN v_order;
END;
$$;

GRANT EXECUTE ON FUNCTION public.vendor_accept_commerce_order TO authenticated;

-- ---------------------------------------------------------------------------
-- submit_commerce_order: validate payment method server-side (never trust
-- an arbitrary client string), enforce per-store COD opt-in. Adds one
-- trailing, defaulted parameter to the Phase A signature — existing callers
-- (Phase A/B tests, any future frontend code) keep working unchanged since
-- the new parameter defaults to 'cod'. A different parameter COUNT is a
-- different function identity to Postgres even with a default, so the old
-- 7-parameter overload must be dropped explicitly first — otherwise
-- CREATE OR REPLACE creates a second, ambiguous overload rather than
-- replacing (the same class of bug already fixed once this session for
-- create_delivery/create_company_with_owner).
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.submit_commerce_order(
  UUID, TEXT, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT
);

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

  -- Explicit, defensive re-assertion that this identity completed OTP
  -- verification (a session can only exist post-verifyOtp today, but this
  -- makes the guarantee checkable rather than merely structural).
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

  -- Payment method: never trust the raw string beyond validating it against
  -- the known enum, then gate on what's actually usable today.
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

  RETURN v_order;
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_commerce_order TO authenticated;

-- ---------------------------------------------------------------------------
-- COD payment-confirmation seam: designed and tested now, dormant until
-- Phase D populates deliveries.commerce_order_id. Fires on the EXISTING
-- payments table's status -> 'collected' transition (the same trigger point
-- trg_payment_collected_webhook already uses), so no second reconciliation
-- mechanism is introduced.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_sync_commerce_order_payment_from_cod()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_commerce_order_id UUID;
  v_order public.commerce_orders;
BEGIN
  IF NEW.status = 'collected' AND (OLD.status IS DISTINCT FROM NEW.status) THEN
    SELECT commerce_order_id INTO v_commerce_order_id
    FROM public.deliveries WHERE id = NEW.delivery_id;

    IF v_commerce_order_id IS NOT NULL THEN
      SELECT * INTO v_order FROM public.commerce_orders WHERE id = v_commerce_order_id;
      IF v_order.id IS NOT NULL
         AND v_order.payment_method = 'cod'
         AND v_order.payment_status = 'pending_payment' THEN
        PERFORM public.mark_commerce_order_paid(v_order.id);
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_commerce_order_payment_from_cod ON public.payments;
CREATE TRIGGER sync_commerce_order_payment_from_cod
  AFTER UPDATE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.trg_sync_commerce_order_payment_from_cod();

-- ---------------------------------------------------------------------------
-- Product image storage — reuses the exact same architecture as
-- delivery-photos (20260307170000_storage_and_admin.sql): a dedicated
-- bucket, storage_company_from_path() for path-based tenant scoping (no new
-- helper), and INSERT/DELETE restricted to the owning vendor's
-- owner/dispatcher. Public (unlike delivery-photos) because product photos
-- are meant to be visible on the future public storefront — no signed-URL
-- expiry to manage for a customer-facing image.
-- ---------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'commerce-product-images',
  'commerce-product-images',
  true,
  5242880,
  ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY commerce_product_images_select ON storage.objects
  FOR SELECT TO anon, authenticated
  USING (bucket_id = 'commerce-product-images');

CREATE POLICY commerce_product_images_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'commerce-product-images'
    AND public.storage_company_from_path(name) IN (SELECT public.user_company_ids())
    AND public.has_company_role(
      public.storage_company_from_path(name),
      ARRAY['company_owner', 'dispatcher']::public.company_role[]
    )
  );

CREATE POLICY commerce_product_images_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'commerce-product-images'
    AND public.storage_company_from_path(name) IN (SELECT public.user_company_ids())
    AND public.has_company_role(
      public.storage_company_from_path(name),
      ARRAY['company_owner', 'dispatcher']::public.company_role[]
    )
  );
