# Marketplace finance

## Price components

For each accepted marketplace job:

| Component | Description |
|-----------|-------------|
| Gross | Merchant quoted delivery fee (`quoted_amount_lrd_cents`) |
| Platform fee | From `marketplace_fee_rules` (fixed, percentage, subscription-only, zero) |
| Provider amount | Gross − platform fee |

Fees are **not hard-coded**. Default platform rule: 10% (`percentage_bps = 1000`).

## Ledger

`marketplace_transactions` is the canonical financial record (one row per request).

`marketplace_ledger_entries` append-only lines:

- `merchant_payable` — merchant owes platform/gross
- `provider_receivable` — provider earnings
- `platform_revenue` — platform fee (`company_id` NULL)

Balances are derived from ledger sums; mutable balance columns are avoided.

## Settlement (manual)

Super Admin uses `record_marketplace_settlement`:

- Merchant paid DeliveryOS
- DeliveryOS paid provider
- Provider collected COD
- Notes for net settlement

Unique index on `marketplace_settlements(marketplace_transaction_id)` prevents double settlement (`already_settled`).

## Status lifecycle

`pending` → `earned` (future automation) → `settled` | `refunded` | `cancelled` | `disputed`

No payment gateway integration in Phase 7.
