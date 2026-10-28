// Adversarial probes for migration 20261028084225_0002_duolingo_loop.sql (T1 of
// odd/tasks/duolingo-loop.md). Independent verification: RLS holes, security
// definer hygiene, XP ledger boundaries (S4) and public-league settlement (S5).
//

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

async function weekStart(db) {
  return (await db.query(`select public.madrid_week_start()::text as w`)).rows[0].w;
}

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

async function addDriveAt(db, userID, { km, score, startISO }) {
  await db.query(
    `insert into public.drives (user_id, started_at, ended_at, distance_km, duration_s, score)
     values ($1, $2::timestamptz, $2::timestamptz + interval '30 minutes', $3, 1800, $4)`,
    [userID, startISO, km, score],
  );
}

async function addDriveInWeek(db, userID, { weekStart, dayOffset, km = 10, score = 95 }) {
  await db.query(
    `insert into public.drives (user_id, started_at, ended_at, distance_km, duration_s, score)
     values ($1, ($2::date + $3::int + time '12:00') at time zone 'Europe/Madrid',
                 ($2::date + $3::int + time '12:30') at time zone 'Europe/Madrid', $4, 1800, $5)`,
    [userID, weekStart, dayOffset, km, score],
  );
}

// Builds one settled week: `players` members of a group of `division` whose
// week is `weekStart`; player i gets `drives[i]` clean drives on distinct days,
// so XP (and therefore place) is deterministic.
async function seedWeek(db, { weekStart: week, division, drives }) {
  const [group] = (
    await db.query(
      `insert into public.public_league_groups (week_start, division) values ($1, $2) returning id`,
      [week, division],
    )
  ).rows;
  const users = [];
  for (let i = 0; i < drives.length; i += 1) {
    const user = await createUser(db, `U${i}`);
    users.push(user);
    await db.query(
      `insert into public.public_league_entries (user_id, division) values ($1, $2)`,
      [user, division],
    );
    await db.query(
      `insert into public.public_league_members (week_start, user_id, group_id, joined_at)
       values ($1, $2, $3, $4::timestamptz)`,
      [week, user, group.id, `2026-01-01T00:00:${String(i).padStart(2, '0')}Z`],
    );
    for (let d = 0; d < drives[i]; d += 1) {
      await addDriveInWeek(db, user, { weekStart: week, dayOffset: d % 7, score: 95 });
    }
  }
  return { group, users };
}

async function standings(db, groupID) {
  return (
    await db.query(`select place, user_id, week_xp, zone from public.public_league_standings($1)`, [
      groupID,
    ])
  ).rows;
}

// ---------------------------------------------------------------------------
// Security posture: definer hygiene, grants, anon reach, RLS on the new tables
// ---------------------------------------------------------------------------

test('probe: definer functions pin search_path and no data RPC is open to anon', async () => {
  const db = await freshDatabase();
  const rows = (
    await db.query(`
      select p.proname,
             p.prosecdef,
             coalesce(array_to_string(p.proconfig, ','), '') as config,
             has_function_privilege('anon', p.oid, 'execute') as anon_exec,
             has_function_privilege('authenticated', p.oid, 'execute') as auth_exec
        from pg_proc p
       where p.pronamespace = 'public'::regnamespace
         and p.proname in ('madrid_week_start', 'my_league_ids', 'my_xp',
                           'league_weekly_ranking', 'public_league_standings',
                           'set_public_league_opt_in', 'public_league_current',
                           'public_league_ranking', 'join_league_by_code')
       order by 1`)
  ).rows;

  assert.equal(rows.length, 9, 'every public API function exists exactly once');

  for (const row of rows) {
    if (row.prosecdef) {
      assert.match(
        row.config,
        /search_path=/,
        `${row.proname} is SECURITY DEFINER without a pinned search_path`,
      );
    }
  }

  // anon gets nothing that reads or writes user data.
  for (const name of [
    'my_league_ids',
    'my_xp',
    'league_weekly_ranking',
    'public_league_standings',
    'set_public_league_opt_in',
    'public_league_current',
    'public_league_ranking',
  ]) {
    assert.equal(rows.find((r) => r.proname === name).anon_exec, false, `${name} reachable by anon`);
  }

  // authenticated gets the client-facing RPCs but never the internal helper.
  for (const name of [
    'my_xp',
    'league_weekly_ranking',
    'set_public_league_opt_in',
    'public_league_current',
    'public_league_ranking',
  ]) {
    assert.equal(
      rows.find((r) => r.proname === name).auth_exec,
      true,
      `${name} not executable by authenticated`,
    );
  }
  assert.equal(
    rows.find((r) => r.proname === 'public_league_standings').auth_exec,
    false,
    'internal standings helper is reachable by clients',
  );
});

test('probe: anon cannot read ledgers nor call any RPC', async () => {
  const db = await freshDatabase();
  const user = await createUser(db, 'Ana');
  await addDrive(db, user, { km: 5, score: 95 });

  // S7 of security-hardening: anon holds no grant at all, not just no rows.
  await assert.rejects(asAnon(db, `select * from public.xp_ledger`), /permission denied/);
  await assert.rejects(asAnon(db, `select * from public.drives`), /permission denied/);

  await assert.rejects(
    asAnon(db, `select * from public.my_xp(current_date)`),
    /permission denied/,
  );
  await assert.rejects(
    asAnon(db, `select * from public.public_league_current()`),
    /permission denied/,
  );
  await assert.rejects(
    asAnon(db, `select * from public.public_league_ranking()`),
    /permission denied/,
  );
  await assert.rejects(
    asAnon(db, `select * from public.league_weekly_ranking(gen_random_uuid(), current_date)`),
    /permission denied/,
  );
  await assert.rejects(
    asAnon(db, `select * from public.public_league_standings(gen_random_uuid())`),
    /permission denied/,
  );
});

test('probe: public league tables are invisible and not writable by clients', async () => {
  const db = await freshDatabase();
  const user = await createUser(db, 'Ana');
  const other = await createUser(db, 'Bea');

  await asUser(db, user, `select public.set_public_league_opt_in(true)`);
  const [current] = await asUser(db, user, `select * from public.public_league_current()`);
  assert.ok(current.group_id, 'placement returns the group id');

  // The raw league tables are server-only, even for their own rows.
  for (const table of ['public_league_groups', 'public_league_members']) {
    assert.equal(
      (await asUser(db, user, `select * from public.${table}`)).length,
      0,
      `${table} is readable by a client`,
    );
  }
  assert.equal(
    (await asUser(db, other, `select * from public.public_league_entries`)).length,
    0,
    'another user reads my entry',
  );
  assert.equal((await asUser(db, user, `select * from public.public_league_entries`)).length, 1);

  // No write policy anywhere: forging a division is impossible, and the row
  // survives a delete attempt untouched.
  await assert.rejects(
    asUser(db, user, `insert into public.public_league_entries (user_id, division) values ($1, 5)`, [
      user,
    ]),
    /row-level security/,
  );
  await asUser(db, user, `update public.public_league_entries set division = 5, last_change = 1`);
  await asUser(db, user, `delete from public.public_league_entries`);
  const [entry] = (
    await db.query(`select division, last_change from public.public_league_entries where user_id = $1`, [
      user,
    ])
  ).rows;
  assert.equal(entry.division, 1, 'client changed its own division');
  assert.equal(entry.last_change, 0);

  await assert.rejects(
    asUser(
      db,
      user,
      `insert into public.public_league_members (week_start, user_id, group_id) values (current_date, $1, $2)`,
      [user, current.group_id],
    ),
    /row-level security/,
  );
  await assert.rejects(
    asUser(db, user, `insert into public.public_league_groups (week_start, division) values (current_date, 5)`),
    /row-level security/,
  );
  // The internal standings helper is not callable by clients.
  await assert.rejects(
    asUser(db, user, `select * from public.public_league_standings($1)`, [current.group_id]),
    /permission denied/,
  );
});

test('probe: nobody forges progress or XP for another user', async () => {
  const db = await freshDatabase();
  const owner = await createUser(db, 'Owner');
  const other = await createUser(db, 'Other');

  const writes = [
    `insert into public.quest_completions (user_id, day, quest_id) values ($1, '2026-10-27', 'clean_drive')`,
    `insert into public.habit_levels (user_id, unit, level) values ($1, 'smooth_braking', 1)`,
    `insert into public.streak_repairs (user_id, day) values ($1, '2026-10-20')`,
    `insert into public.lesson_completions (user_id, day, correct, total) values ($1, '2026-10-27', 5, 5)`,
  ];
  for (const sql of writes) {
    await assert.rejects(asUser(db, other, sql, [owner]), /row-level security/);
  }

  // And nobody reads another user's progress.
  for (const table of ['lesson_completions', 'quest_completions', 'habit_levels', 'streak_repairs']) {
    assert.equal(
      (await asUser(db, other, `select * from public.${table}`)).length,
      0,
      `${table} readable by another user`,
    );
  }

  // The ledger aggregates over all four tables, and it is empty for a stranger.
  const [xp] = await asUser(db, other, `select * from public.my_xp($1)`, [await weekStart(db)]);
  assert.equal(Number(xp.total_xp), 0);
  assert.equal((await asUser(db, other, `select * from public.xp_ledger`)).length, 0);
});

// ---------------------------------------------------------------------------
// S4: the XP ledger
// ---------------------------------------------------------------------------

test('probe: XP boundaries are 2 km, 90 and 75, and km never scale', async () => {
  const short = await freshDatabase();
  // One user per band so the daily cap of three drives never interferes.
  const bands = [
    [{ km: 1.99, score: 100 }, 0], // too short: 0
    [{ km: 2, score: 95 }, 20], // 2 km is enough
    [{ km: 2, score: 90 }, 20], // 90 is enough
    [{ km: 2, score: 89 }, 10],
    [{ km: 2, score: 75 }, 10], // 75 is enough
    [{ km: 2, score: 74 }, 0],
  ];
  for (const [drive, expected] of bands) {
    const bandUser = await createUser(short, `Band${expected}_${drive.km}_${drive.score}`);
    await addDrive(short, bandUser, drive);
    const [bandXP] = await asUser(short, bandUser, `select * from public.my_xp($1)`, [
      await weekStart(short),
    ]);
    assert.equal(Number(bandXP.week_xp), expected, `${drive.km} km at score ${drive.score}`);
  }

  const long = await freshDatabase();
  const longUser = await createUser(long, 'Long');
  await addDrive(long, longUser, { km: 400, score: 95 });
  const [longXP] = await asUser(long, longUser, `select * from public.my_xp($1)`, [
    await weekStart(long),
  ]);
  assert.equal(Number(longXP.week_xp), 20, 'a 400 km drive pays like a 2 km one');

  const cap = await freshDatabase();
  const capUser = await createUser(cap, 'Cap');
  // Four drives with XP 20, 20, 10, 10: only the best three count (50, not 60
  // and not the first three by time).
  await addDrive(cap, capUser, { km: 5, score: 10 }); // 0, must be ignored
  await addDrive(cap, capUser, { km: 5, score: 95 }); // 20
  await addDrive(cap, capUser, { km: 5, score: 80 }); // 10
  await addDrive(cap, capUser, { km: 5, score: 96 }); // 20
  await addDrive(cap, capUser, { km: 5, score: 76 }); // 10
  const [capXP] = await asUser(cap, capUser, `select * from public.my_xp($1)`, [await weekStart(cap)]);
  assert.equal(Number(capXP.week_xp), 50, 'best three drives of the day');
});

test('probe: quests cap at three per day and lessons pay 10', async () => {
  const db = await freshDatabase();
  const user = await createUser(db, 'Quest');
  const today = (await db.query(`select (now() at time zone 'Europe/Madrid')::date::text as d`)).rows[0]
    .d;
  await asUser(db, user, `insert into public.lesson_completions (day, correct, total) values ($1, 0, 5)`, [
    today,
  ]);
  // Quest ids must be catalog keys (QuestCatalog.swift:44-96) and each one now
  // needs the drive that earns it (S3.4 of server-validation): one 5 km drive
  // with no events of any kind earns all five below. Score 40 pays no drive XP,
  // so the total stays lesson + three quests.
  await addDrive(db, user, { km: 5, score: 40 });
  for (const quest of [
    'no_events_drive',
    'no_phone_drive',
    'smooth_brakes',
    'smooth_start',
    'legal_speed',
  ]) {
    await asUser(db, user, `insert into public.quest_completions (day, quest_id) values ($1, $2)`, [
      today,
      quest,
    ]);
  }
  // A lesson is one per day: the primary key refuses a second one.
  await assert.rejects(
    asUser(db, user, `insert into public.lesson_completions (day, correct, total) values ($1, 5, 5)`, [
      today,
    ]),
    /duplicate key/,
  );
  const [xp] = await asUser(db, user, `select * from public.my_xp($1)`, [await weekStart(db)]);
  assert.equal(Number(xp.week_xp), 10 + 45, 'lesson 10 XP + three quests at 15 XP');
});

test('probe: XP days and weeks are Europe/Madrid days', async () => {
  const db = await freshDatabase();
  const user = await createUser(db, 'TZ');
  // Sunday 23:30 Madrid closes the week that starts 2025-12-29.
  await addDriveAt(db, user, { km: 5, score: 95, startISO: '2026-01-04T23:30:00+01:00' });
  // Monday 00:30 Madrid opens the week that starts 2026-01-05.
  await addDriveAt(db, user, { km: 5, score: 95, startISO: '2026-01-05T00:30:00+01:00' });
  // Monday 00:00 Madrid opens the week that starts 2026-01-12.
  await addDriveAt(db, user, { km: 5, score: 95, startISO: '2026-01-12T00:00:00+01:00' });

  const week = async (start) =>
    (await asUser(db, user, `select * from public.my_xp($1)`, [start]))[0];
  assert.equal(Number((await week('2025-12-29')).week_xp), 20, 'Sunday night stays in its week');
  assert.equal(Number((await week('2026-01-05')).week_xp), 20, 'Monday 00:30 opens the new week');
  assert.equal(Number((await week('2026-01-12')).week_xp), 20, 'the week window is [start, start+7)');
  assert.equal(Number((await week('2026-01-05')).total_xp), 60);

  const [wk] = (
    await db.query(
      `select public.madrid_week_start('2026-01-08T23:30:00+01:00'::timestamptz)::text as mid,
              public.madrid_week_start('2026-01-04T23:30:00+01:00'::timestamptz)::text as sun,
              public.madrid_week_start('2026-01-05T00:30:00+01:00'::timestamptz)::text as mon`,
    )
  ).rows;
  assert.equal(wk.mid, '2026-01-05');
  assert.equal(wk.sun, '2025-12-29');
  assert.equal(wk.mon, '2026-01-05');
});

// ---------------------------------------------------------------------------
// S5: settlement, zones and the 30 cap
// ---------------------------------------------------------------------------

test('probe: Diamante never promotes and Bronce never demotes', async () => {
  const db = await freshDatabase();
  const lastWeek = (await db.query(`select (public.madrid_week_start() - 7)::text as w`)).rows[0].w;

  const diamond = await seedWeek(db, {
    weekStart: lastWeek,
    division: 5,
    drives: [12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1],
  });
  const dZones = (await standings(db, diamond.group.id)).map((r) => r.zone);
  assert.deepEqual(dZones.slice(0, 7), [null, null, null, null, null, null, null], 'Diamante promotes');
  assert.deepEqual(
    dZones.slice(7),
    ['demotion', 'demotion', 'demotion', 'demotion', 'demotion'],
    'the bottom five still drop out of Diamante',
  );

  const bronze = await seedWeek(db, {
    weekStart: lastWeek,
    division: 1,
    drives: [12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1],
  });
  const bZones = (await standings(db, bronze.group.id)).map((r) => r.zone);
  assert.deepEqual(
    bZones.slice(0, 7),
    Array(7).fill('promotion'),
    'the top seven leave Bronce',
  );
  assert.deepEqual(bZones.slice(7), [null, null, null, null, null], 'Bronce demotes');

  // And the settlement honours it: the Diamante leader keeps division 5.
  const [leader] = await asUser(db, diamond.users[0], `select * from public.public_league_current()`);
  assert.equal(leader.division, 5, 'a Diamante first place was promoted out of the range');
  assert.equal(leader.last_change, 0);
});

test('probe: 31 players in one division never exceed groups of 30', async () => {
  const db = await freshDatabase();
  const users = [];
  for (let i = 0; i < 31; i += 1) {
    const user = await createUser(db, `D${i}`);
    users.push(user);
    // Pre-place everyone in Plata (division 2) so the cap is exercised there.
    await db.query(`insert into public.public_league_entries (user_id, division) values ($1, 2)`, [
      user,
    ]);
  }
  for (const user of users) await asUser(db, user, `select * from public.public_league_current()`);

  const sizes = (
    await db.query(
      `select g.week_start, g.division, count(m.user_id)::int as members
         from public.public_league_groups g
         join public.public_league_members m on m.group_id = g.id
        group by 1, 2, g.id
        order by members desc`,
    )
  ).rows;
  assert.deepEqual(sizes.map((s) => s.members), [30, 1], 'groups of at most 30 in one division');
  assert.equal(new Set(sizes.map((s) => s.division)).size, 1);
  assert.equal(sizes[0].division, 2, 'placement respects the stored division');

  // Every client sees exactly its own group and never the other one.
  const [a] = await asUser(db, users[0], `select * from public.public_league_current()`);
  const [b] = await asUser(db, users[30], `select * from public.public_league_current()`);
  assert.notEqual(a.group_id, b.group_id);
  assert.equal(
    (await asUser(db, users[30], `select * from public.public_league_ranking()`)).length,
    1,
    'the loner sees only its own group',
  );
});

test('probe: settlement is once per week, across several missed weeks', async () => {
  const db = await freshDatabase();
  const weekOf = async (offset) =>
    (await db.query(`select (public.madrid_week_start() - $1::int)::text as w`, [offset])).rows[0].w;
  const thisWeek = await weekOf(0);
  const lastWeek = await weekOf(7);
  const twoWeeksAgo = await weekOf(14);

  const user = await createUser(db, 'Climber');
  const rival = await createUser(db, 'Rival');
  const { group: oldGroup } = await seedWeek(db, { weekStart: twoWeeksAgo, division: 2, drives: [] });
  // Make the climber the winner of that older week and the rival second.
  for (const [u, drives] of [[user, 3], [rival, 1]]) {
    await db.query(
      `insert into public.public_league_entries (user_id, division) values ($1, 2) on conflict (user_id) do nothing`,
      [u],
    );
    await db.query(
      `insert into public.public_league_members (week_start, user_id, group_id) values ($1, $2, $3)`,
      [twoWeeksAgo, u, oldGroup.id],
    );
    for (let d = 0; d < drives; d += 1) {
      await addDriveInWeek(db, u, { weekStart: twoWeeksAgo, dayOffset: d, score: 95 });
    }
  }
  await db.query(`delete from public.public_league_members where group_id = $1 and user_id not in ($2, $3)`, [
    oldGroup.id,
    user,
    rival,
  ]);

  // Week 1 of play: settle twoWeeksAgo, promote to Plata->Oro, join this week.
  const [first] = await asUser(db, user, `select * from public.public_league_current()`);
  assert.equal(first.division, 3, 'the winner was promoted');
  assert.equal(first.last_change, 1);
  const [afterFirst] = (
    await db.query(`select settled_week::text as s from public.public_league_entries where user_id = $1`, [
      user,
    ])
  ).rows;
  assert.equal(afterFirst.s, twoWeeksAgo, 'settled_week records the settled week');

  // Emulate the following week's rollover: the user played lastWeek in a Oro
  // group and won again, then never asked for this week yet.
  const { group: oroGroup } = await seedWeek(db, { weekStart: lastWeek, division: 3, drives: [] });
  await db.query(`delete from public.public_league_members where week_start = $1 and user_id = $2`, [
    thisWeek,
    user,
  ]);
  await db.query(`delete from public.public_league_members where group_id = $1`, [oroGroup.id]);
  await db.query(
    `insert into public.public_league_members (week_start, user_id, group_id) values ($1, $2, $3)`,
    [lastWeek, user, oroGroup.id],
  );
  for (let d = 0; d < 4; d += 1) {
    await addDriveInWeek(db, user, { weekStart: lastWeek, dayOffset: d, score: 96 });
  }

  const [second] = await asUser(db, user, `select * from public.public_league_current()`);
  assert.equal(second.division, 4, 'a second week settles again');
  assert.equal(second.last_change, 1);

  // Calling again this week must not settle twice.
  const [third] = await asUser(db, user, `select * from public.public_league_current()`);
  assert.equal(third.division, 4, 'the same week settled twice');
  assert.equal(third.group_id, second.group_id);
  const [afterSecond] = (
    await db.query(`select settled_week::text as s from public.public_league_entries where user_id = $1`, [
      user,
    ])
  ).rows;
  assert.equal(afterSecond.s, lastWeek);
});

test('probe: opting out removes the player from the group and opting back in replaces it', async () => {
  const db = await freshDatabase();
  const users = [await createUser(db, 'A'), await createUser(db, 'B'), await createUser(db, 'C')];
  for (const user of users) {
    await asUser(db, user, `select public.set_public_league_opt_in(true)`);
    await asUser(db, user, `select * from public.public_league_current()`);
  }
  assert.equal((await asUser(db, users[0], `select * from public.public_league_ranking()`)).length, 3);

  await asUser(db, users[0], `select public.set_public_league_opt_in(false)`);
  assert.equal(
    (await asUser(db, users[1], `select * from public.public_league_ranking()`)).length,
    2,
    'an opted-out player stays in the standings',
  );
  assert.equal(
    (await asUser(db, users[0], `select * from public.public_league_ranking()`)).length,
    0,
    'an opted-out player still reads the group',
  );

  // Opting back in in the same week places the player again, in one group only.
  await asUser(db, users[0], `select public.set_public_league_opt_in(true)`);
  await asUser(db, users[0], `select * from public.public_league_current()`);
  assert.equal((await asUser(db, users[0], `select * from public.public_league_ranking()`)).length, 3);
  const rows = (
    await db.query(`select count(*)::int as n from public.public_league_members where user_id = $1`, [
      users[0],
    ])
  ).rows;
  assert.equal(rows[0].n, 1, 'one membership row per week');
});

// ---------------------------------------------------------------------------
// S5: zones the spec does not spell out (documented behaviour, decide in T7)
// ---------------------------------------------------------------------------

test('probe: a small group promotes fewer than seven and demotes fewer than five', async () => {
  const db = await freshDatabase();
  const lastWeek = (await db.query(`select (public.madrid_week_start() - 7)::text as w`)).rows[0].w;

  // Ten players, everybody scored: S5 says the bottom five go down.
  const full = await seedWeek(db, {
    weekStart: lastWeek,
    division: 2,
    drives: [10, 9, 8, 7, 6, 5, 4, 3, 2, 1],
  });
  const zones = (await standings(db, full.group.id)).map((r) => r.zone);
  assert.equal(zones.filter((z) => z === 'promotion').length, 7);
  assert.equal(
    zones.filter((z) => z === 'demotion').length,
    3,
    'S5 says the bottom five demote; a group of ten only demotes three',
  );

  // Ten players but only three scored: places 4-7 are ranked but not promoted.
  const quiet = await seedWeek(db, {
    weekStart: lastWeek,
    division: 2,
    drives: [3, 2, 1, 0, 0, 0, 0, 0, 0, 0],
  });
  const quietZones = (await standings(db, quiet.group.id)).map((r) => r.zone);
  assert.deepEqual(
    quietZones.slice(0, 7),
    ['promotion', 'promotion', 'promotion', null, null, null, null],
    'zero XP does not promote even inside the top seven',
  );
});

// ---------------------------------------------------------------------------
// S8 and S2 gaps that live in the app, pinned so a later task changes them on
// purpose: the migration stores these facts and forbids editing them.
// ---------------------------------------------------------------------------

test('probe: progress days are bounded to today and yesterday, repairs to 3 days', async () => {
  const db = await freshDatabase();
  const user = await createUser(db, 'Premium');
  const today = (await db.query(`select public.madrid_today()::text as d`)).rows[0].d;

  // A client cannot back- or pre-fill a week of lessons or quests.
  await asUser(db, user, `insert into public.lesson_completions (day, correct, total) values ($1::date - 1, 5, 5)`, [today]);
  await asUser(db, user, `insert into public.lesson_completions (day, correct, total) values ($1, 5, 5)`, [today]);
  for (const offset of [-2, 1]) {
    await assert.rejects(
      asUser(db, user, `insert into public.lesson_completions (day, correct, total) values ($1::date + $2::int, 5, 5)`, [
        today,
        offset,
      ]),
      /check constraint/,
    );
    await assert.rejects(
      asUser(db, user, `insert into public.quest_completions (day, quest_id) values ($1::date + $2::int, 'lesson')`, [
        today,
        offset,
      ]),
      /check constraint/,
    );
  }

  // S8: only a recent day can be forgiven.
  await asUser(db, user, `insert into public.streak_repairs (day) values ($1::date - 3)`, [today]);
  await assert.rejects(
    asUser(db, user, `insert into public.streak_repairs (day) values ($1::date - 4)`, [today]),
    /check constraint/,
  );

  // Nothing in the app can edit or delete a stored fact.
  await asUser(db, user, `update public.streak_repairs set day = day`);
  await asUser(db, user, `delete from public.streak_repairs`);
  assert.equal(
    (await asUser(db, user, `select * from public.streak_repairs`)).length,
    1,
    'a client edited or deleted progress rows',
  );
});

test('probe: league_weekly_ranking is XP-only and has a single overload', async () => {
  const db = await freshDatabase();
  const defs = (
    await db.query(`
      select p.proname, pg_get_function_result(p.oid) as result
        from pg_proc p
       where p.pronamespace = 'public'::regnamespace
         and p.proname = 'league_weekly_ranking'`)
  ).rows;
  assert.equal(defs.length, 1, 'stale overload of league_weekly_ranking left behind');
  assert.match(defs[0].result, /week_xp/);
  assert.doesNotMatch(defs[0].result, /avg_score|total_km/, 'old score+km columns are gone');

  // No migration object still mentions the old columns.
  const leftover = (
    await db.query(`
      select count(*)::int as n
        from pg_proc p
       where p.pronamespace = 'public'::regnamespace
         and pg_get_functiondef(p.oid) ~ '(avg_score|total_km)'`)
  ).rows;
  assert.equal(leftover[0].n, 0, 'a function still returns the old ranking columns');

  // A member of no league cannot read a league ranking, and a member sees all.
  const ana = await createUser(db, 'Ana');
  const outsider = await createUser(db, 'Outsider');
  const [league] = (
    await db.query(
      `insert into public.leagues (name, owner_id, invite_code) values ('L', $1, 'CODE01') returning id`,
      [ana],
    )
  ).rows;
  await db.query(`insert into public.league_members (league_id, user_id) values ($1, $2)`, [
    league.id,
    ana,
  ]);
  const week = await weekStart(db);
  assert.equal(
    (await asUser(db, outsider, `select * from public.league_weekly_ranking($1, $2)`, [league.id, week]))
      .length,
    0,
  );
  assert.equal(
    (await asUser(db, ana, `select * from public.league_weekly_ranking($1, $2)`, [league.id, week]))
      .length,
    1,
  );
});

test('probe: the weekly window is the ISO week of p_week_start', async () => {
  const db = await freshDatabase();
  const ana = await createUser(db, 'Ana');
  const [league] = (
    await db.query(
      `insert into public.leagues (name, owner_id, invite_code) values ('W', $1, 'CODE02') returning id`,
      [ana],
    )
  ).rows;
  await db.query(`insert into public.league_members (league_id, user_id) values ($1, $2)`, [
    league.id,
    ana,
  ]);
  // Monday 2026-01-05 and Wednesday 2026-01-07, both inside the same ISO week.
  await addDriveAt(db, ana, { km: 5, score: 95, startISO: '2026-01-05T12:00:00+01:00' });
  await addDriveAt(db, ana, { km: 5, score: 95, startISO: '2026-01-07T12:00:00+01:00' });

  const xpFor = async (start) =>
    Number(
      (await asUser(db, ana, `select * from public.league_weekly_ranking($1, $2)`, [league.id, start]))[0]
        .week_xp,
    );
  assert.equal(await xpFor('2026-01-05'), 40, 'a Monday sums the whole ISO week');
  assert.equal(await xpFor('2026-01-07'), 40, 'a mid-week date is rounded down to its Monday');
});

test('probe: a stranger cannot self-insert into a private league; join goes through the code', async () => {
  const db = await freshDatabase();
  const owner = await createUser(db, 'Owner');
  const [league] = await asUser(db, owner, `select * from public.create_league('L')`);
  for (let i = 0; i < 24; i += 1) {
    const member = await createUser(db, `M${i}`);
    await asUser(db, member, `select public.join_league_by_code($1)`, [league.invite_code]);
  }

  const intruder = await createUser(db, 'Intruder');
  await assert.rejects(
    asUser(db, intruder, `insert into public.league_members (league_id, user_id) values ($1, $2)`, [
      league.id,
      intruder,
    ]),
    /row-level security/,
  );
  // Full league: the same null answer as an unknown code.
  const [full] = await asUser(db, intruder, `select public.join_league_by_code($1) as id`, [league.invite_code]);
  assert.equal(full.id, null);
  assert.equal(
    (await db.query(`select count(*)::int as c from public.league_members where league_id = $1`, [league.id]))
      .rows[0].c,
    25,
  );
  assert.equal((await asUser(db, intruder, `select id from public.profiles`)).length, 1);
});
