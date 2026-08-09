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

  it('create_company_with_owner activates the company and creates a trialing subscription', async () => {
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

    // Foundation fix under test: self-service registration must be
    // 'active' immediately — not left 'pending' for manual admin approval.
    const [company] = await sql<{ status: string }[]>`
      SELECT status FROM public.companies WHERE id = ${companyId}::uuid
    `
    expect(company?.status).toBe('active')

    const subs = await sql<{ status: string; plan_id: string; trial_ends_at: Date }[]>`
      SELECT status, plan_id::text, trial_ends_at
      FROM public.company_subscriptions
      WHERE company_id = ${companyId}::uuid
        AND status IN ('trialing', 'active', 'past_due')
    `
    expect(subs.length).toBe(1)
    expect(subs[0]?.status).toBe('trialing')
    expect(subs[0]?.plan_id).toBe(planStarterId)

    const trialMs = new Date(subs[0]!.trial_ends_at).getTime() - Date.now()
    expect(trialMs).toBeGreaterThan(6.9 * 24 * 60 * 60 * 1000)
    expect(trialMs).toBeLessThan(7.1 * 24 * 60 * 60 * 1000)

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

    // The company created in the previous test is already 'active' —
    // create_company_with_owner sets it automatically (see
    // 20260308190700_activate_self_service_companies.sql) — so no manual
    // activation step is needed here anymore.
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

  it('merchant registration activates immediately, same as company registration', async () => {
    const merchantOwnerId = crypto.randomUUID()
    await sql`
      INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, aud, role)
      VALUES (
        ${merchantOwnerId}::uuid,
        ${`onboard-merchant-${merchantOwnerId.slice(0, 8)}@test.local`},
        crypt('testpass', gen_salt('bf')),
        now(), '{}', '{}', 'authenticated', 'authenticated'
      )
    `
    await sql`
      INSERT INTO public.profiles (id, full_name) VALUES (${merchantOwnerId}::uuid, 'Merchant Owner')
      ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name
    `

    try {
      const companyId = await asUser(merchantOwnerId, async (tx) => {
        const [row] = await tx<{ create_company_with_owner: string }[]>`
          SELECT public.create_company_with_owner(
            'Onboard Merchant Co',
            '+231770000113',
            'onboard-merchant@test.local',
            NULL,
            'merchant'::public.company_business_type
          ) AS create_company_with_owner
        `
        return row.create_company_with_owner
      })

      const [company] = await sql<{ status: string; business_type: string }[]>`
        SELECT status, business_type FROM public.companies WHERE id = ${companyId}::uuid
      `
      expect(company?.status).toBe('active')
      expect(company?.business_type).toBe('merchant')

      const [sub] = await sql<{ status: string }[]>`
        SELECT status FROM public.company_subscriptions WHERE company_id = ${companyId}::uuid
      `
      expect(sub?.status).toBe('trialing')

      // Merchant-specific behavior must be unaffected by the activation fix.
      const [{ count: providerProfiles }] = await sql<{ count: string }[]>`
        SELECT COUNT(*)::text AS count
        FROM public.provider_marketplace_profiles WHERE company_id = ${companyId}::uuid
      `
      expect(Number(providerProfiles)).toBe(0)

      await sql`DELETE FROM public.company_subscriptions WHERE company_id = ${companyId}::uuid`
      await sql`DELETE FROM public.company_users WHERE company_id = ${companyId}::uuid`
      await sql`DELETE FROM public.companies WHERE id = ${companyId}::uuid`
    } finally {
      await sql`DELETE FROM public.profiles WHERE id = ${merchantOwnerId}::uuid`
      await sql`DELETE FROM auth.users WHERE id = ${merchantOwnerId}::uuid`
    }
  })

  it('super admin can suspend an active trial company, and it stays blocked', async () => {
    const suspendOwnerId = crypto.randomUUID()
    const adminId = crypto.randomUUID()
    await sql`
      INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, aud, role)
      VALUES
        (
          ${suspendOwnerId}::uuid, ${`onboard-susp-${suspendOwnerId.slice(0, 8)}@test.local`},
          crypt('testpass', gen_salt('bf')), now(), '{}', '{}', 'authenticated', 'authenticated'
        ),
        (
          ${adminId}::uuid, ${`onboard-admin-${adminId.slice(0, 8)}@test.local`},
          crypt('testpass', gen_salt('bf')), now(), '{}', '{}', 'authenticated', 'authenticated'
        )
    `
    await sql`
      INSERT INTO public.profiles (id, full_name) VALUES (${suspendOwnerId}::uuid, 'Suspend Owner')
      ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name
    `
    await sql`
      INSERT INTO public.profiles (id, full_name, is_super_admin) VALUES (${adminId}::uuid, 'Platform Admin', true)
      ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, is_super_admin = true
    `

    try {
      const companyId = await asUser(suspendOwnerId, async (tx) => {
        const [row] = await tx<{ create_company_with_owner: string }[]>`
          SELECT public.create_company_with_owner(
            'Suspend Target Co',
            '+231770000114',
            'onboard-susp@test.local',
            NULL,
            'logistics_provider'::public.company_business_type
          ) AS create_company_with_owner
        `
        return row.create_company_with_owner
      })

      const [before] = await sql<{ status: string }[]>`
        SELECT status FROM public.companies WHERE id = ${companyId}::uuid
      `
      expect(before?.status).toBe('active')

      await asUser(adminId, async (tx) => {
        await tx`SELECT public.admin_set_company_status(${companyId}::uuid, 'suspended'::public.company_status)`
      })

      const [after] = await sql<{ status: string }[]>`
        SELECT status FROM public.companies WHERE id = ${companyId}::uuid
      `
      expect(after?.status).toBe('suspended')

      await expect(
        asUser(suspendOwnerId, async (tx) => {
          await tx`
            SELECT public.create_delivery(
              ${companyId}::uuid, 'Pickup Shop', 'Monrovia', 'Customer', '+231770000444', 'Destination St'
            )
          `
        }),
      ).rejects.toThrow()

      await sql`DELETE FROM public.company_subscriptions WHERE company_id = ${companyId}::uuid`
      await sql`DELETE FROM public.company_users WHERE company_id = ${companyId}::uuid`
      await sql`DELETE FROM public.companies WHERE id = ${companyId}::uuid`
    } finally {
      await sql`DELETE FROM public.profiles WHERE id IN (${suspendOwnerId}::uuid, ${adminId}::uuid)`
      await sql`DELETE FROM auth.users WHERE id IN (${suspendOwnerId}::uuid, ${adminId}::uuid)`
    }
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
