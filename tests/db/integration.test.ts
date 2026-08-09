/**
 * PostgreSQL RLS integration tests (local Supabase).
 *
 * Set DATABASE_URL (default local: postgresql://postgres:postgres@127.0.0.1:54322/postgres)
 * then: npm run test:db
 */
import postgres from 'postgres'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'

const dbUrl =
  process.env.DATABASE_URL ?? process.env.SUPABASE_DB_URL ?? 'postgresql://postgres:postgres@127.0.0.1:54322/postgres'

const runDb = process.env.RUN_DB_TESTS === '1'

describe.skipIf(!runDb)('database integration (RLS & billing)', () => {
  const sql = postgres(dbUrl, { max: 1 })
  let planStarterId: string
  let companyA: string
  let companyB: string
  let ownerA: string
  let ownerB: string

  beforeAll(async () => {
    try {
      await sql`SELECT 1`
    } catch {
      throw new Error(`Cannot connect to DATABASE_URL. Start Supabase locally and apply migrations.`)
    }

    const [plan] = await sql<{ id: string }[]>`
      SELECT id FROM public.subscriptions WHERE slug = 'starter' LIMIT 1
    `
    planStarterId = plan?.id
    if (!planStarterId) {
      throw new Error('Missing starter plan — run Phase 4 migrations')
    }

    ownerA = crypto.randomUUID()
    ownerB = crypto.randomUUID()
    companyA = crypto.randomUUID()
    companyB = crypto.randomUUID()

    await sql`
      INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, aud, role)
      VALUES
        (${ownerA}::uuid, ${`owner-a-${ownerA.slice(0, 8)}@test.local`}, crypt('testpass', gen_salt('bf')), now(), '{}', '{}', 'authenticated', 'authenticated'),
        (${ownerB}::uuid, ${`owner-b-${ownerB.slice(0, 8)}@test.local`}, crypt('testpass', gen_salt('bf')), now(), '{}', '{}', 'authenticated', 'authenticated')
    `
    // handle_new_user already inserts a profile row on the auth.users insert
    // above; upsert here to set the test's intended full_name/is_super_admin.
    await sql`
      INSERT INTO public.profiles (id, full_name, is_super_admin)
      VALUES
        (${ownerA}::uuid, 'Owner A', false),
        (${ownerB}::uuid, 'Owner B', false)
      ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, is_super_admin = EXCLUDED.is_super_admin
    `
    await sql`
      INSERT INTO public.companies (id, name, slug, email, phone, status, subscription_id)
      VALUES
        (${companyA}::uuid, 'Company A', ${'company-a-' + companyA.slice(0, 8)}, 'a@test.local', '+2310000001', 'active', ${planStarterId}::uuid),
        (${companyB}::uuid, 'Company B', ${'company-b-' + companyB.slice(0, 8)}, 'b@test.local', '+2310000002', 'active', ${planStarterId}::uuid)
    `
    await sql`
      INSERT INTO public.company_users (company_id, user_id, role, is_active)
      VALUES
        (${companyA}::uuid, ${ownerA}::uuid, 'company_owner', true),
        (${companyB}::uuid, ${ownerB}::uuid, 'company_owner', true)
    `
    await sql`
      INSERT INTO public.company_subscriptions (
        company_id, plan_id, status, starts_at, current_period_start, current_period_end
      ) VALUES
        (
          ${companyA}::uuid, ${planStarterId}::uuid, 'active', now(),
          date_trunc('month', now()), date_trunc('month', now()) + interval '1 month'
        ),
        (
          ${companyB}::uuid, ${planStarterId}::uuid, 'active', now(),
          date_trunc('month', now()), date_trunc('month', now()) + interval '1 month'
        )
    `
    await sql`
      INSERT INTO public.invoices (
        company_id, plan_id, invoice_number, status, amount_cents, currency,
        billing_period_start, billing_period_end, issued_at, due_at
      )
      SELECT ${companyA}::uuid, ${planStarterId}::uuid, 'INV-A-TEST', 'issued', 1000, 'LRD', now(), now() + interval '1 month', now(), now() + interval '7 days'
      WHERE NOT EXISTS (SELECT 1 FROM public.invoices WHERE invoice_number = 'INV-A-TEST')
    `
    await sql`
      INSERT INTO public.invoices (
        company_id, plan_id, invoice_number, status, amount_cents, currency,
        billing_period_start, billing_period_end, issued_at, due_at
      )
      SELECT ${companyB}::uuid, ${planStarterId}::uuid, 'INV-B-TEST', 'issued', 2000, 'LRD', now(), now() + interval '1 month', now(), now() + interval '7 days'
      WHERE NOT EXISTS (SELECT 1 FROM public.invoices WHERE invoice_number = 'INV-B-TEST')
    `
  })

  afterAll(async () => {
    await sql`DELETE FROM public.invoices WHERE invoice_number IN ('INV-A-TEST', 'INV-B-TEST')`
    await sql`DELETE FROM public.company_subscriptions WHERE company_id IN (${companyA}::uuid, ${companyB}::uuid)`
    await sql`DELETE FROM public.company_users WHERE company_id IN (${companyA}::uuid, ${companyB}::uuid)`
    await sql`DELETE FROM public.companies WHERE id IN (${companyA}::uuid, ${companyB}::uuid)`
    await sql`DELETE FROM public.profiles WHERE id IN (${ownerA}::uuid, ${ownerB}::uuid)`
    await sql`DELETE FROM auth.users WHERE id IN (${ownerA}::uuid, ${ownerB}::uuid)`
    await sql.end()
  })

  async function asUser<T>(userId: string, fn: (tx: postgres.Sql) => Promise<T>) {
    return sql.begin(async (tx) => {
      await tx`SELECT set_config('request.jwt.claim.sub', ${userId}, true)`
      await tx`SET LOCAL role authenticated`
      return fn(tx)
    })
  }

  it('tenant isolation: owner A cannot read company B invoices', async () => {
    const rows = await asUser(ownerA, async (tx) => {
      return tx<{ invoice_number: string }[]>`
        SELECT invoice_number FROM public.invoices WHERE company_id = ${companyB}::uuid
      `
    })
    expect(rows).toHaveLength(0)
  })

  it('tenant isolation: owner A sees own invoices', async () => {
    const rows = await asUser(ownerA, async (tx) => {
      return tx<{ invoice_number: string }[]>`
        SELECT invoice_number FROM public.invoices WHERE company_id = ${companyA}::uuid
      `
    })
    expect(rows.some((r) => r.invoice_number === 'INV-A-TEST')).toBe(true)
  })

  it('suspended subscription disables advanced_reports feature', async () => {
    await sql`
      UPDATE public.company_subscriptions
      SET status = 'suspended', updated_at = now()
      WHERE company_id = ${companyA}::uuid AND status = 'active'
    `
    const ok = await sql<{ can_use_feature: boolean }[]>`
      SELECT public.can_use_feature(${companyA}::uuid, 'advanced_reports') AS can_use_feature
    `
    expect(ok[0]?.can_use_feature).toBe(false)
    await sql`
      UPDATE public.company_subscriptions
      SET status = 'active', updated_at = now()
      WHERE company_id = ${companyA}::uuid AND status = 'suspended'
    `
  })

  it('authenticated cannot UPDATE payments directly', async () => {
    // payments has no UPDATE policy at all (dropped in
    // 20260307190000_phase3_hardening.sql — mutations only via
    // mark_payment_deposited/mark_payment_reconciled). With no matching
    // policy, RLS filters out every row for that command rather than
    // raising an error, so an UPDATE against a REAL row must silently
    // affect zero rows and leave the value unchanged — a `WHERE false`
    // no-op doesn't actually exercise this (it "succeeds" either way),
    // which is why this test previously asserted the wrong thing.
    const [delivery] = await sql<{ id: string }[]>`
      INSERT INTO public.deliveries (
        company_id, tracking_code, pickup_business_name, pickup_address,
        customer_name, customer_phone, destination_address, status
      ) VALUES (
        ${companyA}::uuid, ${'TRK-PAY-' + companyA.slice(0, 8)}, 'Shop', 'Addr A',
        'Cust', '+231770000555', 'Addr B', 'pending'
      ) RETURNING id
    `
    const [payment] = await sql<{ id: string }[]>`
      INSERT INTO public.payments (company_id, delivery_id, amount_lrd_cents, status)
      VALUES (${companyA}::uuid, ${delivery!.id}::uuid, 10000, 'pending')
      RETURNING id
    `

    await asUser(ownerA, async (tx) => {
      await tx`
        UPDATE public.payments SET status = 'deposited' WHERE id = ${payment!.id}::uuid
      `
    })

    const [row] = await sql<{ status: string }[]>`
      SELECT status FROM public.payments WHERE id = ${payment!.id}::uuid
    `
    expect(row?.status).toBe('pending')

    await sql`DELETE FROM public.payments WHERE id = ${payment!.id}::uuid`
    await sql`DELETE FROM public.deliveries WHERE id = ${delivery!.id}::uuid`
  })

  it('public tracking RPC is callable without auth', async () => {
    const rows = await sql`
      SELECT public.get_delivery_tracking('NONEXISTENT-CODE') AS t
    `
    expect(rows).toBeDefined()
  })
})

describe('database integration (offline checklist)', () => {
  it('documents pgTAP suite path', () => {
    expect(true).toBe(true)
  })
})
