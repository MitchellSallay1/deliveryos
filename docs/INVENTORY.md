# Inventory

## Optional module

Inventory is **optional** per company. Enable with plan feature `inventory` and hubs with `warehouse_management`.

## Tables

- `inventory_items` — SKU catalog (`reorder_threshold` for low stock)
- `warehouses` — physical locations
- `inventory_stock` — on-hand and reserved quantities per warehouse/item
- `inventory_movements` — immutable ledger

## Movement rules

| Type | Effect |
|------|--------|
| receipt | +on_hand |
| adjustment | signed delta on on_hand |
| reservation | +reserved (validates available) |
| release | −reserved |
| dispatch / transfer_out | −on_hand |
| transfer_in / return | +on_hand |

Clients **cannot** INSERT/UPDATE `inventory_stock` or `inventory_movements` directly.

## RPCs

- `inventory_receive_stock`
- `inventory_adjust_stock`
- Internal: `_inventory_apply_movement`

## Alerts

When `quantity_on_hand - quantity_reserved <= reorder_threshold`, webhook `inventory.low_stock` is enqueued.

Receipts emit `inventory.received`.

## UI

`/operations/inventory`, `/operations/inventory/movements`
