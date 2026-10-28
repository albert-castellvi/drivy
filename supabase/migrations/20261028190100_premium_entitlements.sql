-- Drivy — premium entitlements and the free one-league cap (odd/tasks/server-validation.md S5.1)
-- The server finally knows who pays: the verify-premium Edge Function upserts a
-- row here after verifying the App Store JWS offline, has_active_premium reads
-- it, and create_league / join_league_by_code stop free users at one league.
-- The client still cannot write any of this: only the service role does.

-- ---------------------------------------------------------------------------
-- premium_entitlements: one row per user, written only by the service role
-- ---------------------------------------------------------------------------
create table public.premium_entitlements (
  user_id                 uuid primary key references public.profiles (id) on delete cascade,
  original_transaction_id text not null unique,
  product_id              text not null,
  expires_at              timestamptz not null,
  revoked_at              timestamptz,
  environment             text,
  updated_at              timestamptz not null default now()
);

create trigger premium_entitlements_set_updated_at
  before update on public.premium_entitlements
  for each row execute function public.set_updated_at();

alter table public.premium_entitlements enable row level security;

-- A user may see its own entitlement (the app shows expiry state); everything
-- else is service-role-only, so there are no insert/update/delete policies.
create policy "premium_entitlements_select_own"
  on public.premium_entitlements
  for select
  to authenticated
  using (user_id = auth.uid());

revoke all on public.premium_entitlements from anon;
-- Same least-privilege shape security_hardening S7 gave every other table:
-- clients keep select only, never the maintenance privileges the default
-- privileges would hand them.
revoke truncate, references, trigger on public.premium_entitlements from authenticated;
revoke insert, update, delete on public.premium_entitlements from authenticated;
grant select on public.premium_entitlements to authenticated;
grant all on public.premium_entitlements to service_role;

-- ---------------------------------------------------------------------------
-- has_active_premium: one un-revoked, un-expired row
-- ---------------------------------------------------------------------------
create or replace function public.has_active_premium(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.premium_entitlements e
    where e.user_id = p_user
      and e.revoked_at is null
      and e.expires_at > now()
  );
$$;

-- Not granted to authenticated: it is an internal helper of the two security
-- definer RPCs and the service role, and probe A13 pins the exact client RPC
-- surface, which must not grow.
revoke execute on function public.has_active_premium(uuid) from public, anon, authenticated;
grant execute on function public.has_active_premium(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- S5.1: one league for free users, more with active premium
-- ---------------------------------------------------------------------------
-- Same function as 20261028111321_security_hardening.sql — every existing
-- behavior is kept (name trimming, 8-symbol code, 5 draw attempts, owner as
-- first member) and only the S5.1 cap is added: a caller already in >= 1 league
-- (as owner or member) without active premium is refused with league_limit.
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
  v_attempt  integer;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  -- B1: one league per free user; premium members keep creating leagues.
  if not public.has_active_premium(v_user)
     and exists (
       select 1 from public.league_members where user_id = v_user
       union all
       select 1 from public.leagues where owner_id = v_user
     ) then
    raise exception 'league_limit';
  end if;

  for v_attempt in 1..5 loop
    if v_attempt = 5 then
      raise exception 'invite_code_unavailable';
    end if;
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

-- Same function as 20261028111321_security_hardening.sql — name rules, the
-- already-member short-circuit, the 10-failures-per-hour budget, the 25-member
-- cap and the null answer for unknown codes all stay; only the S5.1 cap is
-- added, after the short-circuit so re-opening its own invite never fails.
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

  -- Row lock: concurrent joins of one league are counted one at a time, so the
  -- 25-member cap holds.
  select * into v_league from public.leagues where invite_code = upper(btrim(p_code)) for update;

  -- A member re-opening their own invite never spends the attempt budget.
  if found and exists (
    select 1 from public.league_members where league_id = v_league.id and user_id = v_user
  ) then
    return v_league.id;
  end if;

  -- B1: a free user already in a league cannot join another; premium lifts it.
  -- Raising (instead of returning null) keeps the failure budget untouched and
  -- gives the app its stable league_limit error to map to the paywall.
  if not public.has_active_premium(v_user)
     and exists (
       select 1 from public.league_members where user_id = v_user
       union all
       select 1 from public.leagues where owner_id = v_user
     ) then
    raise exception 'league_limit';
  end if;

  delete from public.league_join_failures
  where user_id = v_user and attempted_at < now() - interval '1 day';

  -- ponytail: count without a lock, so a burst of parallel calls can spend a
  -- few attempts over 10; a per-user advisory lock closes it if it matters.
  if (
    select count(*) from public.league_join_failures
    where user_id = v_user and attempted_at > now() - interval '1 hour'
  ) >= 10 then
    raise exception 'too_many_attempts';
  end if;

  if v_league.id is not null then
    select count(*) into v_members from public.league_members where league_id = v_league.id;
  end if;

  if v_league.id is null or v_members >= 25 then
    insert into public.league_join_failures (user_id) values (v_user);
    return null;
  end if;

  insert into public.league_members (league_id, user_id) values (v_league.id, v_user);
  return v_league.id;
end;
$$;

revoke execute on function public.join_league_by_code(text) from public, anon;
grant execute on function public.join_league_by_code(text) to authenticated;
