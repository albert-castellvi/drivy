-- Drivy MVP — schema v1 (T1, odd/tasks/drivy-mvp.md S10)
-- Tables: profiles, drives, daily_scores, leagues, league_members
-- RLS per user, weekly league ranking function, join-by-invite-code RPC.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text not null,
  avatar_url   text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- drives (one row per completed drive; raw GPS/motion stays on-device,
-- only summarized results are uploaded — S10)
-- ---------------------------------------------------------------------------
create table public.drives (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references public.profiles (id) on delete cascade,
  started_at          timestamptz not null,
  ended_at            timestamptz not null,
  distance_km         numeric(8, 2) not null check (distance_km >= 0),
  duration_s          integer not null check (duration_s > 0),
  score               integer not null check (score between 0 and 100),
  harsh_brakes        integer not null default 0 check (harsh_brakes >= 0),
  harsh_accelerations integer not null default 0 check (harsh_accelerations >= 0),
  phone_use_events    integer not null default 0 check (phone_use_events >= 0),
  speeding_events     integer not null default 0 check (speeding_events >= 0),
  connected_mode      boolean not null default false,
  summary             jsonb not null default '{}'::jsonb,
  created_at          timestamptz not null default now(),
  check (ended_at > started_at)
);

create index drives_user_started_idx on public.drives (user_id, started_at desc);

-- ---------------------------------------------------------------------------
-- daily_scores (S6: distance-weighted daily average; streak is derived)
-- ---------------------------------------------------------------------------
create table public.daily_scores (
  user_id      uuid not null references public.profiles (id) on delete cascade,
  day          date not null,
  score        integer not null check (score between 0 and 100),
  distance_km  numeric(8, 2) not null default 0 check (distance_km >= 0),
  drives_count integer not null default 0 check (drives_count >= 0),
  computed_at  timestamptz not null default now(),
  primary key (user_id, day)
);

create index daily_scores_day_idx on public.daily_scores (day);

-- ---------------------------------------------------------------------------
-- leagues (S7: private groups, max 25 members, weekly ranking)
-- ---------------------------------------------------------------------------
create table public.leagues (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (length(name) between 1 and 60),
  owner_id    uuid not null references public.profiles (id) on delete cascade,
  invite_code text not null unique,
  created_at  timestamptz not null default now()
);

create table public.league_members (
  league_id uuid not null references public.leagues (id) on delete cascade,
  user_id   uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (league_id, user_id)
);

create index league_members_user_idx on public.league_members (user_id);

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Auto-create a profile when a user signs up (Sign in with Apple, S10)
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, avatar_url)
  values (
    new.id,
    coalesce(
      nullif(new.raw_user_meta_data ->> 'full_name', ''),
      nullif(new.raw_user_meta_data ->> 'name', ''),
      'Driver'
    ),
    new.raw_user_meta_data ->> 'avatar_url'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Join a league by invite code, enforcing the 25-member cap (S7)
create or replace function public.join_league_by_code(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_league  public.leagues;
  v_members integer;
begin
  select * into v_league from public.leagues where invite_code = p_code;
  if not found then
    raise exception 'league_not_found';
  end if;

  if exists (
    select 1 from public.league_members
    where league_id = v_league.id and user_id = auth.uid()
  ) then
    return v_league.id;  -- already a member
  end if;

  select count(*) into v_members from public.league_members where league_id = v_league.id;
  if v_members >= 25 then
    raise exception 'league_full';
  end if;

  insert into public.league_members (league_id, user_id)
  values (v_league.id, auth.uid());

  return v_league.id;
end;
$$;

revoke execute on function public.join_league_by_code(text) from public, anon;
grant execute on function public.join_league_by_code(text) to authenticated;

-- Weekly league ranking (S7): distance-weighted average score per member for
-- the ISO week starting at p_week_start; ties broken by total km.
create or replace function public.league_weekly_ranking(p_league_id uuid, p_week_start date)
returns table (
  rank        bigint,
  user_id     uuid,
  display_name text,
  avg_score   numeric,
  total_km    numeric
)
language sql
stable
security definer
set search_path = public
as $$
  with week_drives as (
    select d.user_id, d.score, d.distance_km
    from public.drives d
    join public.league_members m
      on m.user_id = d.user_id and m.league_id = p_league_id
    where d.started_at >= p_week_start::timestamptz
      and d.started_at < (p_week_start + 7)::timestamptz
  ),
  per_user as (
    select user_id,
           case
             when sum(distance_km) > 0
               then round(sum(score * distance_km) / sum(distance_km))
             else round(avg(score))
           end as avg_score,
           coalesce(sum(distance_km), 0) as total_km
    from week_drives
    group by user_id
  )
  select rank() over (order by pu.avg_score desc, pu.total_km desc),
         pu.user_id,
         pr.display_name,
         pu.avg_score,
         pu.total_km
  from per_user pu
  join public.profiles pr on pr.id = pu.user_id;
$$;

revoke execute on function public.league_weekly_ranking(uuid, date) from public, anon;
grant execute on function public.league_weekly_ranking(uuid, date) to authenticated;

-- ---------------------------------------------------------------------------
-- RLS (S10)
-- ---------------------------------------------------------------------------
alter table public.profiles        enable row level security;
alter table public.drives          enable row level security;
alter table public.daily_scores    enable row level security;
alter table public.leagues         enable row level security;
alter table public.league_members  enable row level security;

-- profiles: see yourself and co-members of your leagues; edit only yourself
create policy "profiles_select_self_or_league_mates"
  on public.profiles for select to authenticated
  using (
    id = auth.uid()
    or exists (
      select 1
      from public.league_members mine
      where mine.user_id = auth.uid()
        and exists (
          select 1 from public.league_members theirs
          where theirs.league_id = mine.league_id and theirs.user_id = profiles.id
        )
    )
  );

create policy "profiles_insert_self"
  on public.profiles for insert to authenticated
  with check (id = auth.uid());

create policy "profiles_update_self"
  on public.profiles for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- drives: strict ownership
create policy "drives_all_owner"
  on public.drives for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- daily_scores: strict ownership (computed client-side for the MVP)
create policy "daily_scores_all_owner"
  on public.daily_scores for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- leagues: visible to members and owner; managed by the owner
create policy "leagues_select_member_or_owner"
  on public.leagues for select to authenticated
  using (
    owner_id = auth.uid()
    or exists (
      select 1 from public.league_members
      where league_members.league_id = leagues.id and league_members.user_id = auth.uid()
    )
  );

create policy "leagues_insert_owner"
  on public.leagues for insert to authenticated
  with check (owner_id = auth.uid());

create policy "leagues_update_owner"
  on public.leagues for update to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy "leagues_delete_owner"
  on public.leagues for delete to authenticated
  using (owner_id = auth.uid());

-- league_members: see co-members of your leagues; join/leave yourself
create policy "league_members_select_league_mates"
  on public.league_members for select to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.league_members mine
      where mine.user_id = auth.uid() and mine.league_id = league_members.league_id
    )
  );

create policy "league_members_insert_self"
  on public.league_members for insert to authenticated
  with check (user_id = auth.uid());

create policy "league_members_delete_self_or_owner"
  on public.league_members for delete to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.leagues
      where leagues.id = league_members.league_id and leagues.owner_id = auth.uid()
    )
  );
