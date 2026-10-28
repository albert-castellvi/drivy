// Independent verifier probes for PR #11 (fix/security-hardening), migration
// 20261028111321_security_hardening.sql and odd/tasks/security-hardening.md
// S2, S3, S7, written by the independent verifier and kept as regression tests
// (its blocker and three probes were flipped to the fixed behaviour, L5).

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';

const migrationsDir = new URL('../migrations/', import.meta.url);
const migrations = readdirSync(migrationsDir)
  .filter((f) => f.endsWith('.sql'))
  .sort();
const HARDENING = '20261028111321_security_hardening.sql';

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

// `upTo` lets a test stop before the hardening migration, which is how the
// existing-data path (a database that is already in production) is reproduced.
async function freshDatabase(upTo = migrations.length) {
  const db = new PGlite({ extensions: { pgcrypto } });
  await db.exec(supabaseStub);
  for (const file of migrations.slice(0, upTo)) {
    await db.exec(readFileSync(new URL(file, migrationsDir), 'utf8'));
  }
  return db;
}

async function applyHardening(db) {
  return db.exec(readFileSync(new URL(HARDENING, migrationsDir), 'utf8'));
}

let counter = 0;
function uuid() {
  counter += 1;
  return `00000000-0000-4000-8000-${String(counter).padStart(12, '0')}`;
}

// Signs a user up the way the auth service does: raw_user_meta_data only. The
// old handle_new_user copies the Apple full name into display_name, so this is
// exactly the production data the hardening migration has to survive.
async function signUpLegacy(db, fullName) {
  const id = uuid();
  const meta = fullName === undefined ? {} : { full_name: fullName };
  await db.query(`insert into auth.users (id, raw_user_meta_data) values ($1, $2)`, [id, meta]);
  return id;
}

async function createUser(db, name) {
  const id = uuid();
  await db.query(`insert into auth.users (id, raw_user_meta_data) values ($1, $2)`, [id, { full_name: name }]);
  await db.query(`update public.profiles set display_name = $2 where id = $1`, [id, name]);
  return id;
}

async function asUser(db, userID, sql, params = []) {
  return db.transaction(async (tx) => {
    await tx.exec('set local role authenticated');
    await tx.query(`select set_config('request.jwt.claims', $1, true)`, [
      JSON.stringify({ sub: userID, role: 'authenticated' }),
    ]);
    return (await tx.query(sql, params)).rows;
  });
}

async function asAnon(db, sql, params = []) {
  return db.transaction(async (tx) => {
    await tx.exec('set local role anon');
    await tx.query(`select set_config('request.jwt.claims', '', true)`);
    return (await tx.query(sql, params)).rows;
  });
}

// ---------------------------------------------------------------------------
// S2 — existing profile data the ALTER TABLE has to validate
// ---------------------------------------------------------------------------

test('blocker A1: the hardening migration applies to a database seeded with real Apple names', async () => {
  const db = await freshDatabase(migrations.indexOf(HARDENING)); // schema v1 + hardening, no hardening yet
  // Two names a real person has, both longer than the new 30-char limit.
  const longName = 'María del Carmen Fernández de la Vega';
  assert.ok(longName.length > 30);
  await signUpLegacy(db, longName);
  await signUpLegacy(db, 'María José Rodríguez-Casanova y Puente');
  await signUpLegacy(db); // the 'Driver' fallback path

  // No exception: adding the constraint must not abort on data it did not clean.
  await applyHardening(db);

  const names = (await db.query(`select display_name from public.profiles order by display_name`)).rows;
  for (const row of names) {
    assert.ok(row.display_name.length >= 1 && row.display_name.length <= 30, row.display_name);
  }
});

test('probe A1b: legacy names outside 1-30 become pseudonyms and the constraint is added', async () => {
  const db = await freshDatabase(migrations.indexOf(HARDENING));
  const longName = await signUpLegacy(db, 'María del Carmen Fernández de la Vega');
  const driver = await signUpLegacy(db); // seeded as 'Driver'

  await applyHardening(db);

  for (const id of [longName, driver]) {
    const [row] = (await db.query(`select display_name from public.profiles where id = $1`, [id])).rows;
    assert.match(row.display_name, /^Conductor \d{4}$/);
  }
  assert.equal(
    (await db.query(`select count(*)::int as n from pg_constraint where conname = 'profiles_display_name_length'`)).rows[0].n,
    1,
  );
});

// ---------------------------------------------------------------------------
// S2 — what a client can still write on its profile
// ---------------------------------------------------------------------------

test('probe A2: authenticated holds update only on display_name and the trigger still stamps updated_at', async () => {
  const db = await freshDatabase();
  const id = await createUser(db, 'Ana');
  const before = (await db.query(`select updated_at from public.profiles where id = $1`, [id])).rows[0].updated_at;

  const [privs] = (
    await db.query(`
      select has_column_privilege('authenticated', 'public.profiles', 'display_name', 'update') as name_ok,
             has_column_privilege('authenticated', 'public.profiles', 'avatar_url', 'update') as avatar_ok,
             has_column_privilege('authenticated', 'public.profiles', 'updated_at', 'update') as updated_ok,
             has_column_privilege('authenticated', 'public.profiles', 'created_at', 'update') as created_ok`,
  )).rows;
  assert.deepEqual(
    { name: privs.name_ok, avatar: privs.avatar_ok, updated: privs.updated_ok, created: privs.created_ok },
    { name: true, avatar: false, updated: false, created: false },
  );

  // The BEFORE UPDATE trigger writes updated_at although the caller has no
  // privilege on that column: trigger writes are not privilege-checked.
  await asUser(db, id, `update public.profiles set display_name = 'Ana B' where id = $1`, [id]);
  const after = (await db.query(`select display_name, updated_at from public.profiles where id = $1`, [id])).rows[0];
  assert.equal(after.display_name, 'Ana B');
  assert.ok(new Date(after.updated_at) >= new Date(before), 'set_updated_at did not fire');

  await assert.rejects(
    asUser(db, id, `update public.profiles set display_name = 'Ana', avatar_url = 'https://x/y.png' where id = $1`, [id]),
    /permission denied/,
  );
  await assert.rejects(
    asUser(db, id, `update public.profiles set updated_at = now() where id = $1`, [id]),
    /permission denied/,
  );
});

test('probe A3: co-member uuids are still readable through the table endpoints (is_me is RPC-only)', async () => {
  const db = await freshDatabase();
  const owner = await createUser(db, 'Owner');
  const mate = await createUser(db, 'Mate');
  const [league] = await asUser(db, owner, `select * from public.create_league('L')`);
  await asUser(db, mate, `select public.join_league_by_code($1)`, [league.invite_code]);

  // The RPCs are clean …
  const ranking = await asUser(db, mate, `select * from public.league_weekly_ranking($1, $2)`, [
    league.id,
    (await db.query(`select public.madrid_week_start()::text as w`)).rows[0].w,
  ]);
  assert.deepEqual(Object.keys(ranking[0]).sort(), ['display_name', 'is_me', 'rank', 'week_xp']);

  // … but PostgREST table reads still hand out every member's uuid, and the
  // owner's uuid comes with the league row itself.
  const members = await asUser(db, mate, `select user_id from public.league_members order by user_id`);
  assert.equal(members.length, 2);
  const [row] = await asUser(db, mate, `select owner_id from public.leagues where id = $1`, [league.id]);
  assert.equal(row.owner_id, owner);
});

// ---------------------------------------------------------------------------
// S7 — grants
// ---------------------------------------------------------------------------

test('probe A4: no function of this repo is executable by anon (extension functions aside)', async () => {
  const db = await freshDatabase();
  const reachable = (
    await db.query(`
      select p.proname
        from pg_proc p
       where p.pronamespace = 'public'::regnamespace
         and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
         and has_function_privilege('anon', p.oid, 'execute')
       order by 1`)
  ).rows.map((r) => r.proname);
  assert.deepEqual(reachable, [], 'anon can execute these public functions');

  // The extension functions pgcrypto registered in public (Supabase keeps them
  // in `extensions`, PGlite keeps them here) are the only ones left, and they
  // hold no user data.
  const extensions = (
    await db.query(`
      select p.proname
        from pg_proc p
        join pg_depend d on d.objid = p.oid and d.deptype = 'e'
       where p.pronamespace = 'public'::regnamespace
         and has_function_privilege('anon', p.oid, 'execute')
       order by 1`)
  ).rows.map((r) => r.proname);
  for (const name of ['create_league', 'join_league_by_code', 'pseudonym', 'my_xp', 'public_league_ranking']) {
    assert.ok(!extensions.includes(name), `${name} counted as an extension function`);
  }
});

test('probe A5: anon holds no table privilege and authenticated no truncate/references/trigger', async () => {
  const db = await freshDatabase();
  const relations = (
    await db.query(`
      select c.relname, c.relkind
        from pg_class c
       where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm')`)
  ).rows;

  for (const rel of relations) {
    for (const priv of ['SELECT', 'INSERT', 'UPDATE', 'DELETE']) {
      assert.equal(
        (await db.query(`select has_table_privilege('anon', $1, $2) as p`, [`public.${rel.relname}`, priv])).rows[0].p,
        false,
        `anon holds ${priv} on ${rel.relname}`,
      );
    }
  }

  for (const rel of relations.filter((r) => r.relkind === 'r')) {
    for (const priv of ['TRUNCATE', 'REFERENCES', 'TRIGGER']) {
      assert.equal(
        (await db.query(`select has_table_privilege('authenticated', $1, $2) as p`, [`public.${rel.relname}`, priv]))
          .rows[0].p,
        false,
        `authenticated holds ${priv} on ${rel.relname}`,
      );
    }
  }

  // Anon still needs the schema itself, and the day helpers must stay callable
  // by signed-in users: they run inside the CHECK constraints of their inserts.
  assert.equal((await db.query(`select has_schema_privilege('anon', 'public', 'usage') as p`)).rows[0].p, true);
  for (const signature of ['public.madrid_today()', 'public.madrid_week_start(timestamptz)']) {
    assert.equal(
      (await db.query(`select has_function_privilege('authenticated', $1, 'execute') as p`, [signature])).rows[0].p,
      true,
      `${signature} not executable by authenticated`,
    );
  }
  // And the anon revoke is only a grant change: it does not touch RLS.
  assert.equal((await db.query(`select count(*)::int as n from pg_tables where schemaname='public' and rowsecurity=false`)).rows[0].n, 0);
});

test('probe A6: later migrations get no anon table access, but the function default revoke is a no-op here', async () => {
  const db = await freshDatabase();
  // A future migration runs as the same role, so its objects inherit these.
  await db.exec(`
    create table public.future_table (id int);
    create function public.future_fn() returns int language sql as $$ select 1 $$;
    create view public.future_view as select 1 as one;
  `);

  for (const [rel, priv] of [
    ['public.future_table', 'SELECT'],
    ['public.future_table', 'INSERT'],
    ['public.future_view', 'SELECT'],
  ]) {
    assert.equal(
      (await db.query(`select has_table_privilege('anon', $1, $2) as p`, [rel, priv])).rows[0].p,
      false,
      `anon holds ${priv} on ${rel}`,
    );
  }

  // Observations, not requirements (advisories in the report):
  // 1. The functions default-privilege revoke has no effect in this harness: a
  //    new function still carries the hard-wired PUBLIC EXECUTE (proacl NULL),
  //    so anon can call it. There is no pg_default_acl row for functions.
  const futureACL = (await db.query(`select proacl from pg_proc where proname = 'future_fn'`)).rows[0];
  const funcDefaults = (await db.query(`select count(*)::int as n from pg_default_acl where defaclobjtype = 'f'`)).rows[0].n;
  assert.equal(futureACL.proacl, null);
  assert.equal(funcDefaults, 0);
  assert.equal(
    (await db.query(`select has_function_privilege('anon', 'public.future_fn()', 'execute') as p`)).rows[0].p,
    true,
  );
  // 2. Future tables keep TRUNCATE, REFERENCES and TRIGGER for authenticated:
  //    the ALTER DEFAULT PRIVILEGES line only covers anon.
  assert.equal(
    (await db.query(`select has_table_privilege('authenticated', 'public.future_table', 'truncate') as p`)).rows[0].p,
    true,
  );
  assert.equal(
    (await db.query(`select has_table_privilege('authenticated', 'public.future_table', 'references') as p`)).rows[0].p,
    true,
  );
  assert.equal(
    (await db.query(`select has_table_privilege('authenticated', 'public.future_table', 'trigger') as p`)).rows[0].p,
    true,
  );
});

test('probe A7: sign-up still works for an auth-service role with no execute on the trigger', async () => {
  const db = await freshDatabase();
  // Supabase's own auth service: it may insert into auth.users and nothing else
  // in public. It holds no EXECUTE on public.handle_new_user() after the revoke.
  await db.exec(`
    create role supabase_auth_admin nologin;
    grant usage on schema auth to supabase_auth_admin;
    grant insert on auth.users to supabase_auth_admin;
  `);
  assert.equal(
    (await db.query(`select has_function_privilege('supabase_auth_admin', 'public.handle_new_user()', 'execute') as p`))
      .rows[0].p,
    false,
  );

  const id = uuid();
  await db.transaction(async (tx) => {
    await tx.exec('set local role supabase_auth_admin');
    await tx.query(`insert into auth.users (id, raw_user_meta_data) values ($1, $2)`, [
      id,
      { full_name: 'Ana García' },
    ]);
  });

  const [profile] = (await db.query(`select display_name, avatar_url from public.profiles where id = $1`, [id])).rows;
  assert.match(profile.display_name, /^Conductor \d{4}$/);
  assert.equal(profile.avatar_url, null);
});

// ---------------------------------------------------------------------------
// S3 — invite codes, cap, rate limit
// ---------------------------------------------------------------------------

test('probe A8: create_league never repeats a code and covers the whole alphabet', async () => {
  const db = await freshDatabase();
  const owner = await createUser(db, 'Owner');
  // A free user may hold one league (S5.1 of server-validation), so the second
  // create_league would raise league_limit. The owner is premium here: the loop
  // keeps testing code generation and also proves premium lifts the cap.
  await db.query(
    `insert into public.premium_entitlements
       (user_id, original_transaction_id, product_id, expires_at)
     values ($1, 'tx-a8-owner', 'com.acrstudio.drivy.premium.monthly', now() + interval '30 days')`,
    [owner],
  );
  const codes = new Set();
  const symbols = new Set();
  for (let i = 0; i < 60; i += 1) {
    const [league] = await asUser(db, owner, `select * from public.create_league($1)`, [`L${i}`]);
    assert.match(league.invite_code, /^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$/);
    codes.add(league.invite_code);
    for (const ch of league.invite_code) symbols.add(ch);
  }
  assert.equal(codes.size, 60, 'a code was drawn twice in 60 draws of a 40-bit space');
  assert.ok(symbols.size >= 20, `only ${symbols.size} distinct symbols in 480 draws`);
  // The ambiguous glyphs never appear.
  for (const ch of 'IO01') assert.equal(symbols.has(ch), false, `${ch} is in the alphabet`);
});

test('probe A9: joined-at-the-cap is refused, no client can insert a member, and both failures look identical', async () => {
  const db = await freshDatabase();
  const owner = await createUser(db, 'Owner');
  const [league] = await asUser(db, owner, `select * from public.create_league('L')`);
  for (let i = 0; i < 24; i += 1) {
    const member = await createUser(db, `M${i}`);
    await asUser(db, member, `select public.join_league_by_code($1)`, [league.invite_code]);
  }

  const late = await createUser(db, 'Late');
  const [full] = await asUser(db, late, `select public.join_league_by_code($1) as id`, [league.invite_code]);
  const [unknown] = await asUser(db, late, `select public.join_league_by_code('ZZZZZZZZ') as id`);
  assert.equal(full.id, null);
  assert.equal(unknown.id, null, 'a full league and an unknown code answer differently');

  // No client can create a league without going through create_league, nor
  // take over a league it does not own.
  await assert.rejects(
    asUser(db, owner, `insert into public.leagues (name, owner_id, invite_code) values ('X', $1, 'MINE0000')`, [owner]),
    /row-level security/,
  );
  const other = await createUser(db, 'Other');
  const [otherLeague] = await asUser(db, other, `select * from public.create_league('Otra')`);
  // Nobody may write invite_code at all (only name is updatable).
  await assert.rejects(
    asUser(db, owner, `update public.leagues set invite_code = 'STEAL000' where id = $1`, [otherLeague.id]),
    /permission denied/,
  );
  const [untouched] = (
    await db.query(`select invite_code from public.leagues where id = $1`, [otherLeague.id])
  ).rows;
  assert.equal(untouched.invite_code, otherLeague.invite_code);

  // The only writer of league_members besides the RPC is create_league, and the
  // owner cannot add anyone directly either.
  await assert.rejects(
    asUser(db, owner, `insert into public.league_members (league_id, user_id) values ($1, $2)`, [league.id, late]),
    /row-level security/,
  );
  assert.equal(
    (await db.query(`select count(*)::int as n from public.league_members where league_id = $1`, [league.id])).rows[0].n,
    25,
  );
});

test('probe A10: the hourly budget is 10 recorded failures, the daily cleanup frees it, and the record survives the null answer', async () => {
  const db = await freshDatabase();
  const owner = await createUser(db, 'Owner');
  const [league] = await asUser(db, owner, `select * from public.create_league('L')`);

  const prober = await createUser(db, 'Prober');
  // Budget spent: nine failures already on record, all inside the hour.
  for (let i = 0; i < 9; i += 1) {
    await db.query(`insert into public.league_join_failures (user_id, attempted_at) values ($1, now() - interval '5 minutes')`, [prober]);
  }
  // The tenth is still answered (and recorded) even though the RPC returns null.
  const [tenth] = await asUser(db, prober, `select public.join_league_by_code('NOPEAAAA') as id`);
  assert.equal(tenth.id, null);
  const count = (await db.query(`select count(*)::int as n from public.league_join_failures where user_id = $1`, [prober])).rows[0].n;
  assert.equal(count, 10, 'the failure was rolled back with the null answer');

  await assert.rejects(
    asUser(db, prober, `select public.join_league_by_code($1)`, [league.invite_code]),
    /too_many_attempts/,
  );

  // One day later the cleanup in front of the check has emptied the budget.
  await db.query(`update public.league_join_failures set attempted_at = now() - interval '25 hours' where user_id = $1`, [prober]);
  const [recovered] = await asUser(db, prober, `select public.join_league_by_code($1) as id`, [league.invite_code]);
  assert.equal(recovered.id, league.id);
  assert.equal(
    (await db.query(`select count(*)::int as n from public.league_join_failures where user_id = $1`, [prober])).rows[0].n,
    0,
    'expired rows were not cleaned up',
  );
});

test('probe A11: the owner can rename its league but never rewrite the server-drawn invite_code', async () => {
  const db = await freshDatabase();
  const owner = await createUser(db, 'Owner');
  const [league] = await asUser(db, owner, `select * from public.create_league('L')`);

  await assert.rejects(
    asUser(db, owner, `update public.leagues set invite_code = 'A' where id = $1`, [league.id]),
    /permission denied/,
  );
  const [renamed] = await asUser(db, owner, `update public.leagues set name = 'Amigos' where id = $1 returning name`, [
    league.id,
  ]);
  assert.equal(renamed.name, 'Amigos');
});

test('probe A12: a name that breaks the table check surfaces as a raw Postgres error', async () => {
  const db = await freshDatabase();
  const owner = await createUser(db, 'Owner');
  await assert.rejects(
    asUser(db, owner, `select * from public.create_league($1)`, ['x'.repeat(61)]),
    /check constraint|violates check/,
  );
  await assert.rejects(asUser(db, owner, `select * from public.create_league(null)`), /null value|not-null/);
});

test('probe A13: every RPC still open to clients, and the uuids it can return', async () => {
  const db = await freshDatabase();
  const rows = (
    await db.query(`
      select p.proname, pg_get_function_result(p.oid) as result
        from pg_proc p
       where p.pronamespace = 'public'::regnamespace
         and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
         and has_function_privilege('authenticated', p.oid, 'execute')
       order by 1`)
  ).rows;
  // The exact client surface: these, and nothing the migration forgot to revoke.
  assert.deepEqual(rows.map((r) => r.proname), [
    'create_league',
    'join_league_by_code',
    'league_weekly_ranking',
    'madrid_today',
    'madrid_week_start',
    'my_league_ids',
    'my_xp',
    'public_league_current',
    'public_league_ranking',
    'set_public_league_opt_in',
  ]);
  // Only these return a uuid column, and each one is an id of the caller's own
  // row, of a league or of a group: no user uuid of somebody else.
  const withUUID = rows.filter((r) => r.result.includes('uuid')).map((r) => r.proname);
  assert.deepEqual(withUUID.sort(), ['create_league', 'join_league_by_code', 'my_league_ids', 'public_league_current']);
  assert.match(rows.find((r) => r.proname === 'create_league').result, /owner_id uuid/);
  assert.match(rows.find((r) => r.proname === 'public_league_current').result, /group_id uuid/);
});

test('probe A14: the S7 revokes did not take away a path the client uses', async () => {
  const db = await freshDatabase();
  const id = await createUser(db, 'Ana');

  // Views and the ledger stay readable by signed-in users.
  const views = (await db.query(`select relname from pg_class where relnamespace = 'public'::regnamespace and relkind in ('v','m')`)).rows;
  assert.ok(views.length > 0);
  for (const view of views) {
    assert.equal(
      (await db.query(`select has_table_privilege('authenticated', $1, 'select') as p`, [`public.${view.relname}`])).rows[0].p,
      true,
      `authenticated lost SELECT on ${view.relname}`,
    );
  }
  assert.ok((await asUser(db, id, `select * from public.xp_ledger`)) !== undefined);

  // Insert paths whose CHECK constraints call madrid_today(): still allowed.
  // Every write is real data the app itself sends: three 5 km drives of today
  // (six minutes each, no events) earn the quest and the first habit level, so
  // the rules of S3 of server-validation accept them.
  const today = (await db.query(`select public.madrid_today()::text as d`)).rows[0].d;
  for (let i = 0; i < 3; i += 1) {
    await asUser(
      db,
      id,
      `insert into public.drives (user_id, started_at, ended_at, distance_km, duration_s, score)
       values ($1,
               (public.madrid_today() + time '00:05' + make_interval(mins => $2::int)) at time zone 'Europe/Madrid',
               (public.madrid_today() + time '00:11' + make_interval(mins => $2::int)) at time zone 'Europe/Madrid',
               5, 360, 95)`,
      [id, i * 10],
    );
  }
  await asUser(db, id, `insert into public.quest_completions (day, quest_id) values ($1, 'clean_drive')`, [today]);
  await asUser(db, id, `insert into public.habit_levels (unit, level) values ('smooth_braking', 1)`);
  assert.equal((await asUser(db, id, `select count(*)::int as n from public.drives`))[0].n, 3);

  // A settings-style PATCH of one column still works end to end.
  const patched = await asUser(db, id, `update public.profiles set display_name = 'Ana G' where id = $1 returning display_name`, [id]);
  assert.equal(patched[0].display_name, 'Ana G');
});
