# Fleet management

## Scope

Phase 6 fleet covers **vehicles**, **rider↔vehicle assignments**, **maintenance**, and **operating expenses**. Requires plan feature `fleet_management`.

## Data model

- `vehicles` — company fleet registry (optional `branch_id`)
- `rider_vehicle_assignments` — history; one active assignment per vehicle (partial unique index)
- `vehicle_maintenance_records` — service history and next due dates
- `fleet_expenses` — fuel, repairs, insurance, etc.

## Mutations

All writes go through SECURITY DEFINER RPCs (`upsert_vehicle`, `assign_rider_vehicle`, `record_vehicle_maintenance`). Clients have SELECT-only RLS on fleet tables.

## Webhooks

`vehicle.maintenance_due` fires when a recorded next service date is within 7 days.

## UI

`/operations/fleet` and `/operations/fleet/:id`
