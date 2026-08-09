/**
 * Extended RLS / tenant isolation tests (requires local Supabase + migrations).
 */
import postgres from 'postgres'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'

const dbUrl =
  process.env.DATABASE_URL ?? process.env.SUPABASE_DB_URL ?? 'postgresql://postgres:postgres@127.0.0.1:54322/postgres'

const runDb = process.env.RUN_DB_TESTS === '1'

describe.skipIf(!runDb)('RLS security suite', () => {
  const sql = postgres(dbUrl, { max: 1 })
  let planId: string
  let companyA: string
  let companyB: string
  let merchantA: string
  let providerB: string
  let ownerA: string
  let ownerB: string
  let merchantOwner: string
  let requestA: string

  beforeAll(async () => {
    try {
      await sql`SELECT 1`
    } catch {
      throw new Error(`Cannot connect to DATABASE_URL. Start Supabase locally and apply migrations.`)
    }
    const [plan] = await sql<{ id: string }[]>`
      SELECT id FROM public.subscriptions WHERE slug = 'starter' LIMIT 1
    `
    planId = plan!.id

    ownerA = crypto.randomUUID()
    ownerB = crypto.randomUUID()
    merchantOwner = crypto.randomUUID()
    companyA = crypto.randomUUID()
    companyB = crypto.randomUUID()
    merchantA = crypto.randomUUID()
    providerB = companyB
    requestA = crypto.randomUUID()

    await sql`
      INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, aud, role)
      VALUES
        (${ownerA}::uuid, ${`a-${ownerA.slice(0, 6)}@t.local`}, crypt('x', gen_salt('bf')), now(), 'authenticated', 'authenticated'),
        (${ownerB}::uuid, ${`b-${ownerB.slice(0, 6)}@t.local`}, crypt('x', gen_salt('bf')), now(), 'authenticated', 'authenticated'),
        (${merchantOwner}::uuid, ${`m-${merchantOwner.slice(0, 6)}@t.local`}, crypt('x', gen_salt('bf')), now(), 'authenticated', 'authenticated')
    `
    // handle_new_user already inserts a profile row on the auth.users insert
    // above; upsert here to set the test's intended full_name.
    await sql`
      INSERT INTO public.profiles (id, full_name) VALUES
        (${ownerA}::uuid, 'A'), (${ownerB}::uuid, 'B'), (${merchantOwner}::uuid, 'M')
      ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name
    `
    await sql`
      INSERT INTO public.companies (id, name, slug, email, phone, status, subscription_id, business_type)
      VALUES
        (${companyA}::uuid, 'Co A', ${'co-a-' + companyA.slice(0, 8)}, 'a@t.local', '+1', 'active', ${planId}::uuid, 'logistics_provider'),
        (${companyB}::uuid, 'Co B', ${'co-b-' + companyB.slice(0, 8)}, 'b@t.local', '+2', 'active', ${planId}::uuid, 'logistics_provider'),
        (${merchantA}::uuid, 'Merchant A', ${'merchant-a-' + merchantA.slice(0, 8)}, 'm@t.local', '+3', 'active', ${planId}::uuid, 'merchant')
    `
    await sql`
      INSERT INTO public.company_users (company_id, user_id, role, is_active) VALUES
        (${companyA}::uuid, ${ownerA}::uuid, 'company_owner', true),
        (${companyB}::uuid, ${ownerB}::uuid, 'company_owner', true),
        (${merchantA}::uuid, ${merchantOwner}::uuid, 'company_owner', true)
    `
    await sql`
      INSERT INTO public.company_subscriptions (company_id, plan_id, status, starts_at, current_period_start, current_period_end)
      SELECT id, ${planId}::uuid, 'active', now(), now(), now() + interval '30 days'
      FROM public.companies WHERE id IN (${companyA}::uuid, ${companyB}::uuid, ${merchantA}::uuid)
    `
    await sql`
      INSERT INTO public.delivery_requests (id, merchant_company_id, pickup_address, destination_address, status)
      VALUES (${requestA}::uuid, ${merchantA}::uuid, 'P', 'D', 'offered')
    `
    await sql`
      INSERT INTO public.delivery_offers (delivery_request_id, provider_company_id, quoted_amount_lrd_cents, status)
      VALUES (${requestA}::uuid, ${providerB}::uuid, 50000, 'pending')
    `
  })

  afterAll(async () => {
    await sql`DELETE FROM public.delivery_offers WHERE delivery_request_id = ${requestA}::uuid`
    await sql`DELETE FROM public.delivery_requests WHERE id = ${requestA}::uuid`
    await sql`DELETE FROM public.company_subscriptions WHERE company_id IN (${companyA}::uuid, ${companyB}::uuid, ${merchantA}::uuid)`
    await sql`DELETE FROM public.company_users WHERE company_id IN (${companyA}::uuid, ${companyB}::uuid, ${merchantA}::uuid)`
    await sql`DELETE FROM public.companies WHERE id IN (${companyA}::uuid, ${companyB}::uuid, ${merchantA}::uuid)`
    await sql`DELETE FROM public.profiles WHERE id IN (${ownerA}::uuid, ${ownerB}::uuid, ${merchantOwner}::uuid)`
    await sql`DELETE FROM auth.users WHERE id IN (${ownerA}::uuid, ${ownerB}::uuid, ${merchantOwner}::uuid)`
    await sql.end()
  })

  async function asUser<T>(userId: string, fn: (tx: postgres.Sql) => Promise<T>) {
    return sql.begin(async (tx) => {
      await tx`SELECT set_config('request.jwt.claim.sub', ${userId}, true)`
      await tx`SET LOCAL role authenticated`
      return fn(tx)
    })
  }

  it('merchant A cannot read merchant B delivery requests', async () => {
    const otherReq = crypto.randomUUID()
    await sql`
      INSERT INTO public.delivery_requests (id, merchant_company_id, pickup_address, destination_address, status)
      VALUES (${otherReq}::uuid, ${companyA}::uuid, 'x', 'y', 'draft')
    `
    const rows = await asUser(merchantOwner, (tx) =>
      tx`SELECT id FROM public.delivery_requests WHERE id = ${otherReq}::uuid`,
    )
    expect(rows).toHaveLength(0)
    await sql`DELETE FROM public.delivery_requests WHERE id = ${otherReq}::uuid`
  })

  it('provider B cannot read offers for other providers', async () => {
    const otherProvider = companyA
    const rows = await asUser(ownerB, (tx) =>
      tx`
        SELECT o.id FROM public.delivery_offers o
        WHERE o.provider_company_id = ${otherProvider}::uuid
      `,
    )
    expect(rows).toHaveLength(0)
  })

  it('merchant owner sees own marketplace request', async () => {
    const rows = await asUser(merchantOwner, (tx) =>
      tx`SELECT id FROM public.delivery_requests WHERE merchant_company_id = ${merchantA}::uuid`,
    )
    expect(rows.some((r) => r.id === requestA)).toBe(true)
  })

  it('suspended company subscription blocks can_use_feature', async () => {
    await sql`
      UPDATE public.company_subscriptions SET status = 'suspended'
      WHERE company_id = ${merchantA}::uuid
    `
    const ok = await sql<{ v: boolean }[]>`
      SELECT public.can_use_feature(${merchantA}::uuid, 'merchant_portal') AS v
    `
    expect(ok[0]?.v).toBe(false)
    await sql`
      UPDATE public.company_subscriptions SET status = 'active'
      WHERE company_id = ${merchantA}::uuid
    `
  })

  it('marketplace settlement cannot run twice', async () => {
    const txId = crypto.randomUUID()
    await sql`
      INSERT INTO public.marketplace_transactions (
        id, delivery_request_id, merchant_company_id, provider_company_id,
        gross_amount_lrd_cents, platform_fee_lrd_cents, provider_amount_lrd_cents, status
      ) VALUES (
        ${txId}::uuid, ${requestA}::uuid, ${merchantA}::uuid, ${providerB}::uuid,
        50000, 5000, 45000, 'pending'
      )
    `
    await sql`
      INSERT INTO public.marketplace_settlements (marketplace_transaction_id)
      VALUES (${txId}::uuid)
    `
    await expect(
      sql`INSERT INTO public.marketplace_settlements (marketplace_transaction_id) VALUES (${txId}::uuid)`,
    ).rejects.toThrow()
    await sql`DELETE FROM public.marketplace_settlements WHERE marketplace_transaction_id = ${txId}::uuid`
    await sql`DELETE FROM public.marketplace_transactions WHERE id = ${txId}::uuid`
  })

  it('public tracking rate limit blocks excessive lookups', async () => {
    const key = `test-${crypto.randomUUID()}`
    let ok = 0
    for (let i = 0; i < 65; i++) {
      const allowed = await sql<{ v: boolean }[]>`
        SELECT public.check_public_tracking_rate_limit(${key}) AS v
      `
      if (allowed[0]?.v) ok += 1
    }
    expect(ok).toBeLessThanOrEqual(60)
  })
})
