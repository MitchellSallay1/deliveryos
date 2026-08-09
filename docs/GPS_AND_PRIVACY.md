# GPS & privacy

## Data model

- **`rider_locations`**: one current row per rider (upsert). Used for dispatcher live map and Realtime.
- **`rider_location_samples`**: optional short trail during active delivery only; purge with `purge_old_rider_location_samples()` (default 48h).

## Who can access what

| Actor | Access |
|--------|--------|
| Rider | Write own location via `record_rider_location` when linked `riders.user_id = auth.uid()` |
| Owner / dispatcher | Read company riders via RLS + `list_company_rider_locations` (requires `gps_tracking` feature) |
| Customer | Approximate blurred position via `get_public_delivery_tracking` only while in transit/picked up, last 30 minutes |
| Super admin | No routine GPS UI |

Coordinates are blurred for customers (~1.1 km grid using 2 decimal places).

## Tracking states

- `off` — no row stored (delete on off)
- `available` — rider online without active leg
- `active_delivery` — active job; samples may be recorded
- `paused` — temporary hold

## Retention

Do not store unlimited history. Run periodic purge (cron):

```sql
SELECT public.purge_old_rider_location_samples(INTERVAL '48 hours');
```

## PWA / background limitations

Mobile browsers may suspend `watchPosition` when the screen locks or the PWA is backgrounded. Riders should keep the app foreground during active deliveries. iOS Safari PWA has stricter limits than Android Chrome installed PWA.

Document for riders: enable location permission when prompted; tracking stops when no active delivery.

## Realtime

`rider_locations` is in the `supabase_realtime` publication. Dispatchers subscribe per `company_id` filter — avoid polling full fleet lists.
