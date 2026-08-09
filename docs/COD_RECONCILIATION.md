# COD reconciliation

## Feature

Requires plan flag `cod_reconciliation`.

## Workflow

1. Rider collects COD → `payments.status = collected` (existing flow).
2. Dispatcher creates **`cash_settlements`** via `create_cash_settlement(rider_id)` — attaches all collected payments not yet in a settlement (`cash_settlement_items.payment_id` is **UNIQUE**).
3. Rider or dispatcher **`submit_cash_settlement`** with amount received.
4. Dispatcher **`reconcile_cash_settlement`** → calls `mark_payment_deposited` for each item → settlement `reconciled`.

## Double-settlement prevention

- `cash_settlement_items.payment_id` unique constraint
- Creation RPC skips payments already linked

## Statuses

`open` → `submitted` → `verified` (optional future) → `reconciled` / `disputed`

## Webhooks

- `cash_settlement.submitted`
- `cash_settlement.reconciled`

## UI

`/operations/cash-settlements`
