/**
 * Onboarding subscription lifecycle (requires local Supabase + migrations).
 * RUN_DB_TESTS=1 npm run test:db
 */
import postgres from 'postgres'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'

const dbUrl =
  process.env.DATABASE_URL ??
  process.env.SUPABASE_DB_URL ??
  'postgresql://postgres:postgres@127.0.0.1:54322/postgres'

const runDb = process.env.RUN_DB_TESTS === '1'

describe.skipIf(!runDb)('onboarding company subscription', () => {
  const sql = postgres(dbUrl, { max: 1 })
  let ownerId: string
  let planStarterId: string
  let createdCompanyId: string | null = null

  beforeAll(async () => {
    try {
      await sql`SELECT 1`
    } catch {
      throw new Error('Cannot connect to DATABASE_URL. Start Supabase and apply migrations.')
    }

    const [plan] = await sql<{ id: string }[]>`
      SELECT id FROM public.subscriptions WHERE slug = 'starter' LIMIT 1
    `
    planStarterId = plan?.id
    if (!planStarterId) throw new Error('Missing starter plan')

    ownerId = crypto.randomUUID()
    await sql`
      INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, aud, role)
      VALUES (
        ${ownerId}::uuid,
        ${`onboard-sub-${ownerId.slice(0, 8)}@test.local`},
        crypt('testpass', gen_salt('bf')),
        now(), '{}', '{}', 'authenticated', 'authenticated'
      )
    `
    // handle_new_user already inserts a profile row on the auth.users insert
    // above; upsert here to set the test's intended full_name/is_super_admin.
    await sql`
      INSERT INTO public.profiles (id, full_name, is_super_admin)
      VALUES (${ownerId}::uuid, 'Onboard Owner', false)
      ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, is_super_admin = EXCLUDED.is_super_admin
    `
  })

  afterAll(async () => {
    if (createdCompanyId) {
      await sql`DELETE FROM public.deliveries WHERE company_id = ${createdCompanyId}::uuid`
      await sql`DELETE FROM public.riders WHERE company_id = ${createdCompanyId}::uuid`
      await sql`DELETE FROM public.provider_marketplace_profiles WHERE company_id = ${createdCompanyId}::uuid`
      await sql`DELETE FROM public.company_subscriptions WHERE company_id = ${createdCompanyId}::uuid`
      await sql`DELETE FROM public.company_users WHERE company_id = ${createdCompanyId}::uuid`
      await sql`DELETE FROM public.companies WHERE id = ${createdCompanyId}::uuid`
    }
    await sql`DELETE FROM public.profiles WHERE id = ${ownerId}::uuid`
    await sql`DELETE FROM auth.users WHERE id = ${ownerId}::uuid`
    await sql.end()
  })

  async function asUser<T>(userId: string, fn: (tx: postgres.Sql) => Promise<T>) {
    return sql.begin(async (tx) => {
      await tx`SELECT set_config('request.jwt.claim.sub', ${userId}, true)`
      await tx`SET LOCAL role authenticated`
      return fn(tx)
    })
  }

  it('create_company_with_owner creates initial trialing subscription', async () => {
    const companyId = await asUser(ownerId, async (tx) => {
      const [row] = await tx<{ create_company_with_owner: string }[]>`
        SELECT public.create_company_with_owner(
          'Onboard Sub Co',
          '+231770000111',
          'onboard-sub@test.local',
          NULL,
          'logistics_provider'::public.company_business_type
        ) AS create_company_with_owner
      `
      return row.create_company_with_owner
    })

    const subs = await sql<{ status: string; plan_id: string }[]>`
      SELECT status, plan_id::text
      FROM public.company_subscriptions
      WHERE company_id = ${companyId}::uuid
        AND status IN ('trialing', 'active', 'past_due')
    `
    expect(subs.length).toBe(1)
    expect(subs[0]?.status).toBe('trialing')
    expect(subs[0]?.plan_id).toBe(planStarterId)
    createdCompanyId = companyId
  })

  it('onboarding retry does not duplicate open subscription', async () => {
    const companyId = await asUser(ownerId, async (tx) => {
      const [row] = await tx<{ id: string }[]>`
        SELECT public.create_company_with_owner(
          'Ignored Name',
          '+231770000112',
          'ignored@test.local'
        ) AS id
      `
      return row.id
    })

    const [{ count }] = await sql<{ count: string }[]>`
      SELECT COUNT(*)::text AS count
      FROM public.company_subscriptions
      WHERE company_id = ${companyId}::uuid
        AND status IN ('trialing', 'active', 'past_due')
    `
    expect(Number(count)).toBe(1)
  })

  it('allows rider and delivery creation when subscription is present', async () => {
    const companyId = await sql<{ company_id: string }[]>`
      SELECT company_id::text FROM public.company_users WHERE user_id = ${ownerId}::uuid LIMIT 1
    `.then((r) => r[0]?.company_id)

    expect(companyId).toBeTruthy()

    // companies.status defaults to 'pending' (initial_schema.sql) and nothing
    // in this codebase ever transitions it to 'active' automatically —
    // create_company_with_owner doesn't set it, and the only UPDATE of
    // companies.status anywhere is the super-admin activate/suspend RPC
    // (20260308180000_super_admin_control_tower.sql). assert_company_operational
    // rejects any non-active company, so a freshly self-served company cannot
    // create riders/deliveries — i.e. the 7-day free trial is not actually
    // usable until a super admin manually activates the company. That gap is
    // a product decision outside this audit's scope, not something to paper
    // over silently, so it's activated explicitly here (as a human operator
    // would have to) rather than assumed automatic.
    await sql`UPDATE public.companies SET status = 'active' WHERE id = ${companyId}::uuid`

    await sql`
      INSERT INTO public.riders (company_id, full_name, phone, rider_code, status)
      VALUES (${companyId}::uuid, 'Rider One', '+231770000222', 'R-ONB-1', 'available')
    `

    await asUser(ownerId, async (tx) => {
      await tx`
        SELECT public.create_delivery(
          ${companyId}::uuid,
          'Pickup Shop',
          'Monrovia',
          'Customer',
          '+231770000333',
          'Destination St'
        )
      `
    })

    const [{ riders, deliveries }] = await sql<{ riders: string; deliveries: string }[]>`
      SELECT
        (SELECT COUNT(*)::text FROM public.riders WHERE company_id = ${companyId}::uuid) AS riders,
        (SELECT COUNT(*)::text FROM public.deliveries WHERE company_id = ${companyId}::uuid) AS deliveries
    `
    expect(Number(riders)).toBeGreaterThanOrEqual(1)
    expect(Number(deliveries)).toBeGreaterThanOrEqual(1)
  })
})

describe('onboarding subscription (static migration checks)', () => {
  it('migration defines 7-day trial helper', async () => {
    const fs = await import('node:fs/promises')
    const sqlText = await fs.readFile(
      'supabase/migrations/20260308120000_seven_day_free_trial.sql',
      'utf8',
    )
    expect(sqlText).toContain("INTERVAL '7 days'")
    expect(sqlText).toContain('expire_elapsed_company_trials')
    expect(sqlText).toContain('trial_expired')
  })
})
