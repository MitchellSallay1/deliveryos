-- DeliveryOS Commerce — Phase C: Public Customer Storefront + Cart + OTP-
-- Verified COD Checkout.
--
-- Ships the customer-facing half of Commerce: browse a published store,
-- build a cart, verify phone via the EXISTING Auth OTP flow, and place a
-- COD order — using the Phase A cart RPCs and the Phase B.5 payment-method
-- foundation completely unchanged. This migration adds exactly two new
-- read-only RPCs and one column-level privilege tightening; it does not
-- touch submit_commerce_order, the fulfillment state machine, or any
-- write path.
--
-- Design decisions:
--   - get_public_store_catalog(slug): a single anon-callable RPC rather
--     than raw `.from('store_profiles')...` reads from the frontend. Two
--     reasons: (1) store_profiles carries admin-internal columns
--     (status_reason, reviewed_by, reviewed_at) that RLS (row-level only)
--     cannot hide from anon on an otherwise-visible row — an explicit
--     field allowlist is the only way to keep those out of a public
--     response; (2) it lets the storefront render in one round trip
--     (store + categories + products + images + options + a derived
--     availability signal) instead of five, which matters on the
--     low-bandwidth mobile connections this is built for. It never
--     exposes raw product_stock rows — availability is a derived boolean,
--     matching product_stock's existing "never public" RLS posture.
--   - get_cart_summary(cart_id): a small authenticated-only, owner-scoped
--     read RPC that live-prices the caller's own cart (current product
--     price + option deltas, not frozen) for a trustworthy checkout
--     review screen. It performs no writes and does not change how
--     submit_commerce_order computes the authoritative total — that
--     remains entirely server-side inside submit_commerce_order itself,
--     re-read from live rows at submission time, same as Phase A.
--   - Column-level REVOKE on store_profiles for `anon`: the blanket
--     `GRANT SELECT ... TO anon, authenticated` from
--     20260308190500_codify_anon_authenticated_table_grants.sql (further
--     column-blind) means RLS alone can't stop an anon caller from
--     directly querying status_reason/reviewed_by/reviewed_at on an
--     active store via PostgREST column selection, bypassing the RPC's
--     safe field list entirely. `anon` never has any legitimate reason to
--     read these (an anonymous session cannot own a company), so this is
--     revoked outright for `anon` with zero legitimate breakage. It is
--     NOT revoked from `authenticated`, because the existing, already-
--     deployed Phase B vendor settings page
--     (vendor-commerce-service.ts fetchStoreProfile) legitimately reads
--     its OWN store's status_reason/reviewed_at as an authenticated
--     company_owner/dispatcher — Postgres column grants can't be
--     conditioned per-row, so a blanket authenticated-role revoke would
--     break that deployed feature. The residual (an OTP-verified
--     customer session could in principle read another store's
--     status_reason via a raw PostgREST call) is a pre-existing Phase A
--     RLS characteristic, not something Phase C introduces, and is noted
--     in the Phase C report rather than silently left unaddressed.

-- ---------------------------------------------------------------------------
-- Public storefront catalog — one safe, anon-callable read.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_public_store_catalog(p_slug TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_store public.store_profiles;
  v_result JSONB;
BEGIN
  SELECT * INTO v_store FROM public.store_profiles WHERE slug = p_slug;

  -- Identical response (NULL) whether the slug never existed or exists but
  -- isn't publicly visible (draft/pending_review/suspended/rejected, or its
  -- company is inactive/marketplace_suspended) — deliberately not
  -- distinguishing the two, so a public caller can't use this endpoint to
  -- probe a store's private review state.
  IF v_store.company_id IS NULL OR NOT public.store_is_publicly_visible(v_store.company_id) THEN
    RETURN NULL;
  END IF;

  SELECT jsonb_build_object(
    'store', jsonb_build_object(
      'company_id', v_store.company_id,
      'slug', v_store.slug,
      'display_name', v_store.display_name,
      'description', v_store.description,
      'logo_url', v_store.logo_url,
      'banner_url', v_store.banner_url,
      'business_hours', v_store.business_hours,
      'allow_cash_on_delivery', v_store.allow_cash_on_delivery
    ),
    'categories', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', c.id, 'name', c.name, 'sort_order', c.sort_order
      ) ORDER BY c.sort_order), '[]'::JSONB)
      FROM public.product_categories c
      WHERE c.company_id = v_store.company_id AND c.is_active = true
    ),
    'products', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', p.id,
        'category_id', p.category_id,
        'name', p.name,
        'description', p.description,
        'price_lrd_cents', p.price_lrd_cents,
        'currency', p.currency,
        'tracks_inventory', p.tracks_inventory,
        'sort_order', p.sort_order,
        'available', CASE
          WHEN NOT p.tracks_inventory THEN true
          ELSE COALESCE((
            SELECT (s.quantity_on_hand - s.quantity_reserved) > 0
            FROM public.product_stock s WHERE s.product_id = p.id
          ), false)
        END,
        'images', (
          SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'id', img.id, 'storage_path', img.storage_path, 'sort_order', img.sort_order
          ) ORDER BY img.sort_order), '[]'::JSONB)
          FROM public.product_images img WHERE img.product_id = p.id
        ),
        'option_groups', (
          SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'id', g.id, 'name', g.name, 'selection_type', g.selection_type,
            'is_required', g.is_required, 'sort_order', g.sort_order,
            'options', (
              SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'id', o.id, 'name', o.name, 'price_delta_lrd_cents', o.price_delta_lrd_cents
              ) ORDER BY o.sort_order), '[]'::JSONB)
              FROM public.product_options o
              WHERE o.option_group_id = g.id AND o.is_active = true
            )
          ) ORDER BY g.sort_order), '[]'::JSONB)
          FROM public.product_option_groups g WHERE g.product_id = p.id
        )
      ) ORDER BY p.sort_order), '[]'::JSONB)
      FROM public.products p
      WHERE p.company_id = v_store.company_id AND p.status = 'active'
      LIMIT 500
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_public_store_catalog(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_store_catalog(TEXT) TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- Cart summary — live-priced, owner-scoped, read-only. Presentation only:
-- submit_commerce_order re-derives every price from live rows itself and
-- never trusts anything computed here.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_cart_summary(p_cart_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cart public.carts;
  v_items JSONB;
  v_subtotal INT;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT * INTO v_cart FROM public.carts WHERE id = p_cart_id AND customer_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'cart_not_found'; END IF;

  SELECT
    COALESCE(jsonb_agg(jsonb_build_object(
      'cart_item_id', row.cart_item_id,
      'product_id', row.product_id,
      'product_name', row.product_name,
      'product_available', row.product_available,
      'unit_price_lrd_cents', row.unit_price_lrd_cents,
      'quantity', row.quantity,
      'selected_options', row.selected_options,
      'line_total_lrd_cents', row.unit_price_lrd_cents * row.quantity
    ) ORDER BY row.created_at), '[]'::JSONB),
    COALESCE(SUM(row.unit_price_lrd_cents * row.quantity), 0)::INT
  INTO v_items, v_subtotal
  FROM (
    SELECT
      ci.id AS cart_item_id,
      ci.created_at,
      p.id AS product_id,
      p.name AS product_name,
      (p.status = 'active') AS product_available,
      p.price_lrd_cents + COALESCE((
        SELECT SUM(po.price_delta_lrd_cents)
        FROM public.product_options po
        WHERE po.id IN (SELECT (jsonb_array_elements_text(ci.selected_options))::UUID)
      ), 0) AS unit_price_lrd_cents,
      ci.quantity,
      COALESCE((
        SELECT jsonb_agg(jsonb_build_object('name', po.name, 'price_delta_lrd_cents', po.price_delta_lrd_cents))
        FROM public.product_options po
        WHERE po.id IN (SELECT (jsonb_array_elements_text(ci.selected_options))::UUID)
      ), '[]'::JSONB) AS selected_options
    FROM public.cart_items ci
    JOIN public.products p ON p.id = ci.product_id
    WHERE ci.cart_id = p_cart_id
  ) row;

  RETURN jsonb_build_object(
    'cart_id', v_cart.id,
    'vendor_company_id', v_cart.vendor_company_id,
    'items', v_items,
    'subtotal_lrd_cents', v_subtotal
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_cart_summary(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_cart_summary(UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- store_profiles column-level hardening for anon (see header comment).
--
-- Postgres column privileges are ADDITIVE on top of table-level privileges,
-- not subtractive — a column-level REVOKE alone cannot carve an exception
-- out of an existing table-level GRANT (the table-level grant still covers
-- every column). The only way to actually narrow what `anon` can SELECT is
-- to revoke the table-level grant entirely and re-grant SELECT on just the
-- safe column list.
-- ---------------------------------------------------------------------------
REVOKE SELECT ON public.store_profiles FROM anon;
GRANT SELECT (
  company_id, slug, display_name, description, logo_url, banner_url,
  business_hours, allow_cash_on_delivery, status, created_at, updated_at
) ON public.store_profiles TO anon;
