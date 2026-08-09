# DeliveryOS HTTP API (v1)

Base URL (Supabase Edge Function):

```text
https://<project-ref>.supabase.co/functions/v1/api-v1
```

## Authentication

Send the company API key on every request:

```http
X-API-Key: dos_<secret>
```

Keys are created in **Settings → Integrations** (company owner, `api_access` plan feature). Plaintext keys are shown once; only a SHA-256 hash is stored.

Permissions are JSON arrays on the key, for example:

- `delivery:create`
- `delivery:read`
- `tracking:read`

## Rate limiting

The Edge Function applies a simple in-memory limit (**120 requests / minute / key**). For production, add Redis or Supabase-backed counters.

## Endpoints

### `POST /v1/deliveries`

Requires `delivery:create`.

Body (JSON):

```json
{
  "pickup_business_name": "Shop",
  "pickup_address": "Broad St, Monrovia",
  "customer_name": "Jane Doe",
  "customer_phone": "+231770000000",
  "destination_address": "Sinkor, Monrovia",
  "delivery_zone_id": "optional-uuid",
  "delivery_fee_lrd_cents": 500,
  "fee_manual_override": false
}
```

### `GET /v1/deliveries/:id`

Requires `delivery:read`. Scoped to the key's company.

### `GET /v1/tracking/:code`

Requires `tracking:read`. Returns the same privacy-safe payload as `get_public_delivery_tracking`.

## Marketplace (Phase 7)

Requires `marketplace_api` plan feature for production keys.

Permissions:

- `marketplace:request:create`, `marketplace:request:read`
- `marketplace:job:read`, `marketplace:job:accept`

### `POST /v1/delivery-requests`

Create draft request for merchant company (key tenant). Optional body field `"publish": true` to publish immediately.

### `GET /v1/delivery-requests`

Paginated list (`limit`, `offset`, optional `status`).

### `GET /v1/delivery-requests/:id`

Merchant-scoped read.

### `POST /v1/delivery-requests/:id/cancel`

Body optional `{ "reason": "..." }`.

### `GET /v1/marketplace/jobs`

Provider-scoped pending/accepted offers (redacted pre-acceptance fields).

### `POST /v1/marketplace/jobs/:offer_id/accept`

Accepts job offer belonging to provider company.

## Errors

Structured JSON:

```json
{ "error": { "code": "forbidden", "message": "Missing delivery:read permission" } }
```

## Audit

Successful mutating operations should be traced via application logs and PostgreSQL audit events where RPCs call `log_audit_event`.

Deploy:

```bash
npx supabase functions deploy api-v1
```
