// Runs every migration on a fresh PGlite database with a minimal stand-in for
// Supabase's `auth` schema and roles, then checks the rules of
// odd/tasks/duolingo-loop.md through the same SQL the app calls.
//
//   cd supabase/tests && npm ci && npm test

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

let counter = 0;
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
  // Sign-up seeds a pseudonym (S2 of security-hardening); tests name people.
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

async function weekStart(db) {
  return (await db.query(`select public.madrid_week_start()::text as w`)).rows[0].w;
}

// A drive that started today at noon, Madrid time.
async function addDrive(db, userID, { km, score, daysAgo = 0 }) {
  await db.query(
    `insert into public.drives (user_id, started_at, ended_at, distance_km, duration_s, score)
     values ($1,
             ((now() at time zone 'Europe/Madrid')::date - $4::int + time '12:00') at time zone 'Europe/Madrid',
             ((now() at time zone 'Europe/Madrid')::date - $4::int + time '12:30') at time zone 'Europe/Madrid',
             $2, 1800, $3)`,
    [userID, km, score, daysAgo],
  );
}

// Supabase records each applied migration by the 14-digit version in its file
// name; a file without it cannot be matched with the remote history.
test('every migration file is named <14-digit version>_<name>.sql', () => {
  const files = readdirSync(migrationsDir).filter((f) => f.endsWith('.sql'));
  assert.ok(files.length > 0);
  for (const file of files) {
    assert.match(file, /^\d{14}_[a-z0-9_]+\.sql$/);
  }
});

test('S10: league tables are readable without RLS recursion, and only by members', async () => {
  const db = await freshDatabase();
  const owner = await createUser(db, 'Owner');
  const outsider = await createUser(db, 'Outsider');

  const [league] = await asUser(db, owner, `select * from public.create_league('Amigos')`);

  assert.equal((await asUser(db, owner, `select id from public.leagues`)).length, 1);
  assert.equal((await asUser(db, owner, `select user_id from public.league_members`)).length, 1);
  assert.equal((await asUser(db, owner, `select id from public.profiles`)).length, 1);

  assert.equal((await asUser(db, outsider, `select id from public.leagues`)).length, 0);
  assert.equal((await asUser(db, outsider, `select user_id from public.league_members`)).length, 0);
  assert.deepEqual(
    (await asUser(db, outsider, `select id from public.profiles`)).map((r) => r.id),
    [outsider],
  );

  // Joining by code still works, and makes the owner's profile visible.
  const [joined] = await asUser(db, outsider, `select public.join_league_by_code($1) as id`, [league.invite_code]);
  assert.equal(joined.id, league.id);
  assert.equal((await asUser(db, outsider, `select id from public.profiles`)).length, 2);
});

test('S5: the private ranking lists every member by weekly XP and only members can read it', async () => {
  const db = await freshDatabase();
  const ana = await createUser(db, 'Ana');
  const bea = await createUser(db, 'Bea');
  const stranger = await createUser(db, 'Stranger');
  const [league] = (
    await db.query(
      `insert into public.leagues (name, owner_id, invite_code) values ('L', $1, 'L1') returning id`,
      [ana],
    )
  ).rows;
  await db.query(`insert into public.league_members (league_id, user_id) values ($1, $2), ($1, $3)`, [
    league.id,
    ana,
    bea,
  ]);
  // A long drive with a mediocre score earns nothing: km never buy XP (S4).
  await addDrive(db, bea, { km: 300, score: 70 });
  await addDrive(db, ana, { km: 3, score: 95 });

  const week = await weekStart(db);
  const rows = await asUser(db, bea, `select * from public.league_weekly_ranking($1, $2)`, [
    league.id,
    week,
  ]);
  assert.deepEqual(
    rows.map((r) => [Number(r.rank), r.display_name, Number(r.week_xp)]),
    [
      [1, 'Ana', 20],
      [2, 'Bea', 0],
    ],
  );

  const leaked = await asUser(db, stranger, `select * from public.league_weekly_ranking($1, $2)`, [
    league.id,
    week,
  ]);
  assert.equal(leaked.length, 0);
});

test('S4: XP comes from drive quality, lessons, quests and habit levels, with daily caps', async () => {
  const db = await freshDatabase();
  const user = await createUser(db, 'Driver');
  const other = await createUser(db, 'Other');

  await addDrive(db, user, { km: 1.5, score: 99 }); // too short: 0
  await addDrive(db, user, { km: 5, score: 80 }); // 10
  for (let i = 0; i < 4; i += 1) await addDrive(db, user, { km: 5, score: 95 }); // best 3 of the day count
  await addDrive(db, user, { km: 5, score: 95, daysAgo: 8 }); // last week: lifetime only

  const today = (await db.query(`select (now() at time zone 'Europe/Madrid')::date::text as d`)).rows[0].d;
  await asUser(db, user, `insert into public.lesson_completions (day, correct, total) values ($1, 4, 5)`, [
    today,
  ]);
  for (const quest of ['clean_drive', 'no_phone', 'lesson', 'connected']) {
    await asUser(db, user, `insert into public.quest_completions (day, quest_id) values ($1, $2)`, [
      today,
      quest,
    ]);
  }
  await asUser(db, user, `insert into public.habit_levels (unit, level) values ('smooth_braking', 1)`);

  const [xp] = await asUser(db, user, `select * from public.my_xp($1)`, [await weekStart(db)]);
  // 3 x 20 (drives) + 10 (lesson) + 3 x 15 (quests) + 50 (level) = 165 this week.
  assert.equal(Number(xp.week_xp), 165);
  assert.equal(Number(xp.total_xp), 185);

  const [otherXP] = await asUser(db, other, `select * from public.my_xp($1)`, [await weekStart(db)]);
  assert.equal(Number(otherXP.total_xp), 0);
});

test('S1-S8: progress rows are private to their owner and cannot be forged for someone else', async () => {
  const db = await freshDatabase();
  const owner = await createUser(db, 'Owner');
  const other = await createUser(db, 'Other');
  const today = (await db.query(`select public.madrid_today()::text as d`)).rows[0].d;
  await asUser(db, owner, `insert into public.lesson_completions (day, correct, total) values ($1, 5, 5)`, [today]);
  await asUser(db, owner, `insert into public.streak_repairs (day) values ($1::date - 1)`, [today]);

  assert.equal((await asUser(db, other, `select * from public.lesson_completions`)).length, 0);
  assert.equal((await asUser(db, other, `select * from public.streak_repairs`)).length, 0);
  assert.equal((await asUser(db, other, `select * from public.xp_ledger`)).length, 0);
  await assert.rejects(
    asUser(db, other, `insert into public.lesson_completions (user_id, day, correct, total) values ($1, $2, 1, 5)`, [
      owner,
      today,
    ]),
    /row-level security/,
  );
  await assert.rejects(
    asUser(db, owner, `insert into public.lesson_completions (day, correct, total) values ($1::date - 1, 6, 5)`, [today]),
    /check constraint/,
  );
});

test('S5: public leagues need opt-in, fill groups of 30 and keep divisions out of client reach', async () => {
  const db = await freshDatabase();
  const users = [];
  for (let i = 0; i < 31; i += 1) users.push(await createUser(db, `P${i}`));

  await assert.rejects(asUser(db, users[0], `select * from public.public_league_current()`), /not_opted_in/);

  const groups = new Set();
  for (const user of users) {
    await asUser(db, user, `select public.set_public_league_opt_in(true)`);
    const [current] = await asUser(db, user, `select * from public.public_league_current()`);
    assert.equal(current.division, 1);
    assert.equal(current.last_change, 0);
    groups.add(current.group_id);
  }
  assert.equal(groups.size, 2);

  // A second call returns the same group, it does not join twice.
  const [again] = await asUser(db, users[0], `select * from public.public_league_current()`);
  const memberships = (await db.query(`select group_id from public.public_league_members where user_id = $1`, [users[0]])).rows;
  assert.equal(memberships.length, 1);
  assert.equal(again.group_id, memberships[0].group_id);

  const ranking = await asUser(db, users[0], `select * from public.public_league_ranking()`);
  assert.equal(ranking.length, 30);

  // No direct writes: divisions only move through the weekly settlement.
  await asUser(db, users[0], `update public.public_league_entries set division = 5`);
  const [entry] = (await db.query(`select division from public.public_league_entries where user_id = $1`, [users[0]])).rows;
  assert.equal(entry.division, 1);
  await assert.rejects(
    asUser(db, users[0], `insert into public.public_league_members (week_start, user_id, group_id) values ('2026-10-26', $1, $2)`, [
      users[0],
      again.group_id,
    ]),
    /row-level security|permission denied/,
  );

  // Opting out leaves this week's group.
  await asUser(db, users[0], `select public.set_public_league_opt_in(false)`);
  assert.equal((await asUser(db, users[1], `select * from public.public_league_ranking()`)).length, 29);
  await assert.rejects(asUser(db, users[0], `select * from public.public_league_current()`), /not_opted_in/);
});

test('S5: the first call of a new week settles last week once: top 7 up, bottom 5 down', async () => {
  const db = await freshDatabase();
  const lastWeek = (await db.query(`select (public.madrid_week_start() - 7)::text as w`)).rows[0].w;
  const [group] = (
    await db.query(`insert into public.public_league_groups (week_start, division) values ($1, 2) returning id`, [lastWeek])
  ).rows;

  // 12 players in Plata last week; player i drove i clean drives (one per day,
  // up to 3 per day), so the order is fixed: P11 first, P0 last.
  const players = [];
  for (let i = 0; i < 12; i += 1) {
    const user = await createUser(db, `P${i}`);
    players.push(user);
    await db.query(`insert into public.public_league_entries (user_id, division) values ($1, 2)`, [user]);
    await db.query(`insert into public.public_league_members (week_start, user_id, group_id) values ($1, $2, $3)`, [
      lastWeek,
      user,
      group.id,
    ]);
    for (let d = 0; d < i; d += 1) {
      await db.query(
        `insert into public.drives (user_id, started_at, ended_at, distance_km, duration_s, score)
         values ($1, ($2::date + $3::int + time '12:00') at time zone 'Europe/Madrid',
                     ($2::date + $3::int + time '12:30') at time zone 'Europe/Madrid', 10, 1800, 95)`,
        [user, lastWeek, d % 7],
      );
    }
  }

  const result = async (user) => (await asUser(db, user, `select * from public.public_league_current()`))[0];

  const top = await result(players[11]);
  assert.equal(top.division, 3);
  assert.equal(top.last_change, 1);

  // 7th place still promotes; with 12 players the bottom 5 are places 8-12.
  const seventh = await result(players[5]);
  assert.equal(seventh.division, 3);
  const eighth = await result(players[4]);
  assert.equal(eighth.division, 1);
  assert.equal(eighth.last_change, -1);
  const last = await result(players[0]);
  assert.equal(last.division, 1);

  // Players who stay keep their division and a 0 change.
  const db2 = await freshDatabase();
  const week2 = (await db2.query(`select (public.madrid_week_start() - 7)::text as w`)).rows[0].w;
  const [g2] = (await db2.query(`insert into public.public_league_groups (week_start, division) values ($1, 4) returning id`, [week2])).rows;
  const loner = await createUser(db2, 'Loner');
  await db2.query(`insert into public.public_league_entries (user_id, division) values ($1, 4)`, [loner]);
  await db2.query(`insert into public.public_league_members (week_start, user_id, group_id) values ($1, $2, $3)`, [week2, loner, g2.id]);
  const [stayed] = await asUser(db2, loner, `select * from public.public_league_current()`);
  assert.equal(stayed.division, 4);
  assert.equal(stayed.last_change, 0);

  // Settled once: calling again this week changes nothing.
  const twice = await result(players[11]);
  assert.equal(twice.division, 3);
  assert.equal(twice.group_id, top.group_id);
});

// ---------------------------------------------------------------------------
// odd/tasks/security-hardening.md
// ---------------------------------------------------------------------------

test('security S2: sign-up seeds a pseudonym, never the Apple name, and only the name is editable', async () => {
  const db = await freshDatabase();
  const id = uuid();
  await db.query(`insert into auth.users (id, raw_user_meta_data) values ($1, $2)`, [
    id,
    { full_name: 'Ana García López' },
  ]);
  const [profile] = await asUser(db, id, `select display_name from public.profiles where id = $1`, [id]);
  assert.match(profile.display_name, /^Conductor \d{4}$/);

  await asUser(db, id, `update public.profiles set display_name = 'Ana' where id = $1`, [id]);
  const [renamed] = await asUser(db, id, `select display_name from public.profiles where id = $1`, [id]);
  assert.equal(renamed.display_name, 'Ana');

  await assert.rejects(
    asUser(db, id, `update public.profiles set avatar_url = 'x' where id = $1`, [id]),
    /permission denied/,
  );
  for (const bad of ['   ', 'x'.repeat(31)]) {
    await assert.rejects(
      asUser(db, id, `update public.profiles set display_name = $2 where id = $1`, [id, bad]),
      /check constraint/,
    );
  }
});

test('security S2: rankings mark the caller with is_me and never return uuids', async () => {
  const db = await freshDatabase();
  const ana = await createUser(db, 'Ana');
  const bea = await createUser(db, 'Bea');
  const [league] = await asUser(db, ana, `select * from public.create_league('L')`);
  await asUser(db, bea, `select public.join_league_by_code($1)`, [league.invite_code]);

  const privateRows = await asUser(db, bea, `select * from public.league_weekly_ranking($1, $2)`, [
    league.id,
    await weekStart(db),
  ]);
  assert.deepEqual(Object.keys(privateRows[0]).sort(), ['display_name', 'is_me', 'rank', 'week_xp']);
  assert.deepEqual(
    privateRows.map((r) => [r.display_name, r.is_me]).sort(),
    [
      ['Ana', false],
      ['Bea', true],
    ],
  );

  for (const user of [ana, bea]) await asUser(db, user, `select public.set_public_league_opt_in(true)`);
  for (const user of [ana, bea]) await asUser(db, user, `select * from public.public_league_current()`);
  const publicRows = await asUser(db, ana, `select * from public.public_league_ranking()`);
  assert.deepEqual(Object.keys(publicRows[0]).sort(), ['display_name', 'is_me', 'place', 'week_xp', 'zone']);
  assert.deepEqual(publicRows.filter((r) => r.is_me).map((r) => r.display_name), ['Ana']);
});

test('security S3: leagues are created on the server with 8-symbol codes, never by direct insert', async () => {
  const db = await freshDatabase();
  const owner = await createUser(db, 'Owner');
  const [league] = await asUser(db, owner, `select * from public.create_league('  Amigos  ')`);
  assert.match(league.invite_code, /^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$/);
  assert.equal(league.name, 'Amigos');
  assert.equal(league.owner_id, owner);
  assert.equal((await asUser(db, owner, `select user_id from public.league_members`)).length, 1);

  await assert.rejects(
    asUser(db, owner, `insert into public.leagues (name, owner_id, invite_code) values ('X', $1, 'ZZZZZZZZ')`, [owner]),
    /row-level security/,
  );
});

test('security S3: bad codes fail alike and ten failures in an hour lock joining', async () => {
  const db = await freshDatabase();
  const owner = await createUser(db, 'Owner');
  const prober = await createUser(db, 'Prober');
  const [league] = await asUser(db, owner, `select * from public.create_league('L')`);

  for (let i = 0; i < 10; i += 1) {
    const [row] = await asUser(db, prober, `select public.join_league_by_code($1) as id`, [`NOPE${i}AAA`]);
    assert.equal(row.id, null);
  }
  assert.equal(
    (await db.query(`select count(*)::int as c from public.league_join_failures where user_id = $1`, [prober])).rows[0].c,
    10,
  );
  // Even the right code is refused once the budget is spent.
  await assert.rejects(
    asUser(db, prober, `select public.join_league_by_code($1)`, [league.invite_code]),
    /too_many_attempts/,
  );
  // Codes are case- and space-insensitive for a legitimate user.
  const friend = await createUser(db, 'Friend');
  const [joined] = await asUser(db, friend, `select public.join_league_by_code($1) as id`, [
    ` ${league.invite_code.toLowerCase()} `,
  ]);
  assert.equal(joined.id, league.id);
});

test('security S7: anon has no table or RPC access; authenticated cannot truncate', async () => {
  const db = await freshDatabase();
  const user = await createUser(db, 'Ana');
  for (const table of ['profiles', 'drives', 'daily_scores', 'leagues', 'lesson_completions', 'public_league_entries']) {
    await assert.rejects(asAnon(db, `select * from public.${table}`), /permission denied/, table);
  }
  for (const rpc of ["create_league('x')", "join_league_by_code('x')", 'madrid_today()']) {
    await assert.rejects(asAnon(db, `select public.${rpc}`), /permission denied/, rpc);
  }
  await assert.rejects(asUser(db, user, `truncate public.drives`), /permission denied/);
});
