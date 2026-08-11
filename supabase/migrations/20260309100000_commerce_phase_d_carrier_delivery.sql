-- DeliveryOS Commerce — Phase D: Carrier Selection, Delivery Request
-- Conversion & Existing Delivery Engine Integration.
--
-- Connects a ready_for_pickup Commerce order to the EXISTING B2B
-- marketplace (delivery_requests/delivery_offers/accept_marketplace_offer)
-- and delivery engine (deliveries/rider assignment/tracking) — no parallel
-- carrier marketplace, no new delivery status machine.
--
-- ===========================================================================
-- Marketplace-flow audit (read this before touching anything below)
-- ===========================================================================
-- The existing B2B flow is NOT a carrier-bidding marketplace: a merchant
-- sets ONE price on create_delivery_request (quoted_amount_lrd_cents),
-- publish_delivery_request() fans that SAME price out to every matching
-- provider as a pre-priced delivery_offers row, and it's first-provider-
-- to-accept-wins (accept_marketplace_offer expires all sibling offers).
-- Providers never propose their own price today; there is no existing
-- "requester compares differently-priced offers and picks one" UI or RPC
-- anywhere in the codebase (confirmed by exhaustive search).
--
-- Commerce needs genuinely different, real per-carrier amounts (so the
-- customer has something honest to compare) AND a "customer picks, THEN
-- carrier confirms" two-step flow, neither of which the existing broadcast
-- assumes. Two schema-safe decisions follow from that gap:
--
--   1. Per-carrier real pricing without inventing a bidding RPC: each
--      matching provider already has a real, carrier-configured
--      `provider_marketplace_profiles.minimum_delivery_fee_lrd_cents`
--      (existing column, currently only shown in the merchant-facing
--      provider directory). For Commerce-sourced requests specifically,
--      each fanned-out offer's quoted_amount_lrd_cents is that provider's
--      OWN minimum fee — real, carrier-set data, never fabricated —
--      instead of a single merchant-set price. This is done by NEW code
--      in request_commerce_order_delivery() below; publish_delivery_request
--      itself is untouched and keeps doing exactly what it does today for
--      every existing B2B call site.
--   2. "Customer selects -> carrier accepts": delivery_offers gets one new
--      nullable column, `selected_by_customer_at`. Deliberately NOT a new
--      delivery_offer_status enum value — this codebase avoids
--      `ALTER TYPE ... ADD VALUE` everywhere else (same-transaction-use
--      restriction) and a nullable timestamp is forward-safe: every
--      existing B2B offer row simply has it NULL forever, so nothing about
--      today's offer.status semantics is reinterpreted. accept_marketplace_
--      offer() gets a narrowly-scoped addition (see below) that only
--      changes behavior for offers on a Commerce-linked request; every
--      non-Commerce call site is provably unaffected because the added
--      branch is guarded by `EXISTS (SELECT 1 FROM commerce_orders WHERE
--      delivery_request_id = v_req.id)`, which is never true for a plain
--      B2B request.
--
-- We do NOT call create_delivery_request() from the new vendor-facing
-- orchestration RPC below, even though it would otherwise be the obvious
-- "reuse" move: its actor check is `company_owner`/`dispatcher` ONLY,
-- narrower than the owner/dispatcher/support_staff fulfillment-action model
-- every other Commerce vendor RPC already uses (assert_vendor_order_actor).
-- Calling it directly would silently block support_staff from progressing
-- an order past ready_for_pickup even though they can accept/prepare/ready
-- it. Instead request_commerce_order_delivery() authorizes via
-- assert_vendor_order_actor (consistent with the rest of Commerce) and
-- mirrors create_delivery_request's INSERT shape directly, while still
-- reusing assert_merchant_marketplace() verbatim for the company-level
-- gate (plan feature flag, business_type, suspension) since that check has
-- nothing to do with the role-granularity mismatch.
--
-- ===========================================================================
-- COD amount audit (read this before assuming anything about `payments`)
-- ===========================================================================
-- payments.amount_lrd_cents is written by exactly one path today:
-- ensure_cod_payment_on_delivered() (trigger on deliveries, fires on
-- status -> 'delivered'), and it is set to NEW.amount_to_collect_lrd_cents
-- — nothing else, never delivery_fee_lrd_cents, never a sum. But
-- `amount_to_collect_lrd_cents` itself is not hard-coded to mean
-- "merchandise only" anywhere in the schema — it's populated from
-- delivery_requests.cod_amount_lrd_cents, a merchant-supplied "amount to
-- collect from the customer at the door" figure whose composition has
-- always been entirely up to the requester. So for a Commerce delivery,
-- setting deliveries.amount_to_collect_lrd_cents = the ORDER'S frozen
-- product subtotal + the ACCEPTED offer's delivery fee (the true total
-- cash the rider must collect, since nothing was pre-paid) is using the
-- column exactly as designed, not overloading it — no schema extension to
-- `payments` or `deliveries` is required. The breakdown remains fully
-- recoverable without a new column: deliveries.delivery_fee_lrd_cents
-- (already set from the offer, same as every B2B delivery) minus
-- deliveries.amount_to_collect_lrd_cents' non-fee portion is implicit, and
-- explicitly, commerce_orders.subtotal_lrd_cents (frozen at checkout) and
-- commerce_orders.delivery_fee_lrd_cents (frozen at carrier acceptance,
-- see below) already carry the authoritative breakdown on the Commerce
-- side. This decision is deliberate, not a guess — see the Phase D report
-- for the explicit design rationale.
--
-- ===========================================================================
-- Fulfillment synchronization design
-- ===========================================================================
-- commerce_orders.fulfillment_status stays 'ready_for_pickup' through
-- delivery-request publication, carrier selection, and carrier acceptance
-- — nothing has physically happened to the order yet at that point, so
-- 'ready_for_pickup' remains honest. A NEW trigger on deliveries (mirroring
-- the exact idiom Phase B.5's trg_sync_commerce_order_payment_from_cod
-- already established: AFTER UPDATE OF status, guarded by
-- commerce_order_id IS NOT NULL) advances the linked Commerce order only
-- when the REAL delivery reaches a REAL milestone: picked_up (package
-- physically handed to the carrier) -> handed_to_carrier; delivered ->
-- completed; failed/cancelled -> cancelled. This never touches
-- delivery_transition_core or the delivery_status state machine itself —
-- it only observes the result, same as the payment-sync trigger already
-- does for `payments`.

-- ---------------------------------------------------------------------------
-- Schema: minimal, forward-safe additions only.
-- ---------------------------------------------------------------------------
ALTER TABLE public.commerce_orders
  ADD COLUMN IF NOT EXISTS delivery_request_id UUID REFERENCES public.delivery_requests (id) ON DELETE SET NULL;

ALTER TABLE public.delivery_offers
  ADD COLUMN IF NOT EXISTS selected_by_customer_at TIMESTAMPTZ;

-- Defense in depth: a Commerce order can never link to more than one
-- delivery_request or more than one delivery, enforced at the DB level,
-- not just by RPC-level idempotency checks.
CREATE UNIQUE INDEX IF NOT EXISTS uq_commerce_orders_delivery_request
  ON public.commerce_orders (delivery_request_id) WHERE delivery_request_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_deliveries_commerce_order
  ON public.deliveries (commerce_order_id) WHERE commerce_order_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Vendor: convert a ready_for_pickup Commerce order into a real
-- delivery_requests row and fan out real, per-carrier-priced offers.
-- Idempotent: a second call for an order that already has a
-- delivery_request_id just returns the existing request + its current
-- offers, creating nothing new.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.request_commerce_order_delivery(p_order_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.commerce_orders;
  v_req public.delivery_requests;
  v_store public.store_profiles;
  v_branch public.company_branches;
  v_company public.companies;
  v_package_count INT;
  v_package_description TEXT;
  v_provider RECORD;
  v_offer_count INT := 0;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT * INTO v_order FROM public.commerce_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'order_not_found'; END IF;

  PERFORM public.assert_vendor_order_actor(v_order.vendor_company_id);

  -- Idempotent: already converted (or in progress) — return current state,
  -- create nothing.
  IF v_order.delivery_request_id IS NOT NULL THEN
    SELECT * INTO v_req FROM public.delivery_requests WHERE id = v_order.delivery_request_id;
    RETURN jsonb_build_object(
      'delivery_request', to_jsonb(v_req),
      'offers_created', 0,
      'already_existed', true
    );
  END IF;

  IF v_order.fulfillment_status <> 'ready_for_pickup' THEN
    RAISE EXCEPTION 'invalid_fulfillment_state';
  END IF;

  -- Same company-level marketplace eligibility gate create_delivery_request
  -- itself enforces (plan feature flag, business_type, suspension) — see
  -- header comment for why we don't call create_delivery_request directly.
  PERFORM public.assert_merchant_marketplace(v_order.vendor_company_id);

  SELECT * INTO v_store FROM public.store_profiles WHERE company_id = v_order.vendor_company_id;
  SELECT * INTO v_company FROM public.companies WHERE id = v_order.vendor_company_id;

  SELECT * INTO v_branch FROM public.company_branches
  WHERE id = v_company.default_branch_id AND is_active = true;
  IF NOT FOUND THEN
    SELECT * INTO v_branch FROM public.company_branches
    WHERE company_id = v_order.vendor_company_id AND is_active = true
    ORDER BY created_at LIMIT 1;
  END IF;

  IF v_branch.id IS NULL AND v_company.address IS NULL THEN
    RAISE EXCEPTION 'pickup_location_not_configured';
  END IF;

  SELECT COALESCE(SUM(oi.quantity), 1)::INT INTO v_package_count
  FROM public.commerce_order_items oi WHERE oi.order_id = v_order.id;

  SELECT v_package_count || ' item(s) from ' || COALESCE(v_store.display_name, v_company.name)
  INTO v_package_description;

  INSERT INTO public.delivery_requests (
    merchant_company_id, pickup_branch_id,
    pickup_address, pickup_latitude, pickup_longitude, pickup_area_summary,
    destination_address, destination_latitude, destination_longitude, destination_area_summary,
    package_count, cod_amount_lrd_cents, delivery_notes,
    customer_name, customer_phone, package_description,
    status, created_by
  ) VALUES (
    v_order.vendor_company_id,
    v_branch.id,
    COALESCE(v_branch.address, v_company.address, v_store.display_name),
    v_branch.latitude,
    v_branch.longitude,
    COALESCE(v_branch.name, v_store.display_name),
    v_order.delivery_address,
    v_order.delivery_latitude,
    v_order.delivery_longitude,
    v_order.delivery_area_summary,
    v_package_count,
    v_order.subtotal_lrd_cents,
    v_order.delivery_instructions,
    v_order.customer_name,
    v_order.customer_phone,
    v_package_description,
    'open',
    auth.uid()
  )
  RETURNING * INTO v_req;

  UPDATE public.commerce_orders SET delivery_request_id = v_req.id, updated_at = now() WHERE id = p_order_id;

  -- Real, per-carrier fan-out: each matching provider's OWN configured
  -- minimum_delivery_fee_lrd_cents becomes that provider's offer amount —
  -- genuinely different, real numbers to compare, never fabricated. Same
  -- matching predicate the B2B broadcast already uses
  -- (provider_matches_delivery_request), so eligibility rules stay
  -- identical between B2B and Commerce.
  FOR v_provider IN
    SELECT c.id AS company_id, p.minimum_delivery_fee_lrd_cents
    FROM public.companies c
    JOIN public.provider_marketplace_profiles p ON p.company_id = c.id
    WHERE c.business_type IN ('logistics_provider', 'hybrid')
      AND public.provider_matches_delivery_request(c.id, v_req)
    LIMIT 50
  LOOP
    INSERT INTO public.delivery_offers (
      delivery_request_id, provider_company_id, quoted_amount_lrd_cents, expires_at
    ) VALUES (
      v_req.id, v_provider.company_id, GREATEST(v_provider.minimum_delivery_fee_lrd_cents, 0), now() + interval '24 hours'
    )
    ON CONFLICT (delivery_request_id, provider_company_id) DO NOTHING;

    IF FOUND THEN
      v_offer_count := v_offer_count + 1;
      PERFORM public.enqueue_webhook_event(
        v_provider.company_id, 'marketplace_job.available', v_req.id,
        jsonb_build_object(
          'delivery_request_id', v_req.id, 'pickup_area', v_req.pickup_area_summary,
          'destination_area', v_req.destination_area_summary,
          'quoted_amount_lrd_cents', GREATEST(v_provider.minimum_delivery_fee_lrd_cents, 0)
        )
      );
    END IF;
  END LOOP;

  IF v_offer_count > 0 THEN
    UPDATE public.delivery_requests SET status = 'offered' WHERE id = v_req.id RETURNING * INTO v_req;
  END IF;

  PERFORM public.enqueue_webhook_event(
    v_order.vendor_company_id, 'commerce_order.delivery_requested', v_order.id, to_jsonb(v_req)
  );

  RETURN jsonb_build_object(
    'delivery_request', to_jsonb(v_req),
    'offers_created', v_offer_count,
    'already_existed', false
  );
END;
$$;

REVOKE ALL ON FUNCTION public.request_commerce_order_delivery(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_commerce_order_delivery(UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- Customer: read carrier options + delivery/rider status for their own
-- order. A dedicated read RPC (not raw table reads) because delivery_offers
-- and deliveries have no RLS path for a bare customer identity at all —
-- their only relationships to those tables are indirect, through this
-- order — same "minimal safe read RPC" discipline as Phase C's
-- get_public_store_catalog/get_cart_summary. Never exposes another
-- carrier's private data beyond what's needed to compare and choose:
-- company display name, its own quoted amount, and real state.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_commerce_order_delivery_status(p_order_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.commerce_orders;
  v_req public.delivery_requests;
  v_offers JSONB;
  v_delivery JSONB;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT * INTO v_order FROM public.commerce_orders WHERE id = p_order_id AND customer_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'order_not_found'; END IF;

  IF v_order.delivery_request_id IS NULL THEN
    RETURN jsonb_build_object('delivery_request', NULL, 'offers', '[]'::JSONB, 'delivery', NULL);
  END IF;

  SELECT * INTO v_req FROM public.delivery_requests WHERE id = v_order.delivery_request_id;

  -- Eligible-to-choose-from offers: still pending and not expired, PLUS
  -- whichever offer the customer already selected (so their choice stays
  -- visible even if siblings later expire) and whichever offer a carrier
  -- has actually accepted (so the final outcome is always visible).
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'offer_id', o.id,
    'carrier_company_id', o.provider_company_id,
    'carrier_name', c.name,
    'quoted_amount_lrd_cents', o.quoted_amount_lrd_cents,
    'estimated_pickup_minutes', o.estimated_pickup_minutes,
    'status', o.status,
    'is_selected', o.selected_by_customer_at IS NOT NULL,
    'expires_at', o.expires_at
  ) ORDER BY o.quoted_amount_lrd_cents ASC), '[]'::JSONB)
  INTO v_offers
  FROM public.delivery_offers o
  JOIN public.companies c ON c.id = o.provider_company_id
  WHERE o.delivery_request_id = v_req.id
    AND (
      (o.status = 'pending' AND (o.expires_at IS NULL OR o.expires_at > now()))
      OR o.selected_by_customer_at IS NOT NULL
      OR o.status = 'accepted'
    );

  IF v_order.delivery_id IS NOT NULL THEN
    SELECT jsonb_build_object(
      'delivery_id', d.id,
      'tracking_code', d.tracking_code,
      'status', d.status,
      'carrier_name', c.name,
      'rider_name', r.full_name
    ) INTO v_delivery
    FROM public.deliveries d
    JOIN public.companies c ON c.id = d.company_id
    LEFT JOIN public.riders r ON r.id = d.rider_id
    WHERE d.id = v_order.delivery_id;
  END IF;

  RETURN jsonb_build_object(
    'delivery_request', jsonb_build_object('id', v_req.id, 'status', v_req.status),
    'offers', v_offers,
    'delivery', v_delivery
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_commerce_order_delivery_status(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_commerce_order_delivery_status(UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- Customer: choose a carrier. Marks intent only — the offer's amount is
-- frozen onto the real delivery only once the carrier actually accepts
-- (accept_marketplace_offer, extended below), the same "carrier still has
-- to confirm" semantics as the rest of the marketplace. Selecting a
-- different offer before any carrier has accepted simply moves the
-- selection; nothing is destructive.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.select_commerce_delivery_offer(p_order_id UUID, p_offer_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.commerce_orders;
  v_offer public.delivery_offers;
  v_req public.delivery_requests;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT * INTO v_order FROM public.commerce_orders WHERE id = p_order_id AND customer_id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'order_not_found'; END IF;

  IF v_order.delivery_id IS NOT NULL THEN
    RAISE EXCEPTION 'delivery_already_created';
  END IF;
  IF v_order.delivery_request_id IS NULL THEN
    RAISE EXCEPTION 'delivery_not_requested_yet';
  END IF;

  SELECT * INTO v_offer FROM public.delivery_offers WHERE id = p_offer_id FOR UPDATE;
  IF NOT FOUND OR v_offer.delivery_request_id <> v_order.delivery_request_id THEN
    RAISE EXCEPTION 'invalid_offer';
  END IF;
  IF v_offer.status <> 'pending' THEN
    RAISE EXCEPTION 'offer_not_available';
  END IF;
  IF v_offer.expires_at IS NOT NULL AND v_offer.expires_at <= now() THEN
    RAISE EXCEPTION 'offer_expired';
  END IF;

  SELECT * INTO v_req FROM public.delivery_requests WHERE id = v_order.delivery_request_id;
  IF NOT public.provider_matches_delivery_request(v_offer.provider_company_id, v_req) THEN
    RAISE EXCEPTION 'provider_not_available';
  END IF;

  -- A customer can change their mind among still-pending offers — clear
  -- any prior selection on this request before setting the new one.
  UPDATE public.delivery_offers SET selected_by_customer_at = NULL
  WHERE delivery_request_id = v_req.id AND id <> p_offer_id AND selected_by_customer_at IS NOT NULL;

  UPDATE public.delivery_offers SET selected_by_customer_at = now()
  WHERE id = p_offer_id
  RETURNING * INTO v_offer;

  RETURN to_jsonb(v_offer);
END;
$$;

REVOKE ALL ON FUNCTION public.select_commerce_delivery_offer(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.select_commerce_delivery_offer(UUID, UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- accept_marketplace_offer: narrowly-scoped Commerce addition. CREATE OR
-- REPLACE with the SAME signature (p_offer_id, p_provider_company_id) — no
-- overload created. Every added branch below is guarded by
-- `v_commerce_order.id IS NOT NULL`, which is only ever true when the
-- offer's delivery_request is linked from a commerce_orders row — never
-- true for any existing B2B request, so non-Commerce behavior is
-- byte-for-byte unchanged (verified by commerce_phase_d.test.sql running
-- the existing marketplace test suite green afterward).
-- ---------------------------------------------------------------------------
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
    WHERE id = v_commerce_order.id;
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

-- ---------------------------------------------------------------------------
-- Fulfillment sync: observes the REAL delivery status machine, never
-- duplicates it. Mirrors trg_sync_commerce_order_payment_from_cod exactly
-- (Phase B.5 precedent): AFTER UPDATE OF status ON deliveries, guarded by
-- commerce_order_id IS NOT NULL, so it is a pure no-op for every
-- non-Commerce delivery.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_sync_commerce_order_fulfillment_from_delivery()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.commerce_order_id IS NULL OR OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;

  IF NEW.status = 'picked_up' THEN
    UPDATE public.commerce_orders SET fulfillment_status = 'handed_to_carrier', updated_at = now()
    WHERE id = NEW.commerce_order_id AND fulfillment_status = 'ready_for_pickup';
  ELSIF NEW.status = 'delivered' THEN
    UPDATE public.commerce_orders SET fulfillment_status = 'completed', updated_at = now()
    WHERE id = NEW.commerce_order_id AND fulfillment_status IN ('ready_for_pickup', 'handed_to_carrier');
  ELSIF NEW.status IN ('failed', 'cancelled') THEN
    UPDATE public.commerce_orders SET
      fulfillment_status = 'cancelled',
      cancellation_reason = COALESCE(cancellation_reason, 'delivery_' || NEW.status),
      cancelled_at = now(),
      updated_at = now()
    WHERE id = NEW.commerce_order_id AND fulfillment_status IN ('ready_for_pickup', 'handed_to_carrier');
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_commerce_order_fulfillment_from_delivery ON public.deliveries;
CREATE TRIGGER sync_commerce_order_fulfillment_from_delivery
  AFTER UPDATE OF status ON public.deliveries
  FOR EACH ROW EXECUTE FUNCTION public.trg_sync_commerce_order_fulfillment_from_delivery();

-- ---------------------------------------------------------------------------
-- Vendor order inbox: additive fields only (delivery-request/offer/carrier
-- progress), same signature, same shape for every field that already
-- existed — existing frontend callers unaffected.
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

-- ---------------------------------------------------------------------------
-- Carrier inbox: additive fields only, so a Commerce-originated job is
-- clearly labeled and pre-selection offers are visibly non-actionable —
-- the actual enforcement is server-side in accept_marketplace_offer above,
-- this is UX clarity, not the security boundary.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_marketplace_jobs_page(
  p_provider_company_id UUID,
  p_status TEXT DEFAULT 'pending',
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
  v_items JSONB;
  v_total BIGINT;
BEGIN
  IF NOT public.has_company_role(p_provider_company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[])
     AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT COUNT(*) INTO v_total
  FROM public.delivery_offers o
  WHERE o.provider_company_id = p_provider_company_id
    AND (p_status IS NULL OR o.status::TEXT = p_status);

  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::JSONB) INTO v_items
  FROM (
    SELECT
      o.id AS offer_id,
      o.status AS offer_status,
      o.quoted_amount_lrd_cents,
      o.offered_at,
      o.expires_at,
      dr.id AS delivery_request_id,
      dr.status AS request_status,
      dr.pickup_area_summary,
      dr.destination_area_summary,
      dr.package_count,
      dr.fragile,
      dr.cod_amount_lrd_cents,
      CASE WHEN o.status = 'accepted' THEN dr.pickup_address ELSE NULL END AS pickup_address,
      CASE WHEN o.status = 'accepted' THEN dr.destination_address ELSE NULL END AS destination_address,
      CASE WHEN o.status = 'accepted' THEN dr.customer_name ELSE NULL END AS customer_name,
      CASE WHEN o.status = 'accepted' THEN dr.customer_phone ELSE NULL END AS customer_phone,
      EXISTS (SELECT 1 FROM public.commerce_orders co WHERE co.delivery_request_id = dr.id) AS is_commerce_order,
      (
        EXISTS (SELECT 1 FROM public.commerce_orders co WHERE co.delivery_request_id = dr.id)
        AND o.selected_by_customer_at IS NULL
      ) AS awaiting_customer_selection
    FROM public.delivery_offers o
    JOIN public.delivery_requests dr ON dr.id = o.delivery_request_id
    WHERE o.provider_company_id = p_provider_company_id
      AND (p_status IS NULL OR o.status::TEXT = p_status)
    ORDER BY o.offered_at DESC
    LIMIT LEAST(GREATEST(p_limit, 1), 100)
    OFFSET GREATEST(p_offset, 0)
  ) t;

  RETURN jsonb_build_object('items', v_items, 'total', v_total, 'limit', p_limit, 'offset', p_offset);
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_marketplace_jobs_page TO authenticated;

-- ---------------------------------------------------------------------------
-- Bug fix, surfaced by wiring the real delivery linkage end-to-end for the
-- first time: trg_sync_commerce_order_payment_from_cod (Phase B.5) was only
-- ever installed as `AFTER UPDATE ON public.payments`. But the ACTUAL, only
-- real writer of a COD payments row — ensure_cod_payment_on_delivered
-- (trigger on deliveries, fires on status -> 'delivered') — does a single
-- `INSERT ... ON CONFLICT (delivery_id) DO UPDATE`, which for a delivery's
-- first-ever payment is a plain INSERT, not an UPDATE, and its `status`
-- goes straight to 'collected' in that one statement. An AFTER UPDATE-only
-- trigger never fires for that INSERT, so the Phase B.5 seam was dormant
-- for a reason beyond "commerce_order_id was always NULL" — it also had
-- this latent gap, invisible until Phase D actually exercised the real
-- delivered -> payments -> sync path in commerce_phase_d.test.sql's
-- end-to-end scenario (Phase B.5's own test only ever drove the trigger via
-- a synthetic INSERT-then-UPDATE, which happened to sidestep the bug).
-- Fixed by firing on INSERT as well as UPDATE; the function body already
-- correctly short-circuits every non-collected/non-transition case via
-- `NEW.status = 'collected' AND (OLD.status IS DISTINCT FROM NEW.status)`
-- — on INSERT, OLD is NULL, so OLD.status IS DISTINCT FROM NEW.status is
-- true whenever NEW.status = 'collected', which is exactly correct.
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS sync_commerce_order_payment_from_cod ON public.payments;
CREATE TRIGGER sync_commerce_order_payment_from_cod
  AFTER INSERT OR UPDATE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.trg_sync_commerce_order_payment_from_cod();
