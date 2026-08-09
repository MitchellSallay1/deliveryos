# Rider SMS

## Outbound (job assignment)

When a delivery is assigned to a rider with `access_mode` `button_phone` or `both`, `notify_rider_new_job()` queues a concise SMS:

```
DeliveryOS
New job: DLV-…
Pickup: …
Drop: …

Reply:
A = Accept
P = Picked Up
T = In Transit
D = Delivered
F = Failed
```

Assignment remains valid if SMS fails; `deliveries.rider_job_sms_status` is `sent`, `failed`, or `skipped`. Dispatchers can call `resend_rider_job_sms(delivery_id)`.

## Inbound commands

Edge Function: `supabase/functions/sms-inbound`

Webhook secret header: `x-sms-secret` (env `SMS_WEBHOOK_SECRET`)

JSON body: `{ "from": "+231…", "text": "A 69B9" }`

RPC: `process_inbound_sms` → `apply_rider_channel_command(..., 'sms')`

| Command | Status |
|---------|--------|
| A | accepted |
| P | picked_up |
| T | in_transit |
| D | delivered |
| F | failed |

### Multiple active jobs

- One active job: `A` alone is enough.
- Several jobs: reply must include tracking suffix, e.g. `A 69B9` (last 4 chars of tracking code).

### Failed delivery

- `F 69B9` or `F 69B9 1` where `1–4` map to failure reasons (customer unavailable, wrong address, refused, other).

### Customer OTP (optional)

When company setting `require_otp_button_phone_delivery` is on and delivery `proof_method` is `customer_otp`:

- Customer receives SMS when delivery moves to **in transit**.
- Rider completes with `D 69B9 4821`.

## Replies

Successful commands auto-reply via `queue_outbound_sms` from the Edge Function. Errors return helpful text, not raw database errors.

## Provider setup (later)

Configure your aggregator to POST inbound MO messages to the deployed `sms-inbound` URL with the shared secret. Map `from` to the network MSISDN.
