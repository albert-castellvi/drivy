// Runs every migration on a fresh PGlite database with a minimal stand-in for
// Supabase's `auth` schema and roles, then checks the server-validation rules
// of odd/tasks/server-validation.md S3 through the same SQL the app calls.
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

// Inserts a drive as the client would (owner session). Offsets are in minutes
// relative to now for started_at; `elapsedMin` sizes ended_at, `durationS`
// overrides the stored duration. All fixtures are relative to `now()` because
// PGlite runs on the real clock.
async function addDrive(
  db,
  userID,
  {
    startOffsetMin = -30,
    elapsedMin = 30,
    durationS = null,
    km = 10,
    score = 95,
    harshBrakes = 0,
    harshAccelerations = 0,
    phoneUseEvents = 0,
    speedingEvents = 0,
    connectedMode = false,
    daysAgo = 0,
  } = {},
) {
  const duration = durationS ?? Math.round(elapsedMin * 60);
  // Inserted through the owner session, the way PostgREST does: the triggers
  // only judge the owner's own writes (RLS judges everyone else's).
  await asUser(
    db,
    userID,
    `insert into public.drives
       (user_id, started_at, ended_at, distance_km, duration_s, score,
        harsh_brakes, harsh_accelerations, phone_use_events, speeding_events, connected_mode)
     values ($1,
             now() + make_interval(mins => $2::int) - make_interval(days => $5::int),
             now() + make_interval(mins => $2::int + $3::int) - make_interval(days => $5::int),
             $4, $6, $7, $8, $9, $10, $11, $12)`,
    [
      userID,
      startOffsetMin,
      elapsedMin,
      km,
      daysAgo,
      duration,
      score,
      harshBrakes,
      harshAccelerations,
      phoneUseEvents,
      speedingEvents,
      connectedMode,
    ],
  );
}

// The client's daily_scores upsert (SupabaseDriveRepository.upload), with
// deliberately wrong client values so the trigger is the only thing that can
// produce the right ones.
async function upsertDailyScore(db, userID, day, { score, distanceKm, drivesCount }) {
  await asUser(
    db,
    userID,
    `insert into public.daily_scores (user_id, day, score, distance_km, drives_count)
     values ($1, $2, $3, $4, $5)
     on conflict (user_id, day) do update
       set score = excluded.score, distance_km = excluded.distance_km,
           drives_count = excluded.drives_count`,
    [userID, day, score, distanceKm, drivesCount],
  );
}

const madridToday = (db) =>
  db.query(`select (now() at time zone 'Europe/Madrid')::date::text as d`).then((r) => r.rows[0].d);

// ---------------------------------------------------------------------------
// S3.1 — drives: plausibility limits, the daily cap, and no client UPDATE
// ---------------------------------------------------------------------------

test('drives: a drive that starts in the future is rejected, a just-finished one is accepted', async () => {
  const db = await freshDatabase();
  const user = await createUser(db, 'Punctual');

  await assert.rejects(
    addDrive(db, user, { startOffsetMin: 6, elapsedMin: 1, km: 5 }),
    /drive_implausible/,
  );
  await addDrive(db, user, { startOffsetMin: 2, elapsedMin: 1, km: 2 }); // +2 min: inside tolerance
  assert.equal((await db.query(`select count(*)::int c from public.drives`)).rows[0].c, 1);
});

test('drives: a drive older than 30 days is rejected, one from 29 days ago is accepted', async () => {
  const db = await freshDatabase();
  const user = await createUser(db, 'LateUploader'); // D4: retries failed uploads days later

  await assert.rejects(
    addDrive(db, user, { startOffsetMin: -30, daysAgo: 31, km: 5 }),
    /drive_implausible/,
  );
  await addDrive(db, user, { startOffsetMin: -30, daysAgo: 29, km: 5 });
  assert.equal((await db.query(`select count(*)::int c from public.drives`)).rows[0].c, 1);
});

test('drives: duration_s must match ended_at - started_at within 120 s and stay under 24 h', async () => {
  const db = await freshDatabase();
  const user = await createUser(db, 'Timer');

  // 30 min elapsed, claimed 1800 + 300 s: outside the 120 s tolerance.
  await assert.rejects(
    addDrive(db, user, { startOffsetMin: -30, elapsedMin: 30, durationS: 2100, km: 5 }),
    /drive_implausible/,
  );
  // Inside the tolerance: 1800 + 100 s.
  await addDrive(db, user, { startOffsetMin: -30, elapsedMin: 30, durationS: 1900, km: 5 });
  // More than a day of driving is not a drive.
  await assert.rejects(
    addDrive(db, user, { startOffsetMin: -60, elapsedMin: 30, durationS: 86401, km: 5 }),
    /drive_implausible/,
  );
  // Exactly 24 h of driving is accepted (the duration matches the timestamps).
  await addDrive(db, user, { startOffsetMin: -1440, elapsedMin: 1440, durationS: 86400, km: 5 });
});

test('drives: an average speed above 250 km/h is rejected, 240 km/h is accepted', async () => {
  const db = await freshDatabase();
  const user = await createUser(db, 'Speeder');

  await assert.rejects(
    addDrive(db, user, { startOffsetMin: -60, elapsedMin: 60, km: 300 }),
    /drive_implausible/,
  );
  await addDrive(db, user, { startOffsetMin: -60, elapsedMin: 60, km: 240 });
});

test('drives: more than 50 drives per user per Madrid day are rejected', async () => {
  const db = await freshDatabase();
  const user = await createUser(db, 'Fleet');
  for (let i = 0; i < 50; i += 1) {
    await addDrive(db, user, { startOffsetMin: -(60 + i), elapsedMin: 1, km: 2 });
  }
  await assert.rejects(
    addDrive(db, user, { startOffsetMin: -(60 + 50), elapsedMin: 1, km: 2 }),
    /daily_drive_limit/,
  );
  // A different user can still insert 50 on the same day.
  const other = await createUser(db, 'FleetTwo');
  await addDrive(db, other, { startOffsetMin: -30, elapsedMin: 1, km: 2 });
});

test('drives: the owner can select, insert and delete but can no longer UPDATE a drive', async () => {
  const db = await freshDatabase();
  const user = await createUser(db, 'Owner');
  await addDrive(db, user, { km: 5, score: 95 });

  await asUser(db, user, `select * from public.drives`);

  // No UPDATE policy: default-deny hides the row from the scan, so the client
  // rewrite affects nothing instead of erroring (what PostgREST reports as a
  // 0-row PATCH).
  const rewritten = await asUser(
    db,
    user,
    `update public.drives set score = 100 where user_id = $1 returning score`,
    [user],
  );
  assert.equal(rewritten.length, 0);
  await assert.equal(
    (await db.query(`select score from public.drives where user_id = $1`, [user])).rows[0].score,
    95,
    'the client rewrote its score',
  );

  await asUser(db, user, `delete from public.drives where user_id = $1`, [user]);
  assert.equal((await db.query(`select count(*)::int c from public.drives`)).rows[0].c, 0);
});

// ---------------------------------------------------------------------------
// S3.2 — daily_scores: the trigger recomputes from drives, client values are
// ignored (distance-weighted average, SupabaseDriveRepository.swift:39-66 and
// DailyScoreCalculator.swift:23-42)
// ---------------------------------------------------------------------------

test('daily_scores: insert and update recompute score, distance and count, ignoring client values', async () => {
  const db = await freshDatabase();
  const user = await createUser(db, 'Aggregator');
  const today = await madridToday(db);

  await addDrive(db, user, { km: 3, score: 90 });
  await addDrive(db, user, { km: 1, score: 60 });

  // Client sends flattering values; the trigger must overwrite all three.
  await upsertDailyScore(db, user, today, { score: 100, distanceKm: 999, drivesCount: 42 });
  const [row] = await asUser(
    db,
    user,
    `select score, distance_km, drives_count from public.daily_scores where day = $1`,
    [today],
  );
  // (90*3 + 60*1) / 4 = 82.5 -> 83 (Swift .rounded(), half away from zero).
  assert.equal(row.score, 83);
  assert.equal(Number(row.distance_km), 4);
  assert.equal(row.drives_count, 2);

  // A later drive changes the aggregate on the client's next upsert.
  await addDrive(db, user, { km: 2, score: 40 });
  await upsertDailyScore(db, user, today, { score: 99, distanceKm: 1, drivesCount: 1 });
  const [after] = await asUser(
    db,
    user,
    `select score, distance_km, drives_count from public.daily_scores where day = $1`,
    [today],
  );
  // (90*3 + 60*1 + 40*2) / 6 = 68.33 -> 68.
  assert.equal(after.score, 68);
  assert.equal(Number(after.distance_km), 6);
  assert.equal(after.drives_count, 3);
});

test('daily_scores: a day whose drives have no distance falls back to the plain average', async () => {
  const db = await freshDatabase();
  const user = await createUser(db, 'ZeroKm');
  const today = await madridToday(db);

  await addDrive(db, user, { km: 0, score: 70 });
  await addDrive(db, user, { km: 0, score: 90 });
  await upsertDailyScore(db, user, today, { score: 100, distanceKm: 5, drivesCount: 9 });
  const [row] = await asUser(
    db,
    user,
    `select score, distance_km, drives_count from public.daily_scores where day = $1`,
    [today],
  );
  assert.equal(row.score, 80);
  assert.equal(Number(row.distance_km), 0);
  assert.equal(row.drives_count, 2);
});

test('daily_scores: each user only aggregates their own drives', async () => {
  const db = await freshDatabase();
  const user = await createUser(db, 'Mine');
  const other = await createUser(db, 'Theirs');
  const today = await madridToday(db);

  await addDrive(db, other, { km: 3, score: 90 });
  await upsertDailyScore(db, user, today, { score: 90, distanceKm: 3, drivesCount: 1 });
  const [row] = await asUser(
    db,
    user,
    `select score, distance_km, drives_count from public.daily_scores where day = $1`,
    [today],
  );
  // No drives of their own: nothing to average, everything is zeroed.
  assert.equal(row.score, 0);
  assert.equal(Number(row.distance_km), 0);
  assert.equal(row.drives_count, 0);
});

// ---------------------------------------------------------------------------
// S3.3 — habit_levels: window, level chain, unit chain and qualifying drives
// (predicates ported from HabitPathEngine.swift / HabitUnit.swift)
// ---------------------------------------------------------------------------

test('habit_levels: completed_at must be inside [now - 30 days, now + 5 min]', async () => {
  const db = await freshDatabase();
  const user = await createUser(db, 'Backdated');
  // Level 1 of the first unit needs 3 qualifying drives.
  for (let i = 0; i < 3; i += 1) {
    await addDrive(db, user, { startOffsetMin: -(60 + i), elapsedMin: 30, km: 5, daysAgo: 2 });
  }

  await assert.rejects(
    asUser(
      db,
      user,
      `insert into public.habit_levels (unit, level, completed_at)
       values ('smooth_braking', 1, now() - interval '31 days')`,
    ),
    /habit_level_unearned/,
  );
  await assert.rejects(
    asUser(
      db,
      user,
      `insert into public.habit_levels (unit, level, completed_at)
       values ('smooth_braking', 1, now() + interval '6 minutes')`,
    ),
    /habit_level_unearned/,
  );
  await asUser(
    db,
    user,
    `insert into public.habit_levels (unit, level, completed_at)
     values ('smooth_braking', 1, now() + interval '2 minutes')`,
  );
});

test('habit_levels: level L requires level L-1 of the same unit, and every level needs its drives', async () => {
  const db = await freshDatabase();
  const user = await createUser(db, 'Climber');

  // 2 qualifying drives (harsh_brakes = 0, >= 2 km): not enough even for level 1.
  for (let i = 0; i < 2; i += 1) {
    await addDrive(db, user, { startOffsetMin: -(60 + i), elapsedMin: 30, km: 5 });
  }
  await assert.rejects(
    asUser(db, user, `insert into public.habit_levels (unit, level) values ('smooth_braking', 1)`),
    /habit_level_unearned/,
  );
  // A drive with a harsh brake does not qualify (HabitUnit.swift:56).
  await addDrive(db, user, { startOffsetMin: -120, elapsedMin: 30, km: 5, harshBrakes: 1 });
  await addDrive(db, user, { startOffsetMin: -180, elapsedMin: 30, km: 1.5 }); // too short
  await assert.rejects(
    asUser(db, user, `insert into public.habit_levels (unit, level) values ('smooth_braking', 1)`),
    /habit_level_unearned/,
  );
  await addDrive(db, user, { startOffsetMin: -200, elapsedMin: 30, km: 5 });
  await asUser(db, user, `insert into public.habit_levels (unit, level) values ('smooth_braking', 1)`);

  // Level 2 is cumulative since the unit opened (HabitPathEngine.swift:27-28): 7 drives.
  await assert.rejects(
    asUser(db, user, `insert into public.habit_levels (unit, level) values ('smooth_braking', 2)`),
    /habit_level_unearned/,
  );
  for (let i = 0; i < 4; i += 1) {
    await addDrive(db, user, { startOffsetMin: -(300 + i), elapsedMin: 30, km: 5 });
  }
  // Recorded 10 minutes ago so a later drive can still start after it and stay
  // inside the 5-minute upload window.
  await asUser(
    db,
    user,
    `insert into public.habit_levels (unit, level, completed_at)
     values ('smooth_braking', 2, now() - interval '10 minutes')`,
  );

  // Drives that started after completed_at do not count (HabitPathEngine.swift:163-165).
  // 2 km in 1 min: qualifying, and inside the 250 km/h plausibility bound.
  await addDrive(db, user, { startOffsetMin: -5, elapsedMin: 1, km: 2 });
  await assert.rejects(
    asUser(db, user, `insert into public.habit_levels (unit, level) values ('smooth_braking', 3)`),
    /habit_level_unearned/,
  );
  for (let i = 0; i < 8; i += 1) {
    await addDrive(db, user, { startOffsetMin: -(410 + i), elapsedMin: 30, km: 5 });
  }
  await asUser(db, user, `insert into public.habit_levels (unit, level) values ('smooth_braking', 3)`);
});

test('habit_levels: a unit after the first needs level 3 of the previous unit and its own drives', async () => {
  const db = await freshDatabase();
  const user = await createUser(db, 'Skipper');

  // 7 qualifying drives (harsh_accelerations = 0): enough for levels 1 and 2 of unit 1.
  for (let i = 0; i < 7; i += 1) {
    await addDrive(db, user, { startOffsetMin: -(70 + i), elapsedMin: 30, km: 5 });
  }
  await asUser(db, user, `insert into public.habit_levels (unit, level) values ('smooth_braking', 1)`);
  await asUser(db, user, `insert into public.habit_levels (unit, level) values ('smooth_braking', 2)`);
  // Second unit without level 3 of the first: rejected even with enough drives.
  await assert.rejects(
    asUser(
      db,
      user,
      `insert into public.habit_levels (unit, level) values ('smooth_acceleration', 1)`,
    ),
    /habit_level_unearned/,
  );

  const full = await createUser(db, 'Chain');
  for (let i = 0; i < 15; i += 1) {
    await addDrive(db, full, { startOffsetMin: -(80 + i), elapsedMin: 30, km: 5 });
  }
  await asUser(db, full, `insert into public.habit_levels (unit, level) values ('smooth_braking', 1)`);
  await asUser(db, full, `insert into public.habit_levels (unit, level) values ('smooth_braking', 2)`);
  // Recorded in the past so unit 2 can open and count drives after it.
  await asUser(
    db,
    full,
    `insert into public.habit_levels (unit, level, completed_at)
     values ('smooth_braking', 3, now() - interval '10 minutes')`,
  );
  // The next unit opened at that completed_at (HabitPathEngine.swift:184):
  // 3 qualifying drives since then reach its level 1.
  for (const offset of [-8, -7, -6]) {
    await addDrive(db, full, { startOffsetMin: offset, elapsedMin: 1, km: 2 });
  }
  await asUser(
    db,
    full,
    `insert into public.habit_levels (unit, level) values ('smooth_acceleration', 1)`,
  );
});

// ---------------------------------------------------------------------------
// S3.4 — quest_completions: the exact predicates of QuestCatalog.swift
// ---------------------------------------------------------------------------

test('quests: clean_drive / perfect_drive / careful_drive need the exact score over 2 km', async () => {
  const db = await freshDatabase();
  const user = await createUser(db, 'Clean');
  const today = await madridToday(db);

  // 89 over 4 km: careful_drive yes, clean_drive no.
  await addDrive(db, user, { km: 4, score: 89 });
  await asUser(db, user, `insert into public.quest_completions (day, quest_id) values ($1, 'careful_drive')`, [today]);
  await assert.rejects(
    asUser(db, user, `insert into public.quest_completions (day, quest_id) values ($1, 'clean_drive')`, [today]),
    /quest_unearned/,
  );
  await addDrive(db, user, { startOffsetMin: -90, elapsedMin: 30, km: 4, score: 90 });
  await asUser(db, user, `insert into public.quest_completions (day, quest_id) values ($1, 'clean_drive')`, [today]);
  await assert.rejects(
    asUser(db, user, `insert into public.quest_completions (day, quest_id) values ($1, 'perfect_drive')`, [today]),
    /quest_unearned/,
  );
  await addDrive(db, user, { startOffsetMin: -150, elapsedMin: 30, km: 4, score: 95 });
  await asUser(db, user, `insert into public.quest_completions (day, quest_id) values ($1, 'perfect_drive')`, [today]);
});

test('quests: event-free quests read the exact event counters, connected reads the flag', async () => {
  const db = await freshDatabase();
  const user = await createUser(db, 'Events');
  const today = await madridToday(db);

  await addDrive(db, user, { km: 4, score: 80, phoneUseEvents: 1 });
  await assert.rejects(
    asUser(db, user, `insert into public.quest_completions (day, quest_id) values ($1, 'no_phone_drive')`, [today]),
    /quest_unearned/,
  );
  await assert.rejects(
    asUser(db, user, `insert into public.quest_completions (day, quest_id) values ($1, 'no_events_drive')`, [today]),
    /quest_unearned/,
  );
  await asUser(db, user, `insert into public.quest_completions (day, quest_id) values ($1, 'smooth_brakes')`, [today]);
  await asUser(db, user, `insert into public.quest_completions (day, quest_id) values ($1, 'smooth_start')`, [today]);
  await asUser(db, user, `insert into public.quest_completions (day, quest_id) values ($1, 'legal_speed')`, [today]);

  // One harsh brake takes smooth_brakes away.
  const braked = await createUser(db, 'Braked');
  await addDrive(db, braked, { km: 4, score: 80, harshBrakes: 1 });
  await assert.rejects(
    asUser(db, braked, `insert into public.quest_completions (day, quest_id) values ($1, 'smooth_brakes')`, [today]),
    /quest_unearned/,
  );

  const other = await createUser(db, 'Flag');
  await addDrive(db, other, { km: 4, score: 80, connectedMode: false });
  await assert.rejects(
    asUser(db, other, `insert into public.quest_completions (day, quest_id) values ($1, 'connected_drive')`, [today]),
    /quest_unearned/,
  );
  await addDrive(db, other, { startOffsetMin: -90, elapsedMin: 30, km: 4, score: 80, connectedMode: true });
  await asUser(db, other, `insert into public.quest_completions (day, quest_id) values ($1, 'connected_drive')`, [today]);
});

test('quests: the lesson quest needs that day lesson_completions row and nothing else', async () => {
  const db = await freshDatabase();
  const user = await createUser(db, 'Student');
  const today = await madridToday(db);

  await addDrive(db, user, { km: 4, score: 95 });
  await assert.rejects(
    asUser(db, user, `insert into public.quest_completions (day, quest_id) values ($1, 'lesson')`, [today]),
    /quest_unearned/,
  );
  await asUser(db, user, `insert into public.lesson_completions (day, correct, total) values ($1, 4, 5)`, [today]);
  await asUser(db, user, `insert into public.quest_completions (day, quest_id) values ($1, 'lesson')`, [today]);
});

test('quests: only drives of the quest Madrid day count, and only 2 km or longer', async () => {
  const db = await freshDatabase();
  const user = await createUser(db, 'Window');
  const today = await madridToday(db);

  // Qualifying drive yesterday does not earn today's quest.
  await addDrive(db, user, { km: 4, score: 95, daysAgo: 1 });
  await assert.rejects(
    asUser(db, user, `insert into public.quest_completions (day, quest_id) values ($1, 'clean_drive')`, [today]),
    /quest_unearned/,
  );
  // A 1.5 km drive never counts (QuestEvaluator.swift:40-42).
  await addDrive(db, user, { startOffsetMin: -90, elapsedMin: 30, km: 1.5, score: 95 });
  await assert.rejects(
    asUser(db, user, `insert into public.quest_completions (day, quest_id) values ($1, 'clean_drive')`, [today]),
    /quest_unearned/,
  );
  await addDrive(db, user, { startOffsetMin: -150, elapsedMin: 30, km: 2, score: 95 });
  await asUser(db, user, `insert into public.quest_completions (day, quest_id) values ($1, 'clean_drive')`, [today]);
});

test('quests: an id outside QuestCatalog can never be earned', async () => {
  const db = await freshDatabase();
  const user = await createUser(db, 'Forger');
  const today = await madridToday(db);

  await addDrive(db, user, { km: 10, score: 95 });
  await assert.rejects(
    asUser(db, user, `insert into public.quest_completions (day, quest_id) values ($1, 'a_one')`, [today]),
    /quest_unearned/,
  );
});
