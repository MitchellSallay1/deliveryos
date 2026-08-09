# Marketplace

DeliveryOS connects **merchants** to **logistics providers** without becoming the courier. Merchants create **delivery requests**; opted-in providers receive **offers**; acceptance converts the request into a normal provider-scoped **delivery** (riders, GPS, SMS, COD, webhooks unchanged).

## Business types

| Type | Behavior |
|------|----------|
| `logistics_provider` | Default for existing companies. Full ops portal; optional marketplace provider profile. |
| `merchant` | Merchant portal; external delivery requests by default. No fleet/riders nav. |
| `hybrid` | Own riders plus marketplace requests. |

Set at registration via `create_company_with_owner(p_business_type)`.

## Core tables

- `delivery_requests` — merchant intent (separate from execution)
- `delivery_offers` — per-provider opportunities (no cross-provider pricing leakage in UI/RPC)
- `merchant_provider_relationships` — preferred / blocked / contracted / marketplace
- `provider_marketplace_profiles` — opt-in directory settings
- `provider_marketplace_zones` — reuse `delivery_zones` for coverage
- `marketplace_transactions` + `marketplace_ledger_entries` — immutable-style ledger
- `marketplace_settlements` — manual settlement records (Liberia ops reality)
- `provider_reviews`, `marketplace_disputes`

## Flow (MVP)

1. Merchant creates request → `create_delivery_request`
2. Merchant publishes → `publish_delivery_request` (matching + offers)
3. Provider accepts offer → `accept_marketplace_offer` → `deliveries` row on **provider** `company_id`, `merchant_company_id` + `delivery_request_id` set
4. Fulfillment uses existing DeliveryOS delivery pipeline

## Matching

Deterministic filters: marketplace enabled, active company/subscription, accepting jobs, zone/coverage, not blocked. No AI matching in Phase 7.

## Privacy

`list_marketplace_jobs_page` returns area summaries pre-acceptance; full addresses/customer contact only after offer acceptance.

## Feature flags (`can_use_feature`)

- `marketplace_access`, `merchant_portal`, `provider_network`, `marketplace_api`

## UI routes

- Merchant: `/merchant/requests`, `/marketplace/providers`, `/billing`
- Provider: `/marketplace/jobs`, Settings → marketplace profile
- Admin: `/admin/marketplace`

See [MARKETPLACE_FINANCE.md](./MARKETPLACE_FINANCE.md) and [MARKETPLACE_SECURITY.md](./MARKETPLACE_SECURITY.md).
