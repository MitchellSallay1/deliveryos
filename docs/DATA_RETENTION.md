# Data retention

| Data class | Default retention | Notes |
|------------|-------------------|-------|
| GPS samples (`rider_location_samples`) | 48 hours | Purged by `run_scheduled_maintenance_jobs` |
| Rider current location | Until rider inactive | One row per rider |
| Delivery history | Indefinite | Business record |
| Marketplace requests/transactions | Indefinite | Financial/audit |
| Audit logs | Indefinite | Append-only |
| SMS outbox | 90 days recommended | Archive/deletion policy TBD |
| Email outbox | 90 days recommended | Archive/deletion policy TBD |
| Webhook delivery logs | 90 days recommended | Keep dead-letter longer for support |
| API auth events | 30 days recommended | Security monitoring |
| Notification logs | 1 year recommended | |
| Invoices / payments | Indefinite | Do not delete without legal review |

Automated deletion jobs beyond GPS purge are **not** implemented in Phase 8 — configure via future cron or warehouse export.
