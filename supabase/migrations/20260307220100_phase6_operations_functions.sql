-- DeliveryOS · Phase 6: operations RPCs, RLS, profitability, webhooks

-- ---------------------------------------------------------------------------
-- Branch access helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.user_branch_ids(p_company_id UUID)
RETURNS SETOF UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT branch_id FROM public.company_user_branches
  WHERE company_id = p_company_id AND user_id = auth.uid()
  UNION
  SELECT id FROM public.company_branches
  WHERE company_id = p_company_id
    AND public.has_company_role(p_company_id, ARRAY['company_owner']::public.company_role[])
    AND NOT EXISTS (
      SELECT 1 FROM public.company_user_branches cub
      WHERE cub.company_id = p_company_id AND cub.user_id = auth.uid()
    );
$$;

CREATE OR REPLACE FUNCTION public.can_access_branch(p_company_id UUID, p_branch_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    public.is_super_admin()
    OR (
      p_company_id IN (SELECT public.user_company_ids())
      AND (
        p_branch_id IS NULL
        OR p_branch_id IN (SELECT public.user_branch_ids(p_company_id))
      )
    );
$$;

-- ---------------------------------------------------------------------------
-- Feature flags (Phase 6)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.can_use_feature(p_company_id UUID, p_feature_key TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cs public.company_subscriptions;
  v_plan public.subscriptions;
  v_ok BOOLEAN := false;
BEGIN
  v_cs := public.get_active_company_subscription(p_company_id);
  IF v_cs.id IS NULL OR v_cs.status NOT IN ('trialing', 'active') THEN
    RETURN false;
  END IF;
  IF v_cs.current_period_end < now() THEN
    RETURN false;
  END IF;

  SELECT * INTO v_plan FROM public.subscriptions WHERE id = v_cs.plan_id AND is_active = true;
  IF NOT FOUND THEN
    RETURN false;
  END IF;

  v_ok := CASE p_feature_key
    WHEN 'proof_of_delivery' THEN v_plan.proof_of_delivery
    WHEN 'advanced_reports' THEN v_plan.advanced_reports
    WHEN 'api_access' THEN v_plan.api_access
    WHEN 'gps_tracking' THEN v_plan.gps_tracking
    WHEN 'custom_branding' THEN v_plan.custom_branding
    WHEN 'sms_notifications' THEN v_plan.monthly_sms_allowance > 0
    WHEN 'multi_branch' THEN v_plan.multi_branch
    WHEN 'fleet_management' THEN v_plan.fleet_management
    WHEN 'inventory' THEN v_plan.inventory
    WHEN 'warehouse_management' THEN v_plan.warehouse_management
    WHEN 'cod_reconciliation' THEN v_plan.cod_reconciliation
    WHEN 'profitability_reports' THEN v_plan.profitability_reports
    WHEN 'sms' THEN v_cs.status IN ('trialing', 'active')
    ELSE COALESCE((v_plan.features ->> p_feature_key)::BOOLEAN, false)
  END;

  RETURN COALESCE(v_ok, false);
END;
$$;

-- ---------------------------------------------------------------------------
-- Branch management
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.upsert_company_branch(p_payload JSONB)
RETURNS public.company_branches
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID := (p_payload ->> 'company_id')::UUID;
  v_id UUID := NULLIF(p_payload ->> 'id', '')::UUID;
  v_row public.company_branches;
BEGIN
  IF NOT public.can_use_feature(v_company_id, 'multi_branch')
     AND v_id IS NULL THEN
    RAISE EXCEPTION 'multi_branch_not_enabled';
  END IF;

  IF NOT public.has_company_role(v_company_id, ARRAY['company_owner']::public.company_role[])
     AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF v_id IS NULL THEN
    INSERT INTO public.company_branches (
      company_id, name, code, address, city, latitude, longitude, phone, is_active
    ) VALUES (
      v_company_id,
      p_payload ->> 'name',
      p_payload ->> 'code',
      p_payload ->> 'address',
      p_payload ->> 'city',
      NULLIF(p_payload ->> 'latitude', '')::DOUBLE PRECISION,
      NULLIF(p_payload ->> 'longitude', '')::DOUBLE PRECISION,
      p_payload ->> 'phone',
      COALESCE((p_payload ->> 'is_active')::BOOLEAN, true)
    )
    RETURNING * INTO v_row;
  ELSE
    UPDATE public.company_branches SET
      name = COALESCE(p_payload ->> 'name', name),
      address = COALESCE(p_payload ->> 'address', address),
      city = COALESCE(p_payload ->> 'city', city),
      phone = COALESCE(p_payload ->> 'phone', phone),
      is_active = COALESCE((p_payload ->> 'is_active')::BOOLEAN, is_active)
    WHERE id = v_id AND company_id = v_company_id
    RETURNING * INTO v_row;
  END IF;

  PERFORM public.log_audit_event(v_company_id, 'branch_upserted', 'company_branches', v_row.id, to_jsonb(v_row));
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_company_branch TO authenticated;

CREATE OR REPLACE FUNCTION public.list_company_branches(p_company_id UUID)
RETURNS SETOF public.company_branches
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT b.*
  FROM public.company_branches b
  WHERE b.company_id = p_company_id
    AND b.id IN (SELECT public.user_branch_ids(p_company_id))
  ORDER BY b.name;
$$;

GRANT EXECUTE ON FUNCTION public.list_company_branches TO authenticated;

-- ---------------------------------------------------------------------------
-- Fleet: vehicles
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.upsert_vehicle(p_payload JSONB)
RETURNS public.vehicles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID := (p_payload ->> 'company_id')::UUID;
  v_branch_id UUID := NULLIF(p_payload ->> 'branch_id', '')::UUID;
  v_id UUID := NULLIF(p_payload ->> 'id', '')::UUID;
  v_row public.vehicles;
BEGIN
  IF NOT public.can_use_feature(v_company_id, 'fleet_management') THEN
    RAISE EXCEPTION 'fleet_not_enabled';
  END IF;
  IF NOT public.can_access_branch(v_company_id, v_branch_id) THEN
    RAISE EXCEPTION 'forbidden_branch';
  END IF;
  IF NOT public.has_company_role(
    v_company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[]
  ) AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF v_id IS NULL THEN
    INSERT INTO public.vehicles (
      company_id, branch_id, vehicle_code, vehicle_type, make, model, year,
      registration_number, color, status, odometer, is_active
    ) VALUES (
      v_company_id, v_branch_id,
      p_payload ->> 'vehicle_code',
      COALESCE((p_payload ->> 'vehicle_type')::public.vehicle_type, 'motorcycle'),
      p_payload ->> 'make', p_payload ->> 'model',
      NULLIF(p_payload ->> 'year', '')::INT,
      p_payload ->> 'registration_number', p_payload ->> 'color',
      COALESCE((p_payload ->> 'status')::public.vehicle_status, 'available'),
      COALESCE((p_payload ->> 'odometer')::INT, 0),
      COALESCE((p_payload ->> 'is_active')::BOOLEAN, true)
    )
    RETURNING * INTO v_row;
  ELSE
    UPDATE public.vehicles SET
      branch_id = COALESCE(v_branch_id, branch_id),
      make = COALESCE(p_payload ->> 'make', make),
      model = COALESCE(p_payload ->> 'model', model),
      status = COALESCE((p_payload ->> 'status')::public.vehicle_status, status),
      odometer = COALESCE((p_payload ->> 'odometer')::INT, odometer),
      is_active = COALESCE((p_payload ->> 'is_active')::BOOLEAN, is_active)
    WHERE id = v_id AND company_id = v_company_id
    RETURNING * INTO v_row;
  END IF;

  PERFORM public.log_audit_event(v_company_id, 'vehicle_upserted', 'vehicles', v_row.id, to_jsonb(v_row));
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_vehicle TO authenticated;

CREATE OR REPLACE FUNCTION public.assign_rider_vehicle(p_rider_id UUID, p_vehicle_id UUID)
RETURNS public.rider_vehicle_assignments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rider public.riders;
  v_vehicle public.vehicles;
  v_row public.rider_vehicle_assignments;
BEGIN
  SELECT * INTO v_rider FROM public.riders WHERE id = p_rider_id;
  SELECT * INTO v_vehicle FROM public.vehicles WHERE id = p_vehicle_id;
  IF NOT FOUND OR v_rider.company_id <> v_vehicle.company_id THEN
    RAISE EXCEPTION 'invalid_assignment';
  END IF;
  IF NOT public.can_use_feature(v_rider.company_id, 'fleet_management') THEN
    RAISE EXCEPTION 'fleet_not_enabled';
  END IF;
  IF NOT public.has_company_role(
    v_rider.company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[]
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE public.rider_vehicle_assignments
  SET ended_at = now()
  WHERE vehicle_id = p_vehicle_id AND ended_at IS NULL;

  UPDATE public.rider_vehicle_assignments
  SET ended_at = now()
  WHERE rider_id = p_rider_id AND ended_at IS NULL;

  INSERT INTO public.rider_vehicle_assignments (
    company_id, rider_id, vehicle_id, assigned_by
  ) VALUES (
    v_rider.company_id, p_rider_id, p_vehicle_id, auth.uid()
  )
  RETURNING * INTO v_row;

  UPDATE public.vehicles SET status = 'assigned' WHERE id = p_vehicle_id;

  PERFORM public.log_audit_event(
    v_rider.company_id, 'vehicle_assigned', 'rider_vehicle_assignments', v_row.id, to_jsonb(v_row)
  );
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.assign_rider_vehicle TO authenticated;

CREATE OR REPLACE FUNCTION public.record_vehicle_maintenance(p_payload JSONB)
RETURNS public.vehicle_maintenance_records
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_vehicle_id UUID := (p_payload ->> 'vehicle_id')::UUID;
  v_vehicle public.vehicles;
  v_row public.vehicle_maintenance_records;
BEGIN
  SELECT * INTO v_vehicle FROM public.vehicles WHERE id = v_vehicle_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  IF NOT public.can_use_feature(v_vehicle.company_id, 'fleet_management') THEN
    RAISE EXCEPTION 'fleet_not_enabled';
  END IF;

  INSERT INTO public.vehicle_maintenance_records (
    company_id, vehicle_id, maintenance_type, description, vendor,
    cost_cents, currency, odometer, performed_at, next_service_date,
    next_service_odometer, notes
  ) VALUES (
    v_vehicle.company_id, v_vehicle_id,
    p_payload ->> 'maintenance_type',
    p_payload ->> 'description',
    p_payload ->> 'vendor',
    COALESCE((p_payload ->> 'cost_cents')::INT, 0),
    COALESCE(p_payload ->> 'currency', 'LRD'),
    NULLIF(p_payload ->> 'odometer', '')::INT,
    COALESCE((p_payload ->> 'performed_at')::TIMESTAMPTZ, now()),
    NULLIF(p_payload ->> 'next_service_date', '')::DATE,
    NULLIF(p_payload ->> 'next_service_odometer', '')::INT,
    p_payload ->> 'notes'
  )
  RETURNING * INTO v_row;

  IF v_row.next_service_date IS NOT NULL AND v_row.next_service_date <= CURRENT_DATE + 7 THEN
    PERFORM public.enqueue_webhook_event(
      v_vehicle.company_id, 'vehicle.maintenance_due', v_row.id, to_jsonb(v_row)
    );
  END IF;

  PERFORM public.log_audit_event(
    v_vehicle.company_id, 'maintenance_recorded', 'vehicle_maintenance_records', v_row.id, to_jsonb(v_row)
  );
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_vehicle_maintenance TO authenticated;

-- ---------------------------------------------------------------------------
-- Inventory core (ledger)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._inventory_apply_movement(
  p_company_id UUID,
  p_warehouse_id UUID,
  p_item_id UUID,
  p_quantity NUMERIC,
  p_movement_type public.inventory_movement_type,
  p_reference_type TEXT,
  p_reference_id UUID,
  p_notes TEXT
)
RETURNS public.inventory_movements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_stock public.inventory_stock;
  v_move public.inventory_movements;
  v_delta NUMERIC;
  v_available NUMERIC;
  v_item public.inventory_items;
BEGIN
  SELECT * INTO v_item FROM public.inventory_items WHERE id = p_item_id AND company_id = p_company_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'item_not_found'; END IF;

  INSERT INTO public.inventory_stock (company_id, warehouse_id, inventory_item_id)
  VALUES (p_company_id, p_warehouse_id, p_item_id)
  ON CONFLICT (warehouse_id, inventory_item_id) DO NOTHING;

  SELECT * INTO v_stock
  FROM public.inventory_stock
  WHERE warehouse_id = p_warehouse_id AND inventory_item_id = p_item_id
  FOR UPDATE;

  v_delta := CASE p_movement_type
    WHEN 'receipt' THEN p_quantity
    WHEN 'transfer_in' THEN p_quantity
    WHEN 'return' THEN p_quantity
    WHEN 'release' THEN p_quantity
    WHEN 'adjustment' THEN p_quantity
    WHEN 'dispatch' THEN -p_quantity
    WHEN 'transfer_out' THEN -p_quantity
    WHEN 'reservation' THEN 0
    ELSE p_quantity
  END;

  IF p_movement_type = 'reservation' THEN
    v_available := v_stock.quantity_on_hand - v_stock.quantity_reserved;
    IF v_available < p_quantity THEN
      RAISE EXCEPTION 'insufficient_stock';
    END IF;
    UPDATE public.inventory_stock
    SET quantity_reserved = quantity_reserved + p_quantity, updated_at = now()
    WHERE id = v_stock.id;
  ELSIF p_movement_type = 'release' THEN
    UPDATE public.inventory_stock
    SET quantity_reserved = GREATEST(0, quantity_reserved - p_quantity), updated_at = now()
    WHERE id = v_stock.id;
  ELSE
    IF v_delta < 0 AND (v_stock.quantity_on_hand + v_delta) < 0 THEN
      RAISE EXCEPTION 'insufficient_stock';
    END IF;
    UPDATE public.inventory_stock
    SET quantity_on_hand = quantity_on_hand + v_delta, updated_at = now()
    WHERE id = v_stock.id;
  END IF;

  INSERT INTO public.inventory_movements (
    company_id, warehouse_id, inventory_item_id, quantity, movement_type,
    reference_type, reference_id, notes, actor_user_id
  ) VALUES (
    p_company_id, p_warehouse_id, p_item_id, p_quantity, p_movement_type,
    p_reference_type, p_reference_id, p_notes, auth.uid()
  )
  RETURNING * INTO v_move;

  SELECT quantity_on_hand - quantity_reserved INTO v_available
  FROM public.inventory_stock WHERE id = v_stock.id;

  IF v_item.reorder_threshold IS NOT NULL AND v_available <= v_item.reorder_threshold THEN
    PERFORM public.enqueue_webhook_event(
      p_company_id, 'inventory.low_stock', v_item.id,
      jsonb_build_object('item_id', v_item.id, 'warehouse_id', p_warehouse_id, 'available', v_available)
    );
  END IF;

  RETURN v_move;
END;
$$;

REVOKE ALL ON FUNCTION public._inventory_apply_movement FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.inventory_receive_stock(
  p_warehouse_id UUID,
  p_item_id UUID,
  p_quantity NUMERIC,
  p_notes TEXT DEFAULT NULL
)
RETURNS public.inventory_movements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_wh public.warehouses;
BEGIN
  SELECT * INTO v_wh FROM public.warehouses WHERE id = p_warehouse_id;
  IF NOT public.can_use_feature(v_wh.company_id, 'inventory') THEN
    RAISE EXCEPTION 'inventory_not_enabled';
  END IF;
  IF NOT public.has_company_role(
    v_wh.company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[]
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  RETURN public._inventory_apply_movement(
    v_wh.company_id, p_warehouse_id, p_item_id, p_quantity,
    'receipt', 'manual', NULL, p_notes
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.inventory_receive_stock TO authenticated;

CREATE OR REPLACE FUNCTION public.inventory_adjust_stock(
  p_warehouse_id UUID,
  p_item_id UUID,
  p_quantity_delta NUMERIC,
  p_notes TEXT DEFAULT NULL
)
RETURNS public.inventory_movements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_wh public.warehouses;
BEGIN
  SELECT * INTO v_wh FROM public.warehouses WHERE id = p_warehouse_id;
  IF NOT public.can_use_feature(v_wh.company_id, 'inventory') THEN
    RAISE EXCEPTION 'inventory_not_enabled';
  END IF;
  IF NOT public.has_company_role(v_wh.company_id, ARRAY['company_owner']::public.company_role[]) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  PERFORM public.log_audit_event(v_wh.company_id, 'inventory_adjustment', 'inventory_items', p_item_id,
    jsonb_build_object('delta', p_quantity_delta));

  RETURN public._inventory_apply_movement(
    v_wh.company_id, p_warehouse_id, p_item_id, p_quantity_delta,
    'adjustment', 'adjustment', NULL, p_notes
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.inventory_adjust_stock TO authenticated;

-- ---------------------------------------------------------------------------
-- Cash settlements
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_cash_settlement(p_rider_id UUID)
RETURNS public.cash_settlements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rider public.riders;
  v_row public.cash_settlements;
  v_total INT := 0;
  v_pay public.payments;
BEGIN
  SELECT * INTO v_rider FROM public.riders WHERE id = p_rider_id;
  IF NOT public.can_use_feature(v_rider.company_id, 'cod_reconciliation') THEN
    RAISE EXCEPTION 'cod_reconciliation_not_enabled';
  END IF;

  INSERT INTO public.cash_settlements (company_id, branch_id, rider_id, status)
  VALUES (v_rider.company_id, v_rider.branch_id, p_rider_id, 'open')
  RETURNING * INTO v_row;

  FOR v_pay IN
    SELECT p.* FROM public.payments p
    JOIN public.deliveries d ON d.id = p.delivery_id
    WHERE d.rider_id = p_rider_id
      AND p.status = 'collected'
      AND NOT EXISTS (SELECT 1 FROM public.cash_settlement_items csi WHERE csi.payment_id = p.id)
  LOOP
    INSERT INTO public.cash_settlement_items (company_id, settlement_id, payment_id, amount_cents)
    VALUES (v_rider.company_id, v_row.id, v_pay.id, v_pay.amount_lrd_cents);
    v_total := v_total + v_pay.amount_lrd_cents;
  END LOOP;

  UPDATE public.cash_settlements SET total_expected_cents = v_total WHERE id = v_row.id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_cash_settlement TO authenticated;

CREATE OR REPLACE FUNCTION public.submit_cash_settlement(
  p_settlement_id UUID,
  p_received_cents INT
)
RETURNS public.cash_settlements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.cash_settlements;
BEGIN
  SELECT * INTO v_row FROM public.cash_settlements WHERE id = p_settlement_id FOR UPDATE;
  IF v_row.status <> 'open' THEN RAISE EXCEPTION 'invalid_status'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.riders r
    WHERE r.id = v_row.rider_id AND r.user_id = auth.uid()
  ) AND NOT public.has_company_role(
    v_row.company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[]
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE public.cash_settlements SET
    status = 'submitted',
    total_received_cents = p_received_cents,
    submitted_at = now()
  WHERE id = p_settlement_id
  RETURNING * INTO v_row;

  PERFORM public.enqueue_webhook_event(
    v_row.company_id, 'cash_settlement.submitted', v_row.id, to_jsonb(v_row)
  );
  PERFORM public.log_audit_event(
    v_row.company_id, 'cash_settlement_submitted', 'cash_settlements', v_row.id, to_jsonb(v_row)
  );
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_cash_settlement TO authenticated;

CREATE OR REPLACE FUNCTION public.reconcile_cash_settlement(p_settlement_id UUID)
RETURNS public.cash_settlements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.cash_settlements;
  v_item public.cash_settlement_items;
BEGIN
  SELECT * INTO v_row FROM public.cash_settlements WHERE id = p_settlement_id FOR UPDATE;
  IF NOT public.has_company_role(
    v_row.company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[]
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF v_row.status NOT IN ('submitted', 'verified') THEN
    RAISE EXCEPTION 'invalid_status';
  END IF;

  FOR v_item IN SELECT * FROM public.cash_settlement_items WHERE settlement_id = p_settlement_id
  LOOP
    PERFORM public.mark_payment_deposited(v_item.payment_id);
  END LOOP;

  UPDATE public.cash_settlements SET
    status = 'reconciled',
    reconciled_at = now(),
    verified_by = auth.uid()
  WHERE id = p_settlement_id
  RETURNING * INTO v_row;

  PERFORM public.enqueue_webhook_event(
    v_row.company_id, 'cash_settlement.reconciled', v_row.id, to_jsonb(v_row)
  );
  PERFORM public.log_audit_event(
    v_row.company_id, 'cash_settlement_reconciled', 'cash_settlements', v_row.id, to_jsonb(v_row)
  );
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.reconcile_cash_settlement TO authenticated;

-- ---------------------------------------------------------------------------
-- Returns (separate workflow)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.request_delivery_return(
  p_delivery_id UUID,
  p_reason TEXT
)
RETURNS public.delivery_returns
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_d public.deliveries;
  v_row public.delivery_returns;
BEGIN
  SELECT * INTO v_d FROM public.deliveries WHERE id = p_delivery_id;
  IF NOT public.has_company_role(
    v_d.company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[]
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  INSERT INTO public.delivery_returns (
    company_id, delivery_id, branch_id, rider_id, reason, requested_by, status
  ) VALUES (
    v_d.company_id, p_delivery_id, v_d.branch_id, v_d.rider_id, p_reason, auth.uid(), 'return_requested'
  )
  ON CONFLICT (delivery_id) DO UPDATE SET
    reason = EXCLUDED.reason,
    status = 'return_requested',
    updated_at = now()
  RETURNING * INTO v_row;

  PERFORM public.log_audit_event(v_d.company_id, 'return_requested', 'delivery_returns', v_row.id, to_jsonb(v_row));
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.request_delivery_return TO authenticated;

CREATE OR REPLACE FUNCTION public.advance_delivery_return(
  p_return_id UUID,
  p_status public.delivery_return_status
)
RETURNS public.delivery_returns
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.delivery_returns;
BEGIN
  SELECT * INTO v_row FROM public.delivery_returns WHERE id = p_return_id FOR UPDATE;
  IF NOT public.has_company_role(
    v_row.company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[]
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE public.delivery_returns SET
    status = p_status,
    in_transit_at = CASE WHEN p_status = 'return_in_transit' THEN now() ELSE in_transit_at END,
    returned_at = CASE WHEN p_status = 'returned' THEN now() ELSE returned_at END,
    updated_at = now()
  WHERE id = p_return_id
  RETURNING * INTO v_row;

  IF p_status = 'returned' THEN
    PERFORM public.enqueue_webhook_event(
      v_row.company_id, 'delivery.returned', v_row.delivery_id, to_jsonb(v_row)
    );
  END IF;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.advance_delivery_return TO authenticated;

-- ---------------------------------------------------------------------------
-- Profitability RPC
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_profitability_report(
  p_company_id UUID,
  p_branch_id UUID DEFAULT NULL,
  p_days INT DEFAULT 30
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_since TIMESTAMPTZ := now() - make_interval(days => p_days);
  v_revenue BIGINT;
  v_fleet BIGINT;
  v_rider_exp BIGINT;
  v_sms BIGINT;
BEGIN
  IF NOT public.can_use_feature(p_company_id, 'profitability_reports') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF NOT public.can_access_branch(p_company_id, p_branch_id) THEN
    RAISE EXCEPTION 'forbidden_branch';
  END IF;

  SELECT COALESCE(SUM(d.delivery_fee_lrd_cents), 0) INTO v_revenue
  FROM public.deliveries d
  WHERE d.company_id = p_company_id
    AND d.status = 'delivered'
    AND d.delivered_at >= v_since
    AND (p_branch_id IS NULL OR d.branch_id = p_branch_id);

  SELECT COALESCE(SUM(f.amount_cents), 0) INTO v_fleet
  FROM public.fleet_expenses f
  WHERE f.company_id = p_company_id AND f.expense_date >= v_since::DATE;

  SELECT COALESCE(SUM(r.amount_cents), 0) INTO v_rider_exp
  FROM public.rider_expenses r
  WHERE r.company_id = p_company_id AND r.expense_date >= v_since::DATE;

  SELECT COALESCE(SUM(COALESCE(o.cost_cents, 0)), 0) INTO v_sms
  FROM public.sms_outbox o
  WHERE o.company_id = p_company_id AND o.sent_at >= v_since;

  RETURN jsonb_build_object(
    'period_days', p_days,
    'branch_id', p_branch_id,
    'revenue_cents', v_revenue,
    'fleet_expense_cents', v_fleet,
    'rider_expense_cents', v_rider_exp,
    'sms_cost_cents', v_sms,
    'total_cost_cents', v_fleet + v_rider_exp + v_sms,
    'gross_margin_cents', v_revenue - (v_fleet + v_rider_exp + v_sms),
    'by_zone', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'zone_id', z.id,
        'zone_name', z.name,
        'revenue_cents', COALESCE(SUM(d.delivery_fee_lrd_cents), 0)
      )), '[]'::JSONB)
      FROM public.delivery_zones z
      LEFT JOIN public.deliveries d ON d.delivery_zone_id = z.id
        AND d.status = 'delivered' AND d.delivered_at >= v_since
        AND (p_branch_id IS NULL OR d.branch_id = p_branch_id)
      WHERE z.company_id = p_company_id
      GROUP BY z.id, z.name
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_profitability_report TO authenticated;

-- Paginated list helpers
CREATE OR REPLACE FUNCTION public.list_vehicles_page(
  p_company_id UUID,
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
BEGIN
  IF p_company_id NOT IN (SELECT public.user_company_ids()) AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  RETURN jsonb_build_object(
    'total', (SELECT COUNT(*) FROM public.vehicles v WHERE v.company_id = p_company_id
      AND (p_search IS NULL OR v.vehicle_code ILIKE '%' || p_search || '%')),
    'rows', COALESCE((
      SELECT jsonb_agg(to_jsonb(v.*) ORDER BY v.created_at DESC)
      FROM (
        SELECT * FROM public.vehicles v
        WHERE v.company_id = p_company_id
          AND (p_search IS NULL OR v.vehicle_code ILIKE '%' || p_search || '%')
        ORDER BY v.created_at DESC
        LIMIT p_limit OFFSET p_offset
      ) v
    ), '[]'::JSONB)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_vehicles_page TO authenticated;

CREATE OR REPLACE FUNCTION public.upsert_warehouse(p_payload JSONB)
RETURNS public.warehouses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID := (p_payload ->> 'company_id')::UUID;
  v_row public.warehouses;
BEGIN
  IF NOT public.can_use_feature(v_company_id, 'warehouse_management') THEN
    RAISE EXCEPTION 'warehouse_not_enabled';
  END IF;
  IF NOT public.has_company_role(v_company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[]) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  INSERT INTO public.warehouses (company_id, branch_id, name, code, address, is_active)
  VALUES (
    v_company_id,
    NULLIF(p_payload ->> 'branch_id', '')::UUID,
    p_payload ->> 'name',
    p_payload ->> 'code',
    p_payload ->> 'address',
    COALESCE((p_payload ->> 'is_active')::BOOLEAN, true)
  )
  ON CONFLICT (company_id, code) DO UPDATE SET
    name = EXCLUDED.name,
    address = EXCLUDED.address,
    is_active = EXCLUDED.is_active
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_warehouse TO authenticated;

CREATE OR REPLACE FUNCTION public.upsert_inventory_item(p_payload JSONB)
RETURNS public.inventory_items
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID := (p_payload ->> 'company_id')::UUID;
  v_row public.inventory_items;
BEGIN
  IF NOT public.can_use_feature(v_company_id, 'inventory') THEN
    RAISE EXCEPTION 'inventory_not_enabled';
  END IF;
  INSERT INTO public.inventory_items (
    company_id, sku, name, description, barcode, unit, reorder_threshold, is_active
  ) VALUES (
    v_company_id,
    p_payload ->> 'sku',
    p_payload ->> 'name',
    p_payload ->> 'description',
    p_payload ->> 'barcode',
    COALESCE(p_payload ->> 'unit', 'ea'),
    NULLIF(p_payload ->> 'reorder_threshold', '')::INT,
    COALESCE((p_payload ->> 'is_active')::BOOLEAN, true)
  )
  ON CONFLICT (company_id, sku) DO UPDATE SET
    name = EXCLUDED.name,
    reorder_threshold = EXCLUDED.reorder_threshold,
    is_active = EXCLUDED.is_active
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_inventory_item TO authenticated;

-- Patch admin_upsert_plan for Phase 6 flags
CREATE OR REPLACE FUNCTION public.admin_upsert_plan(p_payload JSONB)
RETURNS public.subscriptions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.subscriptions;
  v_id UUID := (p_payload ->> 'id')::UUID;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  IF v_id IS NULL THEN
    INSERT INTO public.subscriptions (
      slug, name, max_riders, max_deliveries_per_month, price_lrd_cents, currency,
      monthly_sms_allowance, proof_of_delivery, advanced_reports, api_access,
      gps_tracking, custom_branding, is_active, features,
      multi_branch, fleet_management, inventory, warehouse_management,
      cod_reconciliation, profitability_reports
    ) VALUES (
      p_payload ->> 'slug', p_payload ->> 'name',
      (p_payload ->> 'max_riders')::INT,
      NULLIF(p_payload ->> 'max_deliveries_per_month', '')::INT,
      (p_payload ->> 'price_lrd_cents')::INT,
      COALESCE(p_payload ->> 'currency', 'LRD'),
      COALESCE((p_payload ->> 'monthly_sms_allowance')::INT, 0),
      COALESCE((p_payload ->> 'proof_of_delivery')::BOOLEAN, true),
      COALESCE((p_payload ->> 'advanced_reports')::BOOLEAN, false),
      COALESCE((p_payload ->> 'api_access')::BOOLEAN, false),
      COALESCE((p_payload ->> 'gps_tracking')::BOOLEAN, false),
      COALESCE((p_payload ->> 'custom_branding')::BOOLEAN, false),
      COALESCE((p_payload ->> 'is_active')::BOOLEAN, true),
      COALESCE(p_payload -> 'features', '{}'::JSONB),
      COALESCE((p_payload ->> 'multi_branch')::BOOLEAN, false),
      COALESCE((p_payload ->> 'fleet_management')::BOOLEAN, false),
      COALESCE((p_payload ->> 'inventory')::BOOLEAN, false),
      COALESCE((p_payload ->> 'warehouse_management')::BOOLEAN, false),
      COALESCE((p_payload ->> 'cod_reconciliation')::BOOLEAN, false),
      COALESCE((p_payload ->> 'profitability_reports')::BOOLEAN, false)
    )
    RETURNING * INTO v_row;
  ELSE
    UPDATE public.subscriptions SET
      slug = COALESCE(p_payload ->> 'slug', slug),
      name = COALESCE(p_payload ->> 'name', name),
      max_riders = COALESCE((p_payload ->> 'max_riders')::INT, max_riders),
      max_deliveries_per_month = CASE
        WHEN p_payload ? 'max_deliveries_per_month' THEN NULLIF(p_payload ->> 'max_deliveries_per_month', '')::INT
        ELSE max_deliveries_per_month
      END,
      price_lrd_cents = COALESCE((p_payload ->> 'price_lrd_cents')::INT, price_lrd_cents),
      multi_branch = COALESCE((p_payload ->> 'multi_branch')::BOOLEAN, multi_branch),
      fleet_management = COALESCE((p_payload ->> 'fleet_management')::BOOLEAN, fleet_management),
      inventory = COALESCE((p_payload ->> 'inventory')::BOOLEAN, inventory),
      warehouse_management = COALESCE((p_payload ->> 'warehouse_management')::BOOLEAN, warehouse_management),
      cod_reconciliation = COALESCE((p_payload ->> 'cod_reconciliation')::BOOLEAN, cod_reconciliation),
      profitability_reports = COALESCE((p_payload ->> 'profitability_reports')::BOOLEAN, profitability_reports),
      is_active = COALESCE((p_payload ->> 'is_active')::BOOLEAN, is_active)
    WHERE id = v_id
    RETURNING * INTO v_row;
  END IF;

  PERFORM public.log_audit_event(NULL, 'plan_upserted', 'subscriptions', v_row.id, to_jsonb(v_row));
  RETURN v_row;
END;
$$;

-- inventory.received webhook on receipt
CREATE OR REPLACE FUNCTION public.inventory_receive_stock(
  p_warehouse_id UUID,
  p_item_id UUID,
  p_quantity NUMERIC,
  p_notes TEXT DEFAULT NULL
)
RETURNS public.inventory_movements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_wh public.warehouses;
  v_move public.inventory_movements;
BEGIN
  SELECT * INTO v_wh FROM public.warehouses WHERE id = p_warehouse_id;
  IF NOT public.can_use_feature(v_wh.company_id, 'inventory') THEN
    RAISE EXCEPTION 'inventory_not_enabled';
  END IF;
  IF NOT public.has_company_role(
    v_wh.company_id, ARRAY['company_owner', 'dispatcher']::public.company_role[]
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  v_move := public._inventory_apply_movement(
    v_wh.company_id, p_warehouse_id, p_item_id, p_quantity,
    'receipt', 'manual', NULL, p_notes
  );

  PERFORM public.enqueue_webhook_event(
    v_wh.company_id, 'inventory.received', v_move.id, to_jsonb(v_move)
  );
  PERFORM public.log_audit_event(v_wh.company_id, 'inventory_received', 'inventory_movements', v_move.id, to_jsonb(v_move));

  RETURN v_move;
END;
$$;

-- ---------------------------------------------------------------------------
-- RLS (SELECT tenant-scoped; mutations via RPC)
-- ---------------------------------------------------------------------------
ALTER TABLE public.company_branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_user_branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rider_vehicle_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicle_maintenance_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fleet_expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rider_expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.warehouses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_stock ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_returns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cash_settlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cash_settlement_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY company_branches_select ON public.company_branches
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR (company_id IN (SELECT public.user_company_ids())
        AND id IN (SELECT public.user_branch_ids(company_id)))
  );

CREATE POLICY vehicles_select ON public.vehicles
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR (company_id IN (SELECT public.user_company_ids())
        AND (branch_id IS NULL OR branch_id IN (SELECT public.user_branch_ids(company_id))))
  );

CREATE POLICY warehouses_select ON public.warehouses
  FOR SELECT TO authenticated
  USING (public.is_super_admin() OR company_id IN (SELECT public.user_company_ids()));

CREATE POLICY inventory_items_select ON public.inventory_items
  FOR SELECT TO authenticated
  USING (public.is_super_admin() OR company_id IN (SELECT public.user_company_ids()));

CREATE POLICY inventory_stock_select ON public.inventory_stock
  FOR SELECT TO authenticated
  USING (public.is_super_admin() OR company_id IN (SELECT public.user_company_ids()));

CREATE POLICY inventory_movements_select ON public.inventory_movements
  FOR SELECT TO authenticated
  USING (public.is_super_admin() OR company_id IN (SELECT public.user_company_ids()));

CREATE POLICY cash_settlements_select ON public.cash_settlements
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR company_id IN (SELECT public.user_company_ids())
  );

CREATE POLICY delivery_returns_select ON public.delivery_returns
  FOR SELECT TO authenticated
  USING (public.is_super_admin() OR company_id IN (SELECT public.user_company_ids()));

CREATE POLICY inventory_movements_no_write ON public.inventory_movements
  FOR ALL TO authenticated USING (false);

CREATE POLICY inventory_stock_no_write ON public.inventory_stock
  FOR ALL TO authenticated USING (false);

CREATE POLICY cash_settlement_items_no_write ON public.cash_settlement_items
  FOR ALL TO authenticated USING (false);
