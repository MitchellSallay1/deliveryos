# Disaster recovery

## Objectives (initial launch)

| Metric | Target |
|--------|--------|
| **RPO** (max data loss) | 24 hours on Starter; **≤ 1 hour** with Supabase Pro PITR enabled |
| **RTO** (time to restore service) | 4 hours for database restore; 1 hour for frontend redeploy |

## Supabase

- Enable **daily backups** (Pro plan recommended for production).
- Enable **Point-in-Time Recovery** when available on production project.
- Store connection strings and project refs in a secure password manager (not git).

## Database export (manual)

```bash
pg_dump "$DATABASE_URL" -Fc -f deliveryos-backup.dump
```

Store encrypted off-site. Test restore on a **non-production** project quarterly.

## Storage

- Bucket `delivery-photos`: include in DR planning; replicate policy JSON and lifecycle rules.
- POD photos are operational, not financial — RPO may be looser than Postgres.

## Restore procedure (high level)

1. Create new Supabase project or use PITR restore point.
2. Apply migrations if starting fresh: `supabase db push`.
3. Restore dump if full restore: `pg_restore --clean --no-owner -d postgres deliveryos-backup.dump`.
4. Redeploy Edge Functions and Vite frontend with production env vars.
5. Rotate API keys and webhook secrets if breach suspected.
6. Run `npm run test:db` and smoke tests before traffic cutover.

## Validation status

| Step | Status |
|------|--------|
| Documented backup | Done |
| Non-production restore test | **UNVERIFIED** (requires Supabase project) |
| PITR enabled on production | **BLOCKED** (operator action) |
