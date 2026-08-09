-- DeliveryOS · Phase 6: branches, fleet, inventory, returns, COD settlements

-- ---------------------------------------------------------------------------
-- Phase 6 plan feature flags on subscriptions catalog
-- ---------------------------------------------------------------------------
ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS multi_branch BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS fleet_management BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS inventory BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS warehouse_management BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS cod_reconciliation BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS profitability_reports BOOLEAN NOT NULL DEFAULT false;

UPDATE public.subscriptions SET
  fleet_management = (slug IN ('business', 'enterprise')),
  multi_branch = (slug = 'enterprise'),
  inventory = (slug = 'enterprise'),
  warehouse_management = (slug = 'enterprise'),
  cod_reconciliation = (slug IN ('business', 'enterprise')),
  profitability_reports = (slug IN ('business', 'enterprise')),
  gps_tracking = (slug IN ('business', 'enterprise'))
WHERE slug IN ('starter', 'business', 'enterprise');

-- ---------------------------------------------------------------------------
-- Branches
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.company_branches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  code TEXT NOT NULL,
  address TEXT,
  city TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  phone TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (company_id, code)
);

CREATE INDEX IF NOT EXISTS idx_company_branches_company ON public.company_branches (company_id, is_active);

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS default_branch_id UUID REFERENCES public.company_branches (id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS public.company_user_branches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  branch_id UUID NOT NULL REFERENCES public.company_branches (id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (company_id, user_id, branch_id)
);

CREATE INDEX IF NOT EXISTS idx_company_user_branches_user ON public.company_user_branches (company_id, user_id);

-- ---------------------------------------------------------------------------
-- Fleet
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE public.vehicle_type AS ENUM (
    'motorcycle', 'car', 'van', 'truck', 'bicycle', 'other'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE public.vehicle_status AS ENUM (
    'available', 'assigned', 'maintenance', 'inactive'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS public.vehicles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  branch_id UUID REFERENCES public.company_branches (id) ON DELETE SET NULL,
  vehicle_code TEXT NOT NULL,
  vehicle_type public.vehicle_type NOT NULL DEFAULT 'motorcycle',
  make TEXT,
  model TEXT,
  year INT,
  registration_number TEXT,
  color TEXT,
  status public.vehicle_status NOT NULL DEFAULT 'available',
  odometer INT NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (company_id, vehicle_code)
);

CREATE INDEX IF NOT EXISTS idx_vehicles_company ON public.vehicles (company_id, is_active);

CREATE TABLE IF NOT EXISTS public.rider_vehicle_assignments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  rider_id UUID NOT NULL REFERENCES public.riders (id) ON DELETE CASCADE,
  vehicle_id UUID NOT NULL REFERENCES public.vehicles (id) ON DELETE CASCADE,
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at TIMESTAMPTZ,
  assigned_by UUID REFERENCES auth.users (id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_rider_vehicle_one_active
  ON public.rider_vehicle_assignments (vehicle_id)
  WHERE ended_at IS NULL;

CREATE TABLE IF NOT EXISTS public.vehicle_maintenance_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  vehicle_id UUID NOT NULL REFERENCES public.vehicles (id) ON DELETE CASCADE,
  maintenance_type TEXT NOT NULL,
  description TEXT,
  vendor TEXT,
  cost_cents INT NOT NULL DEFAULT 0,
  currency TEXT NOT NULL DEFAULT 'LRD',
  odometer INT,
  performed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  next_service_date DATE,
  next_service_odometer INT,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  CREATE TYPE public.fleet_expense_category AS ENUM (
    'fuel', 'repairs', 'maintenance', 'parking', 'toll', 'insurance', 'registration', 'other'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS public.fleet_expenses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  vehicle_id UUID NOT NULL REFERENCES public.vehicles (id) ON DELETE CASCADE,
  rider_id UUID REFERENCES public.riders (id) ON DELETE SET NULL,
  amount_cents INT NOT NULL,
  currency TEXT NOT NULL DEFAULT 'LRD',
  category public.fleet_expense_category NOT NULL,
  expense_date DATE NOT NULL DEFAULT CURRENT_DATE,
  odometer INT,
  reference TEXT,
  notes TEXT,
  recorded_by UUID NOT NULL REFERENCES auth.users (id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.rider_expenses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  rider_id UUID NOT NULL REFERENCES public.riders (id) ON DELETE CASCADE,
  amount_cents INT NOT NULL,
  currency TEXT NOT NULL DEFAULT 'LRD',
  category TEXT NOT NULL,
  expense_date DATE NOT NULL DEFAULT CURRENT_DATE,
  notes TEXT,
  recorded_by UUID NOT NULL REFERENCES auth.users (id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Warehouses & inventory
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.warehouses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  branch_id UUID REFERENCES public.company_branches (id) ON DELETE SET NULL,
  name TEXT NOT NULL,
  code TEXT NOT NULL,
  address TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (company_id, code)
);

CREATE TABLE IF NOT EXISTS public.inventory_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  sku TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  barcode TEXT,
  unit TEXT NOT NULL DEFAULT 'ea',
  reorder_threshold INT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (company_id, sku)
);

CREATE TABLE IF NOT EXISTS public.inventory_stock (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  warehouse_id UUID NOT NULL REFERENCES public.warehouses (id) ON DELETE CASCADE,
  inventory_item_id UUID NOT NULL REFERENCES public.inventory_items (id) ON DELETE CASCADE,
  quantity_on_hand NUMERIC(14, 3) NOT NULL DEFAULT 0,
  quantity_reserved NUMERIC(14, 3) NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (warehouse_id, inventory_item_id)
);

DO $$ BEGIN
  CREATE TYPE public.inventory_movement_type AS ENUM (
    'receipt', 'adjustment', 'reservation', 'release', 'dispatch', 'return', 'transfer_in', 'transfer_out'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS public.inventory_movements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  warehouse_id UUID NOT NULL REFERENCES public.warehouses (id) ON DELETE CASCADE,
  inventory_item_id UUID NOT NULL REFERENCES public.inventory_items (id) ON DELETE CASCADE,
  quantity NUMERIC(14, 3) NOT NULL,
  movement_type public.inventory_movement_type NOT NULL,
  reference_type TEXT,
  reference_id UUID,
  notes TEXT,
  actor_user_id UUID REFERENCES auth.users (id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_inventory_movements_wh ON public.inventory_movements (warehouse_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- Delivery extensions (parcels + items + branch)
-- ---------------------------------------------------------------------------
ALTER TABLE public.deliveries
  ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES public.company_branches (id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS package_count INT NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS weight_kg NUMERIC(10, 3),
  ADD COLUMN IF NOT EXISTS dimensions_cm JSONB,
  ADD COLUMN IF NOT EXISTS is_fragile BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS package_category TEXT,
  ADD COLUMN IF NOT EXISTS handling_notes TEXT;

ALTER TABLE public.riders
  ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES public.company_branches (id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS public.delivery_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  delivery_id UUID NOT NULL REFERENCES public.deliveries (id) ON DELETE CASCADE,
  inventory_item_id UUID REFERENCES public.inventory_items (id) ON DELETE SET NULL,
  item_name TEXT NOT NULL,
  quantity NUMERIC(14, 3) NOT NULL DEFAULT 1,
  unit_value_cents INT NOT NULL DEFAULT 0,
  currency TEXT NOT NULL DEFAULT 'LRD',
  weight_kg NUMERIC(10, 3),
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  CREATE TYPE public.delivery_return_status AS ENUM (
    'return_requested', 'return_in_transit', 'returned', 'cancelled'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS public.delivery_returns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  delivery_id UUID NOT NULL REFERENCES public.deliveries (id) ON DELETE CASCADE,
  branch_id UUID REFERENCES public.company_branches (id) ON DELETE SET NULL,
  rider_id UUID REFERENCES public.riders (id) ON DELETE SET NULL,
  status public.delivery_return_status NOT NULL DEFAULT 'return_requested',
  reason TEXT NOT NULL,
  requested_by UUID REFERENCES auth.users (id) ON DELETE SET NULL,
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  in_transit_at TIMESTAMPTZ,
  returned_at TIMESTAMPTZ,
  returned_to_location TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (delivery_id)
);

DO $$ BEGIN
  CREATE TYPE public.cash_settlement_status AS ENUM (
    'open', 'submitted', 'verified', 'reconciled', 'disputed'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS public.cash_settlements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  branch_id UUID REFERENCES public.company_branches (id) ON DELETE SET NULL,
  rider_id UUID NOT NULL REFERENCES public.riders (id) ON DELETE CASCADE,
  status public.cash_settlement_status NOT NULL DEFAULT 'open',
  total_expected_cents INT NOT NULL DEFAULT 0,
  total_received_cents INT NOT NULL DEFAULT 0,
  currency TEXT NOT NULL DEFAULT 'LRD',
  submitted_at TIMESTAMPTZ,
  verified_at TIMESTAMPTZ,
  reconciled_at TIMESTAMPTZ,
  verified_by UUID REFERENCES auth.users (id) ON DELETE SET NULL,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.cash_settlement_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  settlement_id UUID NOT NULL REFERENCES public.cash_settlements (id) ON DELETE CASCADE,
  payment_id UUID NOT NULL REFERENCES public.payments (id) ON DELETE CASCADE,
  amount_cents INT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (payment_id)
);

CREATE TRIGGER company_branches_updated_at BEFORE UPDATE ON public.company_branches
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER vehicles_updated_at BEFORE UPDATE ON public.vehicles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER warehouses_updated_at BEFORE UPDATE ON public.warehouses
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER inventory_items_updated_at BEFORE UPDATE ON public.inventory_items
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER cash_settlements_updated_at BEFORE UPDATE ON public.cash_settlements
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER delivery_returns_updated_at BEFORE UPDATE ON public.delivery_returns
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Default branch per company (forward-safe backfill)
INSERT INTO public.company_branches (company_id, name, code, city, is_active)
SELECT c.id, c.name || ' Main', 'MAIN', 'Monrovia', true
FROM public.companies c
WHERE NOT EXISTS (
  SELECT 1 FROM public.company_branches b WHERE b.company_id = c.id
);

UPDATE public.companies c
SET default_branch_id = b.id
FROM public.company_branches b
WHERE b.company_id = c.id AND b.code = 'MAIN' AND c.default_branch_id IS NULL;

UPDATE public.deliveries d
SET branch_id = c.default_branch_id
FROM public.companies c
WHERE d.company_id = c.id AND d.branch_id IS NULL AND c.default_branch_id IS NOT NULL;
