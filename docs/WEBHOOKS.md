# Webhooks

## Configuration

Company owners add endpoints in **Settings → Integrations**. Each endpoint has:

- HTTPS URL
- Secret (used for HMAC)
- Subscribed events (empty = all supported events)

## Events

- `delivery.created`
- `delivery.assigned`
- `delivery.picked_up`
- `delivery.in_transit`
- `delivery.delivered`
- `delivery.failed`
- `payment.collected`

## Marketplace (Phase 7)

Merchant:

- `delivery_request.created`
- `delivery_request.accepted`
- `delivery_request.cancelled`
- `delivery_request.completed` (via delivery lifecycle hooks where applicable)

Provider:

- `marketplace_job.available`
- `marketplace_job.accepted`

Internal notification event names (SMS/email pipeline):

- `marketplace.request.created`
- `marketplace.offer.created` / `accepted` / `rejected`
- `marketplace.delivery.started` / `completed`
- `marketplace.payment.recorded`

Payload shape:

```json
{
  "event": "delivery.delivered",
  "company_id": "uuid",
  "entity_id": "uuid",
  "data": { },
  "occurred_at": "2026-08-07T19:00:00Z"
}
```

## Security

Outbound requests include:

```http
X-DeliveryOS-Signature: sha256=<hex-hmac-sha256-of-raw-body>
X-DeliveryOS-Event: delivery.delivered
```

Verify HMAC with your endpoint secret. Reject requests with mismatched signatures.

## Delivery & retries

Rows in `webhook_deliveries` track attempts. The `webhooks-dispatch` Edge Function POSTs pending rows with exponential backoff (up to 5 attempts, then `dead`).

Schedule dispatch via Supabase cron or external scheduler:

```bash
npx supabase functions deploy webhooks-dispatch
```

## Tenant isolation

Webhooks are enqueued only for the company that owns the delivery/payment. Endpoint secrets are never returned after creation (store on your side when rotating).
