# Super Admin control tower

Platform operators (`profiles.is_super_admin`) use `/admin` — separate from tenant workspaces.

## Authorization

- UI: `SuperAdminRoute` requires `context.activeRole === 'super_admin'`.
- Database: `public.is_super_admin()` on all platform RPCs and RLS bypass where explicitly granted.
- Never trust frontend role labels alone; mutations go through SECURITY DEFINER RPCs where possible.

## Navigation

Grouped sidebar: `src/lib/admin-nav.ts` + `AdminLayout` + `AdminSidebar`.

## Data layer

Migration `20260308180000_super_admin_control_tower.sql`:

| RPC | Purpose |
|-----|---------|
| `get_platform_command_center` | Command center KPIs + day-over-day |
| `get_platform_live_snapshot` | Live tower counts |
| `get_platform_network_metrics` | Network performance |
| `get_platform_trial_funnel` | Schema-derived trial funnel |
| `list_admin_companies_page` | Paginated company directory |
| `get_company_admin_360` | Company 360 summary |
| `get_company_health_score` | Transparent health rules |
| `list_admin_deliveries_page` | Global delivery explorer |
| `get_admin_delivery_detail` | Inspection drawer payload |
| `list_admin_map_points` | Map riders (no customer addresses) |
| `get_admin_communications_summary` | SMS/email aggregates |
| `list_admin_api_keys_page` | API key metadata (no secrets) |
| `admin_global_search` | Platform search |
| `admin_support_lookup` | Support diagnostics |
| `get_platform_alerts` | Conservative alerts |
| `admin_set_company_status` | Audited activate/suspend |
| `list_audit_logs_admin` | Audit filters |
| `get_platform_health_snapshot` | Extended health (MTN not configured) |

## Key routes

See sidebar groups in `admin-nav.ts`. Company detail: `/admin/companies/:id`.

## Performance

Server-side pagination on companies, deliveries, API keys, audit. Maps and charts lazy-loaded.

See also [PLATFORM_OPERATIONS.md](./PLATFORM_OPERATIONS.md), [ADMIN_SECURITY.md](./ADMIN_SECURITY.md).
