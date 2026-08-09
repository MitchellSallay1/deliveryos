# Rider USSD

## Architecture

Business logic is provider-neutral:

- SQL: `handle_ussd_request(phone, session_id, text, network)`
- Edge Function: `supabase/functions/ussd-rider`
- Sessions: `ussd_sessions` (short TTL, JSON context for job lists)

## Normalized API

**Request** (POST JSON or form):

```json
{
  "phone": "+231770000000",
  "session_id": "abc-123",
  "network": "mtn",
  "input": "1*2",
  "service_code": "*123#"
}
```

Field aliases accepted: `msisdn`, `sessionId`, `text`, `subscriberInput`.

**Response:**

```json
{
  "continue_session": true,
  "message": "DeliveryOS Rider\n1. My jobs\n…"
}
```

Secret header: `x-ussd-secret` (`USSD_WEBHOOK_SECRET`).

## Menus

Main menu:

1. My jobs (list → pick job → action submenu)
2. Accept
3. Picked up
4. In transit
5. Delivered
6. Failed
7. Jobs today (ends session)

Actions reuse `apply_rider_channel_command(..., 'ussd')` — same rules as SMS.

## Provider adapters (stubs)

Implement mapping at your reverse proxy or extend `ussd-rider/index.ts`:

| Provider | Notes |
|----------|--------|
| **MTN Liberia** | Map aggregator fields to normalized `phone`, `session_id`, `input` |
| **Orange Liberia** | Same; do not embed provider XML/JSON in SQL |

Core rider logic must stay in Postgres RPCs.

## Deploy

```bash
npx supabase functions deploy ussd-rider
```

Set `USSD_WEBHOOK_SECRET` in function secrets.
