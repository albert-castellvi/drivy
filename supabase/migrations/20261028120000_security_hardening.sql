-- Drivy — security and privacy hardening (odd/tasks/security-hardening.md S2, S3, S7)
-- No RPC returns other users' uuids, display names start as a pseudonym and only
-- they are editable, invite codes are made on the server and joins are
-- rate-limited with one uniform failure, and anon loses every grant in public.

-- ---------------------------------------------------------------------------
-- S2: display names — a pseudonym by default, editable, never the real name
-- ---------------------------------------------------------------------------
create or replace function public.pseudonym()
returns text
language sql
volatile
set search_path = public
as $$
  select 'Conductor ' || lpad((floor(random() * 10000))::int::text, 4, '0');
$$;

-- The Apple full name is never copied any more: strangers in public leagues see
-- this name, so it starts as a pseudonym the user can change in Ajustes.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, avatar_url)
  values (new.id, public.pseudonym(), null)
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- 'Driver' was the old fallback; every profile still carrying it gets its own
-- pseudonym so a league never shows a column of identical names.
update public.profiles set display_name = public.pseudonym() where display_name = 'Driver';

alter table public.profiles
  add constraint profiles_display_name_length
  check (char_length(btrim(display_name)) between 1 and 30);

-- Clients may change their display name and nothing else of their profile.
revoke update on public.profiles from authenticated;
grant update (display_name) on public.profiles to authenticated;

-- ---------------------------------------------------------------------------
-- S2: rankings say which row is the caller's instead of exposing uuids
-- ---------------------------------------------------------------------------
drop function public.public_league_ranking();

create function public.public_league_ranking()
returns table (
  place        bigint,
  display_name text,
  week_xp      bigint,
  zone         text,
  is_me        boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select s.place, s.display_name, s.week_xp, s.zone, s.user_id = auth.uid()
  from public.public_league_members m
  cross join lateral public.public_league_standings(m.group_id) s
  where m.user_id = auth.uid() and m.week_start = public.madrid_week_start()
  order by s.place;
$$;

revoke execute on function public.public_league_ranking() from public, anon;
grant execute on function public.public_league_ranking() to authenticated;

drop function public.league_weekly_ranking(uuid, date);

create function public.league_weekly_ranking(p_league_id uuid, p_week_start date)
returns table (
  rank         bigint,
  display_name text,
  week_xp      bigint,
  is_me        boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select rank() over (order by coalesce(x.week_xp, 0) desc),
         p.display_name,
         coalesce(x.week_xp, 0)::bigint,
         m.user_id = auth.uid()
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
-- S3: invite codes are made on the server, 8 symbols (40 bits)
-- ---------------------------------------------------------------------------
-- Creates the league and makes the caller its first member in one step. The
-- direct table inserts it replaces are no longer allowed.
create or replace function public.create_league(p_name text)
returns table (
  id          uuid,
  name        text,
  owner_id    uuid,
  invite_code text
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_user     uuid := auth.uid();
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_bytes    bytea;
  v_code     text;
  v_league   public.leagues;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  loop
    -- 32 symbols and 256 byte values: byte % 32 has no bias.
    v_bytes := gen_random_bytes(8);
    v_code := '';
    for i in 0..7 loop
      v_code := v_code || substr(v_alphabet, (get_byte(v_bytes, i) % 32) + 1, 1);
    end loop;

    begin
      insert into public.leagues (name, owner_id, invite_code)
      values (btrim(p_name), v_user, v_code)
      returning * into v_league;
      exit;
    exception when unique_violation then
      -- A collision in 2^40 codes: draw again.
    end;
  end loop;

  insert into public.league_members (league_id, user_id) values (v_league.id, v_user);

  return query select v_league.id, v_league.name, v_league.owner_id, v_league.invite_code;
end;
$$;

revoke execute on function public.create_league(text) from public, anon;
grant execute on function public.create_league(text) to authenticated;

drop policy "leagues_insert_owner" on public.leagues;
drop policy "league_members_insert_owner_self" on public.league_members;

-- ---------------------------------------------------------------------------
-- S3: joining is rate-limited and fails the same way for every bad code
-- ---------------------------------------------------------------------------
create table public.league_join_failures (
  user_id      uuid not null references public.profiles (id) on delete cascade,
  attempted_at timestamptz not null default now()
);

create index league_join_failures_user_idx on public.league_join_failures (user_id, attempted_at);

-- Only the join RPC reads or writes it.
alter table public.league_join_failures enable row level security;

-- Returns the league id, or null when the code does not exist or the league is
-- full: one answer for both, so codes cannot be probed for existence. After 10
-- failures in an hour it refuses with too_many_attempts. Failures are recorded
-- by returning null instead of raising, which would roll the record back.
create or replace function public.join_league_by_code(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_league  public.leagues;
  v_members integer;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  delete from public.league_join_failures
  where user_id = v_user and attempted_at < now() - interval '1 day';

  if (
    select count(*) from public.league_join_failures
    where user_id = v_user and attempted_at > now() - interval '1 hour'
  ) >= 10 then
    raise exception 'too_many_attempts';
  end if;

  -- Row lock: concurrent joins of one league are counted one at a time, so the
  -- 25-member cap holds.
  select * into v_league from public.leagues where invite_code = upper(btrim(p_code)) for update;

  if found and exists (
    select 1 from public.league_members where league_id = v_league.id and user_id = v_user
  ) then
    return v_league.id;  -- already a member
  end if;

  if found then
    select count(*) into v_members from public.league_members where league_id = v_league.id;
  end if;

  if not found or v_members >= 25 then
    insert into public.league_join_failures (user_id) values (v_user);
    return null;
  end if;

  insert into public.league_members (league_id, user_id) values (v_league.id, v_user);
  return v_league.id;
end;
$$;

revoke execute on function public.join_league_by_code(text) from public, anon;
grant execute on function public.join_league_by_code(text) to authenticated;

-- ---------------------------------------------------------------------------
-- S7: least privilege. Every table is RLS-protected already; these grants only
-- remove what no client path uses, so a future mistake is not amplified.
-- ---------------------------------------------------------------------------
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke truncate, references, trigger on all tables in schema public from authenticated;

-- Functions are executable by PUBLIC by default; keep only what signed-in users
-- need (the day helpers run inside the CHECK constraints of their inserts).
revoke execute on function public.madrid_today() from public, anon;
revoke execute on function public.madrid_week_start(timestamptz) from public, anon;
revoke execute on function public.set_updated_at() from public, anon, authenticated;
revoke execute on function public.pseudonym() from public, anon, authenticated;
grant execute on function public.madrid_today() to authenticated;
grant execute on function public.madrid_week_start(timestamptz) to authenticated;

-- Tables and functions created by later migrations start without anon access.
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on sequences from anon;
alter default privileges in schema public revoke execute on functions from anon, public;
