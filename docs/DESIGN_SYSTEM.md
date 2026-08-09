# DeliveryOS design system (UI phase)

Presentation-only layer. Business logic, RPCs, and auth are unchanged.

## Branding

- `BrandingProvider` (`src/branding/BrandingProvider.tsx`) applies CSS variables at runtime.
- Default deployment theme: **MTN** (`src/branding/themes/mtn.ts`) — product name stays **DeliveryOS**, partner line **Powered by MTN**.
- Set `VITE_BRAND_THEME=default` for swappable neutral branding.

Components: `BrandLogo`, `PoweredByPartner`, `MtnMark` in `src/components/brand/`.

## Tokens

Global tokens in `src/index.css` (`@theme`): primary, accent (MTN yellow), sidebar, status colors, radii, shadows.

Delivery status visuals: `src/design-system/delivery-status.ts`.

## UI primitives

| Component | Path |
|-----------|------|
| Button (default, accent, outline, ghost, destructive) | `components/ui/Button.tsx` |
| Card | `components/ui/Card.tsx` |
| Badge | `components/ui/Badge.tsx` |
| StatusBadge | `components/ui/StatusBadge.tsx` |
| KpiCard / Skeleton | `components/ui/KpiCard.tsx`, `Skeleton.tsx` |
| PageHeader | `components/ui/PageHeader.tsx` |
| Tabs | `components/ui/Tabs.tsx` |
| Sheet (drawer) | `components/ui/Sheet.tsx` |
| EmptyState | `components/EmptyState.tsx` |

## Feature layouts

- **Operations center**: `components/dashboard/OperationsDashboard.tsx`
- **Live Kanban**: `components/deliveries/DeliveryKanbanBoard.tsx`
- **Delivery drawer**: `components/deliveries/DeliveryDetailDrawer.tsx`

Icons: `lucide-react` only (no emoji).

## Marketing site

- **Layout:** `layouts/MarketingLayout.tsx` + `components/marketing/*`
- Reuses branding tokens and UI primitives (KpiCard, StatusBadge, Button accent)
- See [PUBLIC_WEBSITE.md](./PUBLIC_WEBSITE.md)

## MTN placeholders

“Coming soon” cards for MTN SMS, MoMo, USSD, Enterprise — no API wiring in this phase.
