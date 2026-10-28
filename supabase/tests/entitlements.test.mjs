// Checks the rules of odd/tasks/server-validation.md S4, S5.1 through the same
// SQL the app calls: premium_entitlements is service-role-only, has_active_premium
// is exactly one row, and create_league / join_league_by_code stop free users at
// one league with the stable league_limit error.
//
//   cd supabase/tests && npm test

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';

const migrationsDir = new URL('../migrations/', import.meta.url);

// What Supabase provides before any migration runs.
const supabaseStub = `
  create role anon nologin;
  create role authenticated nologin;
  create role service_role nologin;
  create schema auth;
  create table auth.users (id uuid primary key, raw_user_meta_data jsonb not null default '{}');
  create function auth.uid() returns uuid language sql stable as $$
    select nullif(current_setting('request.jwt.claims', true)::json ->> 'sub', '')::uuid
  $$;
  grant usage on schema auth to anon, authenticated;
  grant usage on schema public to anon, authenticated;
  alter default privileges in schema public grant all on tables to anon, authenticated;
  alter default privileges in schema public grant all on sequences to anon, authenticated;
`;

async function freshDatabase() {
  const db = new PGlite({ extensions: { pgcrypto } });
  await db.exec(supabaseStub);
  for (const file of readdirSync(migrationsDir).filter((f) => f.endsWith('.sql')).sort()) {
    await db.exec(readFileSync(new URL(file, migrationsDir), 'utf8'));
  }
  return db;
}

let counter = 1000;
function uuid() {
  counter += 1;
  return `00000000-0000-4000-8000-${String(counter).padStart(12, '0')}`;
}

async function createUser(db, name) {
  const id = uuid();
  await db.query(`insert into auth.users (id, raw_user_meta_data) values ($1, $2)`, [
    id,
    { full_name: name },
  ]);
  await db.query(`update public.profiles set display_name = $2 where id = $1`, [id, name]);
  return id;
}

// Runs `sql` as a signed-in user, the way PostgREST does: role
// `authenticated` plus the JWT claims auth.uid() reads.
async function asUser(db, userID, sql, params = []) {
  return db.transaction(async (tx) => {
    await tx.exec('set local role authenticated');
    await tx.query(`select set_config('request.jwt.claims', $1, true)`, [
      JSON.stringify({ sub: userID, role: 'authenticated' }),
    ]);
    return (await tx.query(sql, params)).rows;
  });
}

// Runs `sql` with the publishable key and no session, the way PostgREST does.
async function asAnon(db, sql, params = []) {
  return db.transaction(async (tx) => {
    await tx.exec('set local role anon');
    await tx.query(`select set_config('request.jwt.claims', '', true)`);
    return (await tx.query(sql, params)).rows;
  });
}

// What the verify-premium Edge Function writes with the service role after an
// offline JWS check. expiresDays < 0 means already expired.
async function grantPremium(db, userID, { expiresDays = 30, revoked = false } = {}) {
  await db.query(
    `insert into public.premium_entitlements
       (user_id, original_transaction_id, product_id, expires_at, revoked_at, environment)
     values ($1, $2, 'com.acrstudio.drivy.premium.monthly',
             now() + make_interval(days => $3::int),
             case when $4 then now() else null end, 'Production')
     on conflict (user_id) do update
       set original_transaction_id = excluded.original_transaction_id,
           expires_at = excluded.expires_at,
           revoked_at = excluded.revoked_at`,
    [userID, `tx-${userID}`, expiresDays, revoked],
  );
}

// ---------------------------------------------------------------------------
// S5.1: the entitlement table and has_active_premium
// ---------------------------------------------------------------------------

test('premium S5.1: entitlements are readable only by their owner and writable by nobody but the service role', async () => {
  const db = await freshDatabase();
  const owner = await createUser(db, 'Owner');
  const other = await createUser(db, 'Other');
  await grantPremium(db, owner);

  const mine = await asUser(db, owner, `select user_id, original_transaction_id, product_id, environment from public.premium_entitlements`);
  assert.deepEqual(
    mine.map((r) => r.user_id),
    [owner],
  );
  assert.equal(mine[0].product_id, 'com.acrstudio.drivy.premium.monthly');
  assert.equal(mine[0].environment, 'Production');

  // RLS: a stranger sees no rows and learns nothing.
  assert.equal((await asUser(db, other, `select user_id from public.premium_entitlements`)).length, 0);

  // No client write path: the table is service-role-only.
  await assert.rejects(
    asUser(db, owner, `insert into public.premium_entitlements (user_id, original_transaction_id, product_id, expires_at) values ($1, 'x', 'p', now())`, [owner]),
    /permission denied|row-level security/,
  );
  await assert.rejects(
    asUser(db, owner, `update public.premium_entitlements set expires_at = now() + interval '10 years'`),
    /permission denied|row-level security/,
  );
  await assert.rejects(
    asUser(db, owner, `delete from public.premium_entitlements`),
    /permission denied|row-level security/,
  );
  await assert.rejects(asAnon(db, `select * from public.premium_entitlements`), /permission denied/);
});

test('premium S5.1: has_active_premium is exactly one un-revoked, un-expired row', async () => {
  const db = await freshDatabase();
  const active = await createUser(db, 'Active');
  const expired = await createUser(db, 'Expired');
  const revoked = await createUser(db, 'Revoked');
  const none = await createUser(db, 'None');
  await grantPremium(db, active);
  await grantPremium(db, expired, { expiresDays: -1 });
  await grantPremium(db, revoked, { revoked: true });

  const premiumOf = async (user) =>
    (await db.query(`select public.has_active_premium($1) as p`, [user])).rows[0].p;
  assert.equal(await premiumOf(active), true);
  assert.equal(await premiumOf(expired), false, 'an expired entitlement is not active');
  assert.equal(await premiumOf(revoked), false, 'a revoked entitlement is not active');
  assert.equal(await premiumOf(none), false, 'no entitlement is not active');
});

// ---------------------------------------------------------------------------
// S5.1: the free one-league cap behind league_limit
// ---------------------------------------------------------------------------

test('premium S5.1: a free user is capped at one league, as owner or as member', async () => {
  const db = await freshDatabase();
  const owner = await createUser(db, 'Owner');
  const joiner = await createUser(db, 'Joiner');
  const [first] = await asUser(db, owner, `select * from public.create_league('Primera')`);

  // Owner already leads one league: a second one is refused.
  await assert.rejects(
    asUser(db, owner, `select * from public.create_league('Segunda')`),
    /league_limit/,
  );
  // A member of another league cannot create either.
  await asUser(db, joiner, `select public.join_league_by_code($1)`, [first.invite_code]);
  await assert.rejects(
    asUser(db, joiner, `select * from public.create_league('Mia')`),
    /league_limit/,
  );

  // The refusal is P0001 with the stable message the app maps.
  await assert.rejects(
    asUser(db, owner, `select * from public.create_league('Segunda')`),
    (err) => err.code === 'P0001' && err.message === 'league_limit',
  );

  // The failed calls left nothing behind.
  assert.equal((await db.query(`select count(*)::int as c from public.leagues`)).rows[0].c, 1);
  assert.equal((await db.query(`select count(*)::int as c from public.league_members`)).rows[0].c, 2);
});

test('premium S5.1: joining a second league by code is refused for free users, allowed with active premium', async () => {
  const db = await freshDatabase();
  const a = await createUser(db, 'A');
  const b = await createUser(db, 'B');
  const joiner = await createUser(db, 'Joiner');
  const [first] = await asUser(db, a, `select * from public.create_league('L1')`);
  const [second] = await asUser(db, b, `select * from public.create_league('L2')`);

  await asUser(db, joiner, `select public.join_league_by_code($1)`, [first.invite_code]);
  await assert.rejects(
    asUser(db, joiner, `select public.join_league_by_code($1)`, [second.invite_code]),
    /league_limit/,
  );

  // Active premium lifts the cap.
  await grantPremium(db, joiner);
  const [joined] = await asUser(db, joiner, `select public.join_league_by_code($1) as id`, [second.invite_code]);
  assert.equal(joined.id, second.id);
  assert.equal(
    (await db.query(`select count(*)::int as c from public.league_members where user_id = $1`, [joiner])).rows[0].c,
    2,
  );
});

test('premium S5.1: expired or revoked premium no longer lifts the cap, but memberships are never removed', async () => {
  const db = await freshDatabase();
  const a = await createUser(db, 'A');
  const b = await createUser(db, 'B');
  const joiner = await createUser(db, 'Joiner');
  const [first] = await asUser(db, a, `select * from public.create_league('L1')`);
  const [second] = await asUser(db, b, `select * from public.create_league('L2')`);
  await grantPremium(db, joiner);
  await asUser(db, joiner, `select public.join_league_by_code($1)`, [first.invite_code]);

  // Expired: back to the cap for new joins...
  await grantPremium(db, joiner, { expiresDays: -1 });
  await assert.rejects(
    asUser(db, joiner, `select public.join_league_by_code($1)`, [second.invite_code]),
    /league_limit/,
  );
  await assert.rejects(asUser(db, joiner, `select * from public.create_league('Nueva')`), /league_limit/);

  // ...but never kicked out of the leagues it already belongs to.
  assert.equal(
    (await db.query(`select count(*)::int as c from public.league_members where user_id = $1`, [joiner])).rows[0].c,
    1,
  );

  // Revoked behaves the same.
  await grantPremium(db, joiner, { revoked: true });
  await assert.rejects(
    asUser(db, joiner, `select public.join_league_by_code($1)`, [second.invite_code]),
    /league_limit/,
  );
  assert.equal(
    (await db.query(`select count(*)::int as c from public.league_members where user_id = $1`, [joiner])).rows[0].c,
    1,
  );
});

test('premium S5.1: re-opening its own league invite still works without premium, and everything else is unchanged', async () => {
  const db = await freshDatabase();
  const owner = await createUser(db, 'Owner');
  const [league] = await asUser(db, owner, `select * from public.create_league('L')`);

  // The owner re-opening its own code is not a second league.
  const [again] = await asUser(db, owner, `select public.join_league_by_code($1) as id`, [league.invite_code]);
  assert.equal(again.id, league.id);

  // A user without any league still joins normally.
  const friend = await createUser(db, 'Friend');
  const [joined] = await asUser(db, friend, `select public.join_league_by_code($1) as id`, [league.invite_code]);
  assert.equal(joined.id, league.id);

  // A fresh user still creates its first league without premium.
  const newcomer = await createUser(db, 'Newcomer');
  const [newLeague] = await asUser(db, newcomer, `select * from public.create_league('Primera')`);
  assert.match(newLeague.invite_code, /^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$/);

  // Anonymous callers still cannot touch the RPCs or the table.
  await assert.rejects(asAnon(db, `select * from public.create_league('x')`), /permission denied/);
  await assert.rejects(asAnon(db, `select public.join_league_by_code('x')`), /permission denied/);
  await assert.rejects(asAnon(db, `select public.has_active_premium($1)`, [owner]), /permission denied/);
});
