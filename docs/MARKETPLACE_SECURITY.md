# Marketplace security

## Tenant boundaries

- Merchants: RLS + RPC checks on `merchant_company_id`
- Providers: offers/jobs scoped to `provider_company_id`
- Merchants must not see other merchants' requests or provider internal ops
- Providers must not see competing providers' offers or pricing

## RPC-first mutations

Writes go through SECURITY DEFINER RPCs with `has_company_role` / `assert_*_marketplace` / feature flags — not direct table INSERT from clients.

## Pre-acceptance data minimization

Providers receive pickup/destination **area summaries**, package hints, and fee opportunity until offer is **accepted**; then fulfillment fields are exposed via `list_marketplace_jobs_page` CASE expressions.

## Reviews

`create_provider_review` requires delivered marketplace delivery (`merchant_company_id` match, `delivery_request_id` present). Unique per `delivery_id`.

## Suspension

`companies.marketplace_suspended` and `provider_marketplace_profiles.admin_marketplace_disabled` enforced in assert helpers.

## API keys

Marketplace scopes (Edge `api-v1`):

- `marketplace:request:create`, `marketplace:request:read`
- `marketplace:job:read`, `marketplace:job:accept`

Provider job accept verifies offer belongs to key's company before RPC.
