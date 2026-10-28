-- Drivy — server-side validation of client-written XP inputs (B2)
-- odd/tasks/server-validation.md S3. The server stops trusting what the client
-- uploads: drives get plausibility limits and lose the owner UPDATE policy,
-- daily_scores is recomputed from drives instead of trusting client values, and
-- habit_levels / quest_completions are only accepted when the user's own drives
-- earn them. Predicates are ported verbatim from the Swift sources, each with a
-- file:line comment. XP amounts, caps, streak rules and copy are untouched.
-- Known limit (S3): the drive score is computed on the phone from sensor data
-- that never leaves it; the server bounds it but cannot recompute it.

-- ---------------------------------------------------------------------------
-- S3.1: drives — plausibility limits at insert time
-- Every rejection raises P0001 with a stable message; existing rows are not
-- revalidated.
-- ---------------------------------------------------------------------------
create or replace function public.check_drive_plausible()
returns trigger
language plpgsql
-- Invoker: the owner's own drives are all it reads, and RLS already returns
-- exactly those. Like every function below, it is a no-op for writes that do
-- not come from the row's owner: RLS is the ownership guard, this trigger only
-- guards the owner's own writes, so service-role backfills stay possible.
-- The caller is read from the JWT claims instead of auth.uid() because the
-- same GUC can sit empty in a session that last served an anonymous request,
-- and an empty string is not valid JSON for auth.uid() to parse.
set search_path = ''
as $$
declare
  v_caller uuid := nullif(nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub', '')::uuid;
begin
  if v_caller is null or v_caller is distinct from new.user_id then
    return new;
  end if;

  -- A drive that starts more than 5 minutes from now is a forged clock.
  if new.started_at > now() + interval '5 minutes' then
    raise exception 'drive_implausible';
  end if;

  -- Older than 30 days: the app retries failed uploads days later (D4), but
  -- nothing legitimate is a month old.
  if new.started_at < now() - interval '30 days' then
    raise exception 'drive_implausible';
  end if;

  -- More than a day of driving is not a drive.
  if new.duration_s > 86400 then
    raise exception 'drive_implausible';
  end if;

  -- The claimed duration must match the timestamps within 120 s.
  if abs(new.duration_s - extract(epoch from (new.ended_at - new.started_at))) > 120 then
    raise exception 'drive_implausible';
  end if;

  -- Average speed above 250 km/h is not driving.
  if new.distance_km / (extract(epoch from (new.ended_at - new.started_at)) / 3600) > 250 then
    raise exception 'drive_implausible';
  end if;

  -- More than 50 drives in one Europe/Madrid day is a farm, not a driver.
  if (
    select count(*)
    from public.drives d
    where d.user_id = new.user_id
      and (d.started_at at time zone 'Europe/Madrid')::date
        = (new.started_at at time zone 'Europe/Madrid')::date
  ) >= 50 then
    raise exception 'daily_drive_limit';
  end if;

  return new;
end;
$$;

revoke execute on function public.check_drive_plausible() from public, anon, authenticated;

create trigger drives_plausible_check
  before insert on public.drives
  for each row execute function public.check_drive_plausible();

-- The owner can read, insert and delete; there is no UPDATE policy, so a
-- client cannot rewrite a drive after uploading it (the app only inserts; its
-- upsert uses ignoreDuplicates, which never updates).
drop policy "drives_all_owner" on public.drives;

create policy "drives_select_owner"
  on public.drives for select to authenticated
  using (user_id = auth.uid());

create policy "drives_insert_owner"
  on public.drives for insert to authenticated
  with check (user_id = auth.uid());

create policy "drives_delete_owner"
  on public.drives for delete to authenticated
  using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- S3.2: daily_scores — recomputed from drives, client values ignored
-- Same distance-weighted average as the client (SupabaseDriveRepository.swift
-- :39-66 reading back the day's drives, DailyScoreCalculator.swift:23-42 for
-- the aggregate: distance-weighted when there is distance, plain average
-- otherwise, rounded half away from zero). Old builds keep working: their
-- upsert simply has its values overwritten.
-- ---------------------------------------------------------------------------
create or replace function public.recompute_daily_score()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_caller uuid := nullif(nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub', '')::uuid;
  v_score integer;
  v_km    numeric;
  v_count integer;
begin
  if v_caller is null or v_caller is distinct from new.user_id then
    return new;
  end if;

  select coalesce(
           round(
             sum(d.score * d.distance_km) / nullif(sum(d.distance_km), 0)
           )::int,
           round(avg(d.score))::int,
           0),
         round(coalesce(sum(d.distance_km), 0), 2),
         count(*)::int
  into v_score, v_km, v_count
  from public.drives d
  where d.user_id = new.user_id
    and (d.started_at at time zone 'Europe/Madrid')::date = new.day;

  new.score = v_score;
  new.distance_km = v_km;
  new.drives_count = v_count;
  return new;
end;
$$;

revoke execute on function public.recompute_daily_score() from public, anon, authenticated;

create trigger daily_scores_recompute
  before insert or update on public.daily_scores
  for each row execute function public.recompute_daily_score();

-- ---------------------------------------------------------------------------
-- S3.3: habit_levels — a level exists only when the drives earn it
-- Ported from HabitPathEngine.swift and HabitUnit.swift:
--   - window [now - 30 days, now + 5 min] for completed_at;
--   - level L > 1 requires level L-1 of the same unit
--     (HabitPathEngine.swift:181-186, the next unit opens only at the
--     previous unit's level-3 completed_at);
--   - a unit other than the first requires level 3 of the previous unit
--     (HabitUnit.previous, HabitUnit.swift:66-70; HabitPathEngine.swift:184);
--   - qualifying drives: distance_km >= 2 (HabitPathEngine.swift:45,
--     qualifyingDistanceKm) and HabitUnit.isQualified (HabitUnit.swift:52-63),
--     started between the unit's opening and completed_at
--     (HabitPathEngine.swift:163-167), at least [3, 7, 15][L-1] of them
--     (HabitPathEngine.swift:31, levelRequirements; the count is cumulative
--     since the unit opened, HabitPathEngine.swift:27-28).
-- ---------------------------------------------------------------------------
create or replace function public.check_habit_level_earned()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_caller uuid := nullif(nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub', '')::uuid;
  -- HabitUnit.allCases order (HabitUnit.swift:23-29): the path plays them in
  -- this order.
  v_units    constant text[] := array[
    'smooth_braking', 'smooth_acceleration', 'no_phone', 'speed', 'connected'];
  v_index    integer;
  v_previous text;
  v_opened   timestamptz;
  v_needed   integer;
  v_count    integer;
begin
  if v_caller is null or v_caller is distinct from new.user_id then
    return new;
  end if;

  if new.completed_at < now() - interval '30 days'
     or new.completed_at > now() + interval '5 minutes' then
    raise exception 'habit_level_unearned';
  end if;

  v_index := array_position(v_units, new.unit);
  if v_index is null then
    raise exception 'habit_level_unearned';
  end if;

  if new.level > 1 and not exists (
    select 1 from public.habit_levels h
    where h.user_id = new.user_id and h.unit = new.unit and h.level = new.level - 1
  ) then
    raise exception 'habit_level_unearned';
  end if;

  if v_index > 1 then
    v_previous := v_units[v_index - 1];
    if not exists (
      select 1 from public.habit_levels h
      where h.user_id = new.user_id and h.unit = v_previous and h.level = 3
    ) then
      raise exception 'habit_level_unearned';
    end if;
    -- HabitPathEngine.swift:184: the unit opens at the previous unit's
    -- level-3 completedAt, and at nothing else.
    select h.completed_at into v_opened
    from public.habit_levels h
    where h.user_id = new.user_id and h.unit = v_previous and h.level = 3;
  else
    -- HabitPathEngine.swift:48-50: the first unit counts from the epoch.
    v_opened := timestamptz '1970-01-01 00:00:00+00';
  end if;

  -- HabitPathEngine.swift:31: 3, 7 or 15 drives for levels 1, 2, 3.
  v_needed := (array[3, 7, 15])[new.level];

  select count(*) into v_count
  from public.drives d
  where d.user_id = new.user_id
    -- HabitPathEngine.swift:163-165: started since the unit opened and no
    -- later than the moment the level is recorded.
    and d.started_at >= v_opened
    and d.started_at <= new.completed_at
    -- HabitPathEngine.swift:45: a drive counts only from 2 km.
    and d.distance_km >= 2
    -- HabitUnit.isQualified (HabitUnit.swift:52-63), one branch per unit.
    and case new.unit
          when 'smooth_braking' then d.harsh_brakes = 0
          when 'smooth_acceleration' then d.harsh_accelerations = 0
          when 'no_phone' then d.phone_use_events = 0
          when 'speed' then d.speeding_events = 0
          when 'connected' then d.connected_mode
        end;

  if v_count < v_needed then
    raise exception 'habit_level_unearned';
  end if;

  return new;
end;
$$;

revoke execute on function public.check_habit_level_earned() from public, anon, authenticated;

create trigger habit_levels_earned_check
  before insert on public.habit_levels
  for each row execute function public.check_habit_level_earned();

-- ---------------------------------------------------------------------------
-- S3.4: quest_completions — the exact predicates of QuestCatalog.swift
-- Every drive quest is one qualifying drive of the quest's Europe/Madrid day:
-- distance_km >= 2 (QuestEvaluator.swift:40-42, QuestCatalog.swift:39) plus
-- the requirement of the quest (QuestCatalog.swift:44-96 ids, evaluated as in
-- QuestEvaluator.swift:11-32). The lesson quest needs that day's
-- lesson_completions row (QuestEvaluator.swift:29-30).
-- ---------------------------------------------------------------------------
create or replace function public.check_quest_earned()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_caller uuid := nullif(nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub', '')::uuid;
begin
  if v_caller is null or v_caller is distinct from new.user_id then
    return new;
  end if;

  -- Days outside [today - 1, today] are already refused by the table's CHECK
  -- constraint; leave them their existing error.
  if new.day not between public.madrid_today() - 1 and public.madrid_today() then
    return new;
  end if;

  if new.quest_id = 'lesson' then
    -- QuestRequirement.lesson (QuestCatalog.swift:46-52,
    -- QuestEvaluator.swift:29-30): today's theory lesson is done.
    if not exists (
      select 1 from public.lesson_completions l
      where l.user_id = new.user_id and l.day = new.day
    ) then
      raise exception 'quest_unearned';
    end if;
    return new;
  end if;

  if not exists (
    select 1
    from public.drives d
    where d.user_id = new.user_id
      and (d.started_at at time zone 'Europe/Madrid')::date = new.day
      -- QuestEvaluator.qualifies (QuestEvaluator.swift:40-42): the shared
      -- 2 km floor (QuestCatalog.minimumDistanceKm, QuestCatalog.swift:39).
      and d.distance_km >= 2
      -- The requirement of each catalog quest (QuestCatalog.swift:44-96).
      and case new.quest_id
            -- clean_drive, .cleanDrive(minimumScore: 90) (QuestCatalog.swift:53-58)
            when 'clean_drive' then d.score >= 90
            -- perfect_drive, .cleanDrive(minimumScore: 95) (QuestCatalog.swift:60-65)
            when 'perfect_drive' then d.score >= 95
            -- careful_drive, .cleanDrive(minimumScore: 75) (QuestCatalog.swift:67-72)
            when 'careful_drive' then d.score >= 75
            -- no_events_drive, .driveWithoutEvents (QuestCatalog.swift:74-80)
            when 'no_events_drive' then d.harsh_brakes = 0 and d.harsh_accelerations = 0
                 and d.phone_use_events = 0 and d.speeding_events = 0
            -- no_phone_drive, .driveWithoutPhoneUse (QuestCatalog.swift:82-86)
            when 'no_phone_drive' then d.phone_use_events = 0
            -- smooth_brakes, .driveWithoutHarshBrakes (QuestCatalog.swift:88-92)
            when 'smooth_brakes' then d.harsh_brakes = 0
            -- smooth_start, .driveWithoutHarshAccelerations (QuestCatalog.swift:94-98)
            when 'smooth_start' then d.harsh_accelerations = 0
            -- legal_speed, .driveWithoutSpeeding (QuestCatalog.swift:100-104)
            when 'legal_speed' then d.speeding_events = 0
            -- connected_drive, .connectedDrive (QuestCatalog.swift:106-110)
            when 'connected_drive' then d.connected_mode
          end
  ) then
    raise exception 'quest_unearned';
  end if;

  return new;
end;
$$;

revoke execute on function public.check_quest_earned() from public, anon, authenticated;

create trigger quests_earned_check
  before insert on public.quest_completions
  for each row execute function public.check_quest_earned();
