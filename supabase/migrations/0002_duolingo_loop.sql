-- Drivy — Duolingo loop (T1, odd/tasks/duolingo-loop.md S1-S8, S10)
-- Fixes the league RLS recursion, adds lessons, quests, habit levels, streak
-- repairs, an XP ledger and public tiered leagues; private leagues rank by
-- weekly XP instead of score + km. Days and weeks are Europe/Madrid.

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
-- Monday of the Europe/Madrid week that contains p_at.
-- ponytail: one fixed zone for every user (the app targets Spain); store the
-- user's zone on the profile if Drivy ships outside it.
create or replace function public.madrid_week_start(p_at timestamptz default now())
returns date
language sql
stable
set search_path = public
as $$
  select date_trunc('week', p_at at time zone 'Europe/Madrid')::date;
$$;

-- Leagues the caller belongs to. Security definer so policies on
-- league_members can use it without querying league_members under RLS again
-- (that self-reference is what raised 42P17 "infinite recursion", S10).
create or replace function public.my_league_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select league_id from public.league_members where user_id = auth.uid();
$$;

revoke execute on function public.my_league_ids() from public, anon;
grant execute on function public.my_league_ids() to authenticated;

-- ---------------------------------------------------------------------------
-- S10: league RLS without recursion
-- ---------------------------------------------------------------------------
drop policy "league_members_select_league_mates" on public.league_members;
create policy "league_members_select_league_mates"
  on public.league_members for select to authenticated
  using (user_id = auth.uid() or league_id in (select public.my_league_ids()));

drop policy "leagues_select_member_or_owner" on public.leagues;
create policy "leagues_select_member_or_owner"
  on public.leagues for select to authenticated
  using (owner_id = auth.uid() or id in (select public.my_league_ids()));

drop policy "profiles_select_self_or_league_mates" on public.profiles;
create policy "profiles_select_self_or_league_mates"
  on public.profiles for select to authenticated
  using (
    id = auth.uid()
    or exists (
      select 1 from public.league_members theirs
      where theirs.user_id = profiles.id
        and theirs.league_id in (select public.my_league_ids())
    )
  );

-- Joining someone else's league goes through join_league_by_code (invite code
-- and 25-member cap). A direct insert is only for the owner adding themself
-- right after creating the league; before, anyone could join any league.
drop policy "league_members_insert_self" on public.league_members;
create policy "league_members_insert_owner_self"
  on public.league_members for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.leagues
      where leagues.id = league_members.league_id and leagues.owner_id = auth.uid()
    )
  );

-- Today in Spain. Progress days come from the device: a lesson or quest can be
-- stored for today or yesterday only (yesterday covers Canarias, one hour
-- behind, around midnight), so nobody back- or pre-fills a week of XP.
-- ponytail: still trusts one day of client clock; move the day server-side if
-- a public league ever carries a prize.
create or replace function public.madrid_today()
returns date
language sql
stable
set search_path = public
as $$
  select (now() at time zone 'Europe/Madrid')::date;
$$;

-- ---------------------------------------------------------------------------
-- S2: theory lessons (one per day counts for the streak and for XP)
-- ---------------------------------------------------------------------------
create table public.lesson_completions (
  user_id      uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  day          date not null,
  correct      integer not null check (correct >= 0),
  total        integer not null check (total between 1 and 20),
  completed_at timestamptz not null default now(),
  primary key (user_id, day),
  check (correct <= total),
  check (day between public.madrid_today() - 1 and public.madrid_today())
);

-- ---------------------------------------------------------------------------
-- S6: daily quests (catalog lives in the app; ids are its stable keys)
-- ---------------------------------------------------------------------------
create table public.quest_completions (
  user_id      uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  day          date not null,
  quest_id     text not null check (quest_id ~ '^[a-z_]{1,40}$'),
  completed_at timestamptz not null default now(),
  primary key (user_id, day, quest_id),
  check (day between public.madrid_today() - 1 and public.madrid_today())
);

-- ---------------------------------------------------------------------------
-- S3: habit path levels (3 levels per unit)
-- ---------------------------------------------------------------------------
create table public.habit_levels (
  user_id      uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  unit         text not null check (unit in (
                 'smooth_braking', 'smooth_acceleration', 'no_phone', 'speed', 'connected')),
  level        smallint not null check (level between 1 and 3),
  completed_at timestamptz not null default now(),
  primary key (user_id, unit, level)
);

-- ---------------------------------------------------------------------------
-- S8: premium streak repairs (the day that broke the run, now forgiven)
-- ponytail: premium is verified by StoreKit on the device only; move the
-- gate server-side (App Store Server API) if repairs get abused.
-- ---------------------------------------------------------------------------
create table public.streak_repairs (
  user_id    uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  -- The repair window is 48 h (S8): only a recent day can be forgiven.
  day        date not null check (day between public.madrid_today() - 3 and public.madrid_today()),
  created_at timestamptz not null default now(),
  primary key (user_id, day)
);

-- Owner can read and add rows; nothing is ever edited or deleted by clients.
alter table public.lesson_completions enable row level security;
alter table public.quest_completions  enable row level security;
alter table public.habit_levels       enable row level security;
alter table public.streak_repairs     enable row level security;

create policy "lesson_completions_select_own" on public.lesson_completions
  for select to authenticated using (user_id = auth.uid());
create policy "lesson_completions_insert_own" on public.lesson_completions
  for insert to authenticated with check (user_id = auth.uid());

create policy "quest_completions_select_own" on public.quest_completions
  for select to authenticated using (user_id = auth.uid());
create policy "quest_completions_insert_own" on public.quest_completions
  for insert to authenticated with check (user_id = auth.uid());

create policy "habit_levels_select_own" on public.habit_levels
  for select to authenticated using (user_id = auth.uid());
create policy "habit_levels_insert_own" on public.habit_levels
  for insert to authenticated with check (user_id = auth.uid());

create policy "streak_repairs_select_own" on public.streak_repairs
  for select to authenticated using (user_id = auth.uid());
create policy "streak_repairs_insert_own" on public.streak_repairs
  for insert to authenticated with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- S4: XP ledger. XP never scales with km: a drive of at least 2 km earns 20 XP
-- with score >= 90 and 10 XP with score >= 75, best 3 drives per day; lesson
-- 10 XP; quest 15 XP (3 per day); habit level 50 XP.
-- security_invoker: callers see only their own rows through the base tables'
-- RLS; the definer functions below read it as the table owner.
-- ponytail: computed on every read; materialize per week if it gets slow.
-- ---------------------------------------------------------------------------
create view public.xp_ledger
with (security_invoker = true)
as
with drive_xp as (
  select user_id,
         (started_at at time zone 'Europe/Madrid')::date as day,
         case when score >= 90 then 20 when score >= 75 then 10 else 0 end as xp
  from public.drives
  where distance_km >= 2
),
best_drives as (
  select user_id, day, xp,
         row_number() over (partition by user_id, day order by xp desc) as n
  from drive_xp
  where xp > 0
),
quests as (
  select user_id, day,
         row_number() over (partition by user_id, day order by completed_at, quest_id) as n
  from public.quest_completions
)
select user_id, day, 'drive'::text as source, xp from best_drives where n <= 3
union all
select user_id, day, 'lesson', 10 from public.lesson_completions
union all
select user_id, day, 'quest', 15 from quests where n <= 3
union all
select user_id, (completed_at at time zone 'Europe/Madrid')::date, 'habit_level', 50
from public.habit_levels;

-- Caller's lifetime XP and XP of the Monday-to-Sunday week of p_week_start
-- (any day of the week is accepted and rounded down to its Monday).
create or replace function public.my_xp(p_week_start date)
returns table (total_xp bigint, week_xp bigint)
language sql
stable
set search_path = public
as $$
  with w as (select date_trunc('week', p_week_start)::date as monday)
  select coalesce(sum(l.xp), 0)::bigint,
         coalesce(sum(l.xp) filter (where l.day >= w.monday and l.day < w.monday + 7), 0)::bigint
  from w
  left join public.xp_ledger l on l.user_id = auth.uid()
  group by w.monday;
$$;

revoke execute on function public.my_xp(date) from public, anon;
grant execute on function public.my_xp(date) to authenticated;

-- ---------------------------------------------------------------------------
-- S5: private leagues rank by weekly XP (was distance-weighted score + km).
-- Every member is listed, 0 XP included, and only members can read it (the
-- previous version answered any signed-in caller who knew the league id).
-- p_week_start is rounded down to its Monday, so a mid-week date cannot shift
-- the window.
-- ---------------------------------------------------------------------------
drop function public.league_weekly_ranking(uuid, date);

create function public.league_weekly_ranking(p_league_id uuid, p_week_start date)
returns table (
  rank         bigint,
  user_id      uuid,
  display_name text,
  week_xp      bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select rank() over (order by coalesce(x.week_xp, 0) desc),
         m.user_id,
         p.display_name,
         coalesce(x.week_xp, 0)::bigint
  from public.league_members m
  join public.profiles p on p.id = m.user_id
  left join (
    select l.user_id, sum(l.xp) as week_xp
    from public.xp_ledger l
    cross join (select date_trunc('week', p_week_start)::date as monday) w
    where l.day >= w.monday and l.day < w.monday + 7
    group by l.user_id
  ) x on x.user_id = m.user_id
  where m.league_id = p_league_id
    and p_league_id in (select public.my_league_ids())
  order by 1, p.display_name;
$$;

revoke execute on function public.league_weekly_ranking(uuid, date) from public, anon;
grant execute on function public.league_weekly_ranking(uuid, date) to authenticated;

-- ---------------------------------------------------------------------------
-- S5: public tiered leagues. Divisions 1..5 = Bronce, Plata, Oro, Platino,
-- Diamante. Groups of up to 30 per division and week. Clients never touch
-- these tables: everything goes through the RPCs below.
-- ---------------------------------------------------------------------------
create table public.public_league_entries (
  user_id      uuid primary key references public.profiles (id) on delete cascade,
  opted_in     boolean not null default true,
  division     smallint not null default 1 check (division between 1 and 5),
  -- Result of the last settled week: 1 promoted, -1 demoted, 0 stayed.
  last_change  smallint not null default 0 check (last_change between -1 and 1),
  settled_week date,
  updated_at   timestamptz not null default now()
);

create table public.public_league_groups (
  id         uuid primary key default gen_random_uuid(),
  week_start date not null,
  division   smallint not null check (division between 1 and 5),
  created_at timestamptz not null default now()
);

create index public_league_groups_week_division_idx
  on public.public_league_groups (week_start, division);

create table public.public_league_members (
  week_start date not null,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  group_id   uuid not null references public.public_league_groups (id) on delete cascade,
  joined_at  timestamptz not null default now(),
  primary key (week_start, user_id)
);

create index public_league_members_group_idx on public.public_league_members (group_id);

alter table public.public_league_entries enable row level security;
alter table public.public_league_groups  enable row level security;
alter table public.public_league_members enable row level security;

create policy "public_league_entries_select_own" on public.public_league_entries
  for select to authenticated using (user_id = auth.uid());

-- Standings of one group: top 7 with XP promote (not from Diamante), bottom 5
-- demote (not from Bronce, never inside the top 7). Ties go to who joined the
-- group first. Internal: callers go through public_league_ranking().
create or replace function public.public_league_standings(p_group uuid)
returns table (
  place        bigint,
  user_id      uuid,
  display_name text,
  week_xp      bigint,
  zone         text
)
language sql
stable
security definer
set search_path = public
as $$
  with g as (
    select week_start, division from public.public_league_groups where id = p_group
  ),
  totals as (
    select m.user_id, p.display_name, m.joined_at, coalesce(sum(l.xp), 0)::bigint as week_xp
    from public.public_league_members m
    cross join g
    join public.profiles p on p.id = m.user_id
    left join public.xp_ledger l
      on l.user_id = m.user_id and l.day >= g.week_start and l.day < g.week_start + 7
    where m.group_id = p_group
    group by m.user_id, p.display_name, m.joined_at
  ),
  ordered as (
    select t.*,
           row_number() over (order by t.week_xp desc, t.joined_at, t.user_id) as place,
           count(*) over () as size
    from totals t
  )
  select o.place, o.user_id, o.display_name, o.week_xp,
         case
           when g.division < 5 and o.place <= 7 and o.week_xp > 0 then 'promotion'
           when g.division > 1 and o.place > greatest(o.size - 5, 7) then 'demotion'
         end
  from ordered o
  cross join g
  order by o.place;
$$;

revoke execute on function public.public_league_standings(uuid) from public, anon, authenticated;

-- Opt in or out of public leagues. Opting out also leaves this week's group,
-- so the name disappears from it; the division is kept for a later opt-in.
create or replace function public.set_public_league_opt_in(p_on boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  insert into public.public_league_entries (user_id, opted_in)
  values (auth.uid(), p_on)
  on conflict (user_id) do update
    set opted_in = excluded.opted_in, updated_at = now();

  if not p_on then
    delete from public.public_league_members
    where user_id = auth.uid() and week_start = public.madrid_week_start();
  end if;
end;
$$;

revoke execute on function public.set_public_league_opt_in(boolean) from public, anon;
grant execute on function public.set_public_league_opt_in(boolean) to authenticated;

-- Caller's public group for the current week. On the first call of a new week
-- it settles the last week played (promotion/demotion, once) and places the
-- caller in the first group of their division with room, or a new one. This
-- lazy rollover replaces a weekly job (L8).
create or replace function public.public_league_current()
returns table (
  group_id    uuid,
  week_start  date,
  division    smallint,
  last_change smallint
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_user   uuid := auth.uid();
  v_week   date := public.madrid_week_start();
  v_entry  public.public_league_entries;
  v_prev   public.public_league_members;
  v_zone   text;
  v_change smallint;
  v_group  uuid;
begin
  -- Row lock: two calls of the same user settle and join only once.
  select * into v_entry
  from public.public_league_entries e
  where e.user_id = v_user
  for update;

  if not found or not v_entry.opted_in then
    raise exception 'not_opted_in';
  end if;

  select m.group_id into v_group
  from public.public_league_members m
  where m.week_start = v_week and m.user_id = v_user;

  if v_group is null then
    select * into v_prev
    from public.public_league_members m
    where m.user_id = v_user and m.week_start < v_week
    order by m.week_start desc
    limit 1;

    if found and (v_entry.settled_week is null or v_entry.settled_week < v_prev.week_start) then
      select s.zone into v_zone
      from public.public_league_standings(v_prev.group_id) s
      where s.user_id = v_user;

      v_change := case v_zone when 'promotion' then 1 when 'demotion' then -1 else 0 end;

      update public.public_league_entries e
      set division     = e.division + v_change,
          last_change  = v_change,
          settled_week = v_prev.week_start,
          updated_at   = now()
      where e.user_id = v_user
      returning * into v_entry;
    end if;

    -- One filler at a time per division and week keeps groups at 30 at most.
    perform pg_advisory_xact_lock(
      hashtextextended('drivy_public_league:' || v_week || ':' || v_entry.division, 0)
    );

    select g.id into v_group
    from public.public_league_groups g
    where g.week_start = v_week
      and g.division = v_entry.division
      and (select count(*) from public.public_league_members m where m.group_id = g.id) < 30
    order by g.created_at, g.id
    limit 1;

    if v_group is null then
      insert into public.public_league_groups (week_start, division)
      values (v_week, v_entry.division)
      returning id into v_group;
    end if;

    insert into public.public_league_members (week_start, user_id, group_id)
    values (v_week, v_user, v_group);
  end if;

  return query select v_group, v_week, v_entry.division, v_entry.last_change;
end;
$$;

revoke execute on function public.public_league_current() from public, anon;
grant execute on function public.public_league_current() to authenticated;

-- Standings of the caller's group this week (empty when not placed yet).
create or replace function public.public_league_ranking()
returns table (
  place        bigint,
  user_id      uuid,
  display_name text,
  week_xp      bigint,
  zone         text
)
language sql
stable
security definer
set search_path = public
as $$
  select s.*
  from public.public_league_members m
  cross join lateral public.public_league_standings(m.group_id) s
  where m.user_id = auth.uid() and m.week_start = public.madrid_week_start()
  order by s.place;
$$;

revoke execute on function public.public_league_ranking() from public, anon;
grant execute on function public.public_league_ranking() to authenticated;
