# Rider channels overview

DeliveryOS supports two first-class rider operational channels:

| Mode | Identity | Client | Proof / location |
|------|----------|--------|------------------|
| **Smartphone** | Supabase Auth user linked to `riders.user_id` | Rider PWA (My Jobs) | GPS, photo proof |
| **Button phone** | Company + normalized MSISDN + rider row | SMS keywords, USSD menus | Optional customer OTP |
| **Both** | Same rider record | PWA and/or SMS/USSD | Channel-appropriate proof |

## Data model

- `riders.access_mode`: `smartphone` (default), `button_phone`, `both`
- `riders.phone` / `phone_normalized`: Liberia MSISDN via `normalize_phone_lr()`
- Company toggles on `companies`: allow modes, enable SMS/USSD, require OTP for button-phone delivery
- Plan features: `rider_sms`, `rider_ussd`, `customer_otp` via `can_use_feature()` (plan JSON or SMS allowance)

## Security

- Inbound SMS/USSD Edge Functions use **service role** only; riders are resolved by telecom MSISDN, not rider codes in message body.
- Status changes go through `delivery_transition_core()` with `transition_source` (`pwa`, `sms`, `ussd`, `dispatcher`).
- Rate limiting and `rider_channel_events` audit log for commands.

## Related docs

- [RIDER_SMS.md](./RIDER_SMS.md)
- [RIDER_USSD.md](./RIDER_USSD.md)
