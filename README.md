# DeliveryOS

Multi-tenant delivery SaaS for Liberia — **Supabase-first** (Postgres, Auth, RLS, Realtime, Storage, Edge Functions).

> **Start here:** [ARCHITECTURE.md](./ARCHITECTURE.md) for setup, security model, and roadmap.  
> Phase 3 hardening: [PHASE3_AUDIT.md](./PHASE3_AUDIT.md).  
> The app runs from the **repo root** (`npm run dev`).

## Quick start

```bash
cp .env.example .env.local   # add Supabase URL + anon key
npm install
npx supabase db push         # after linking your project
npm run dev
npm test                     # unit tests (RBAC, schemas, errors)
npm run gen:types            # optional: refresh types from linked Supabase project
```

Deploy the `dist/` output to **Vercel**; keep database and auth on **Supabase Cloud**.

### SMS

- Apply migration `20260307160000_notifications_sms.sql`
- Set DB setting (optional): `ALTER DATABASE postgres SET app.public_url = 'https://your-app.vercel.app';`
- Deploy function: `npx supabase functions deploy sms-inbound --no-verify-jwt`
- Secrets: `SMS_WEBHOOK_SECRET`, `SUPABASE_SERVICE_ROLE_KEY` (auto in Edge)

Top up credits (SQL): `UPDATE companies SET sms_credits = 50 WHERE id = '...';`
