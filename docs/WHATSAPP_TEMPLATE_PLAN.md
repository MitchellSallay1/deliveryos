# WhatsApp template submission plan

Proposed templates to submit through Gupshup/Meta for WhatsApp Business approval. **Not submitted automatically** — this is a plan for a human to review and submit. All are `UTILITY` category (transactional, triggered by the customer's/vendor's own action), not `MARKETING` — no promotional content, per WhatsApp policy and this project's own no-marketing-campaigns constraint.

Each row already exists in `whatsapp_template_registry` (migration `20260310000000_whatsapp_phase_a_foundation.sql`) with `status = 'draft'` and `gupshup_template_id = NULL`. After a template is approved in the Gupshup/Meta dashboard, update that row:

```sql
update platform_settings... -- N/A; use:
select admin_set... -- there is no admin RPC to edit this table in Phase A (read-only via admin_list_whatsapp_templates).
```

For Phase A, editing `gupshup_template_id`/`status` after approval is a direct table write via the Supabase SQL Editor (same operational pattern already used for `platform_settings` before its admin UI existed — see `docs/PRODUCTION_RUNBOOK.md`):

```sql
update whatsapp_template_registry
set gupshup_template_id = '<id from Gupshup>', status = 'approved'
where semantic_key = '<semantic_key>';
```

## Templates

### 1. `commerce_order_created_vendor`
- **Gupshup template name (suggested)**: `deliveryos_order_created_vendor`
- **Category**: Utility
- **Recipient**: Vendor (company phone)
- **Trigger**: Customer places a Commerce order (`submit_commerce_order`)
- **Body**: `New DeliveryOS order #{{1}} from {{2}}. Total LRD {{3}}. Open your vendor dashboard to accept.`
- **Parameters**: `{{1}}` order number, `{{2}}` customer name, `{{3}}` total (LRD)
- **CTA**: none in Phase A (a "View order" button linking to the vendor dashboard is a reasonable future addition once a stable deep-link exists)

### 2. `commerce_order_accepted_customer`
- **Gupshup template name**: `deliveryos_order_accepted_customer`
- **Category**: Utility
- **Recipient**: Customer
- **Trigger**: Vendor accepts the order (`vendor_accept_commerce_order`)
- **Body**: `Your DeliveryOS order #{{1}} has been accepted and is being prepared.`
- **Parameters**: `{{1}}` order number

### 3. `commerce_order_rejected_customer`
- **Gupshup template name**: `deliveryos_order_rejected_customer`
- **Category**: Utility
- **Recipient**: Customer
- **Trigger**: Vendor rejects the order (`vendor_reject_commerce_order`)
- **Body**: `Your DeliveryOS order #{{1}} could not be accepted. {{2}}`
- **Parameters**: `{{1}}` order number, `{{2}}` reason (short, customer-safe)
- **Note**: registered in the plan/registry for completeness; **not actively wired** to WhatsApp in Phase A (stays SMS-only) — see the phase report's "deliberately deferred" section.

### 4. `commerce_order_ready_customer`
- **Gupshup template name**: `deliveryos_order_ready_customer`
- **Category**: Utility
- **Recipient**: Customer
- **Trigger**: Vendor marks the order ready for pickup (`vendor_mark_order_ready`)
- **Body**: `Your DeliveryOS order #{{1}} is ready and waiting for a carrier.`
- **Parameters**: `{{1}}` order number

### 5. `carrier_selected`
- **Gupshup template name**: `deliveryos_carrier_selected`
- **Category**: Utility
- **Recipient**: Merchant/vendor (whoever requested the delivery)
- **Trigger**: A carrier is selected for a delivery request
- **Body**: `A carrier has been selected for order #{{1}}.`
- **Parameters**: `{{1}}` order/request number
- **Note**: registered for completeness; not wired to any call site in Phase A (no current single call site cleanly maps to "carrier selected" distinct from "carrier accepted" — see report).

### 6. `carrier_accepted_customer`
- **Gupshup template name**: `deliveryos_carrier_accepted_customer`
- **Category**: Utility
- **Recipient**: Customer
- **Trigger**: A marketplace carrier accepts the delivery offer (`accept_marketplace_offer`)
- **Body**: `A carrier has accepted your DeliveryOS order #{{1}}. You will be notified when it is picked up.`
- **Parameters**: `{{1}}` order number

### 7. `rider_assigned_customer`
- **Gupshup template name**: `deliveryos_rider_assigned_customer`
- **Category**: Utility
- **Recipient**: Customer
- **Trigger**: A rider is assigned to the delivery (`assign_delivery_rider`)
- **Body**: `A rider has been assigned to your delivery {{1}}.`
- **Parameters**: `{{1}}` tracking code
- **Note**: registered for completeness; not wired in Phase A (rider assignment today notifies the *rider*, not the customer — a customer-facing "rider assigned" message is a reasonable Phase B addition).

### 8. `delivery_picked_up_customer`
- **Gupshup template name**: `deliveryos_delivery_picked_up`
- **Category**: Utility
- **Recipient**: Customer
- **Trigger**: Delivery transitions to `picked_up`
- **Body**: `Your package for {{1}} has been picked up and is on the way.`
- **Parameters**: `{{1}}` tracking code
- **Note**: registered; **not actively wired** in Phase A (stays SMS-only — conservative "first 5 events" scope, see report).

### 9. `delivery_in_transit_customer`
- **Gupshup template name**: `deliveryos_delivery_in_transit`
- **Category**: Utility
- **Recipient**: Customer
- **Trigger**: Delivery transitions to `in_transit`
- **Body**: `Your package for {{1}} is in transit. Track: {{2}}`
- **Parameters**: `{{1}}` tracking code, `{{2}}` tracking URL
- **CTA button**: "Track order" linking to `{{2}}` — WhatsApp supports a URL button on utility templates; recommended once volume justifies the extra approval complexity
- **Note**: registered; not actively wired in Phase A.

### 10. `delivery_delivered_customer`
- **Gupshup template name**: `deliveryos_delivery_delivered`
- **Category**: Utility
- **Recipient**: Customer
- **Trigger**: Delivery transitions to `delivered` (`notify_customer_tracking`)
- **Body**: `Your package for {{1}} was delivered. Thank you for using DeliveryOS!`
- **Parameters**: `{{1}}` tracking code

### 11. `delivery_failed_customer`
- **Gupshup template name**: `deliveryos_delivery_failed`
- **Category**: Utility
- **Recipient**: Customer
- **Trigger**: Delivery transitions to `failed`
- **Body**: `We were unable to deliver your package for {{1}}. {{2}}`
- **Parameters**: `{{1}}` tracking code, `{{2}}` failure reason (customer-safe wording)
- **Note**: registered; not wired in Phase A (no failed-delivery customer notification exists on SMS today either — this would be a new notification, not a channel addition to an existing one, so it's out of Phase A's "extend existing notifications" scope).

## What's actively wired to WhatsApp in Phase A

Only **5 events** actually call `dispatch_channel_notification` (and therefore can ever choose WhatsApp, once its template is approved and a company opts in): #1, #2, #4, #6, #10 above. The rest are registered (so the registry/template-plan is complete and won't need a schema change later) but their call sites still queue SMS directly — see the phase report for the exact reasoning per event.
