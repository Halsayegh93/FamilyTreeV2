-- ============================================================================
-- Phase 1 — Multi-tournament support (pragmatic).
-- ADDITIVE & BACKWARD-COMPATIBLE: the live single-tournament site keeps working.
-- Every function gains a trailing p_tournament arg DEFAULT 'wc26', so old RPC
-- calls (which omit it) resolve to the existing World Cup tournament unchanged.
-- Match ids stay GLOBALLY UNIQUE (each tournament uses its own id range), so no
-- primary-key / foreign-key surgery is needed.
-- Re-runnable.
-- ============================================================================

-- 1) Tournaments registry -----------------------------------------------------
create table if not exists public.wc_tournaments (
  id         text primary key,                 -- slug: 'wc26', 'gulf27', 'asia27'
  name       text not null,
  short_name text,
  active     boolean not null default true,
  format     text    not null default 'knockout',  -- 'knockout' | 'groups'
  sort       int     not null default 0,
  created_at timestamptz not null default now()
);
alter table public.wc_tournaments enable row level security;
drop policy if exists "tournaments public read" on public.wc_tournaments;
create policy "tournaments public read" on public.wc_tournaments for select using (true);

-- the existing data belongs to the World Cup
insert into public.wc_tournaments (id, name, short_name, active, format, sort)
values ('wc26', 'كأس العالم', 'كأس العالم', true, 'knockout', 1)
on conflict (id) do nothing;

-- 2) tournament_id on every data table (default backfills existing rows) -------
alter table public.wc_matches            add column if not exists tournament_id text not null default 'wc26' references public.wc_tournaments(id);
alter table public.wc_predictions        add column if not exists tournament_id text not null default 'wc26' references public.wc_tournaments(id);
alter table public.wc_bracket            add column if not exists tournament_id text not null default 'wc26' references public.wc_tournaments(id);
alter table public.wc_prediction_history add column if not exists tournament_id text not null default 'wc26' references public.wc_tournaments(id);
alter table public.wc_champion_picks     add column if not exists tournament_id text not null default 'wc26' references public.wc_tournaments(id);
alter table public.wc_settings           add column if not exists tournament_id text not null default 'wc26' references public.wc_tournaments(id);

-- group-stage support: which group a match belongs to (null = knockout match)
alter table public.wc_matches add column if not exists group_label text;

create index if not exists wc_matches_tid_idx     on public.wc_matches (tournament_id);
create index if not exists wc_predictions_tid_idx on public.wc_predictions (tournament_id);

-- 3) Per-tournament uniqueness ------------------------------------------------
-- champion pick: one per player PER TOURNAMENT (was globally unique)
alter table public.wc_champion_picks drop constraint if exists wc_champion_picks_player_name_key;
alter table public.wc_champion_picks drop constraint if exists wc_champion_picks_tid_name_key;
alter table public.wc_champion_picks add  constraint wc_champion_picks_tid_name_key unique (tournament_id, player_name);

-- settings: keyed per tournament (was PK on key alone)
do $$
begin
  if exists (
    select 1 from pg_constraint
    where conname = 'wc_settings_pkey'
      and conrelid = 'public.wc_settings'::regclass
      and pg_get_constraintdef(oid) = 'PRIMARY KEY (key)'
  ) then
    alter table public.wc_settings drop constraint wc_settings_pkey;
    alter table public.wc_settings add primary key (tournament_id, key);
  end if;
end $$;

-- ============================================================================
-- 4) Functions — tournament-aware. Trailing p_tournament DEFAULT 'wc26'.
-- ============================================================================

-- ---- player submit: prediction (score) -------------------------------------
create or replace function public.wc_submit_prediction(
  p_match_id integer, p_name text, p_home integer, p_away integer,
  p_pen_home integer default null, p_pen_away integer default null)
returns wc_predictions language plpgsql security definer set search_path to 'public'
as $function$
declare
  m   public.wc_matches;
  row public.wc_predictions;
  nm  text := nullif(btrim(p_name), '');
  ph  integer; pa integer; pen text;
begin
  if nm is null then raise exception 'NAME_REQUIRED'; end if;
  if p_home is null or p_away is null or p_home < 0 or p_away < 0
     or p_home > 99 or p_away > 99 then raise exception 'INVALID_SCORE'; end if;

  if p_home = p_away and p_pen_home is not null and p_pen_away is not null then
    if p_pen_home < 0 or p_pen_away < 0 or p_pen_home > 99 or p_pen_away > 99 then
      raise exception 'INVALID_SCORE'; end if;
    if p_pen_home = p_pen_away then raise exception 'INVALID_PICK'; end if;
    ph := p_pen_home; pa := p_pen_away;
    pen := case when ph > pa then 'home' else 'away' end;
  else
    ph := null; pa := null; pen := null;
  end if;

  select * into m from public.wc_matches where id = p_match_id;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  if m.finished or m.locked or (m.kickoff is not null and m.kickoff <= now()) then
    raise exception 'MATCH_LOCKED'; end if;

  insert into public.wc_predictions
    (tournament_id, match_id, player_name, home_score, away_score, pick, pen_pick, pen_home, pen_away)
  values (m.tournament_id, p_match_id, nm, p_home, p_away, null, pen, ph, pa)
  on conflict (match_id, player_name) do update set
    home_score = excluded.home_score, away_score = excluded.away_score,
    pick = null, pen_pick = excluded.pen_pick,
    pen_home = excluded.pen_home, pen_away = excluded.pen_away, updated_at = now()
  returning * into row;
  return row;
end;
$function$;

-- ---- player submit: winner-only --------------------------------------------
create or replace function public.wc_submit_winner(
  p_match_id integer, p_name text, p_pick text)
returns wc_predictions language plpgsql security definer set search_path to 'public'
as $function$
declare
  m   public.wc_matches;
  row public.wc_predictions;
  nm  text := nullif(btrim(p_name), '');
begin
  if nm is null then raise exception 'NAME_REQUIRED'; end if;
  if p_pick is null or p_pick not in ('home','away') then raise exception 'INVALID_PICK'; end if;

  select * into m from public.wc_matches where id = p_match_id;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  if m.finished or m.locked or (m.kickoff is not null and m.kickoff <= now()) then
    raise exception 'MATCH_LOCKED'; end if;

  insert into public.wc_predictions
    (tournament_id, match_id, player_name, home_score, away_score, pick, pen_pick, pen_home, pen_away)
  values (m.tournament_id, p_match_id, nm, null, null, p_pick, null, null, null)
  on conflict (match_id, player_name) do update set
    home_score = null, away_score = null, pick = excluded.pick,
    pen_pick = null, pen_home = null, pen_away = null, updated_at = now()
  returning * into row;
  return row;
end;
$function$;

-- ---- history trigger: carry tournament_id ----------------------------------
create or replace function public.wc_log_prediction_change()
returns trigger language plpgsql security definer set search_path to 'public'
as $function$
begin
  if tg_op = 'INSERT' then
    insert into public.wc_prediction_history
      (tournament_id, match_id, player_name, home_score, away_score, pick,
       pen_pick, pen_home, pen_away, action, changed_at)
    values
      (new.tournament_id, new.match_id, new.player_name, new.home_score, new.away_score, new.pick,
       new.pen_pick, new.pen_home, new.pen_away, 'created', now());
    return new;
  end if;
  if new.home_score is distinct from old.home_score
     or new.away_score is distinct from old.away_score
     or new.pick      is distinct from old.pick
     or new.pen_pick  is distinct from old.pen_pick
     or new.pen_home  is distinct from old.pen_home
     or new.pen_away  is distinct from old.pen_away then
    insert into public.wc_prediction_history
      (tournament_id, match_id, player_name, home_score, away_score, pick,
       pen_pick, pen_home, pen_away, action, changed_at)
    values
      (new.tournament_id, new.match_id, new.player_name, new.home_score, new.away_score, new.pick,
       new.pen_pick, new.pen_home, new.pen_away, 'updated', now());
  end if;
  return new;
end;
$function$;

-- ---- champion pick (player) -------------------------------------------------
drop function if exists public.wc_submit_champion(text, text);
create or replace function public.wc_submit_champion(
  p_name text, p_team text, p_tournament text default 'wc26')
returns wc_champion_picks language plpgsql security definer set search_path to 'public'
as $function$
declare
  nm  text := nullif(btrim(p_name), '');
  tm  text := nullif(btrim(p_team), '');
  qf1 timestamptz;
  row public.wc_champion_picks;
begin
  if nm is null then raise exception 'NAME_REQUIRED'; end if;
  if tm is null then raise exception 'INVALID_TEAM';  end if;

  -- lock when the knockout stage begins (first QF, or first SF for group cups)
  select min(kickoff) into qf1
    from public.wc_matches
   where tournament_id = p_tournament and round in ('QF','SF') and kickoff is not null;
  if qf1 is not null and now() >= qf1 then raise exception 'CHAMPION_LOCKED'; end if;

  if not exists (select 1 from public.wc_matches
                 where tournament_id = p_tournament and (home_team = tm or away_team = tm)) then
    raise exception 'INVALID_TEAM';
  end if;

  if exists (select 1 from public.wc_champion_picks
             where tournament_id = p_tournament and player_name = nm) then
    raise exception 'ALREADY_PICKED';
  end if;

  insert into public.wc_champion_picks (tournament_id, player_name, team)
  values (p_tournament, nm, tm)
  returning * into row;
  return row;
end;
$function$;

-- ---- maintenance read helper ------------------------------------------------
drop function if exists public.wc_maintenance_on();
create or replace function public.wc_maintenance_on(p_tournament text default 'wc26')
returns boolean language sql stable set search_path to 'public'
as $function$
  select coalesce((select value = 'on' from public.wc_settings
                   where tournament_id = p_tournament and key = 'maintenance'), false)
$function$;

-- ============================================================================
-- Admin functions (PIN-gated). p_tournament added where data is tournament-wide.
-- ============================================================================

-- ---- set result (+ knockout bracket propagation) ---------------------------
-- unchanged logic: operates by match id (globally unique); bracket rows are
-- keyed by src match id. No tournament arg needed.
-- (left as-is in the database)

-- ---- reset (DESTRUCTIVE) — now scoped to one tournament --------------------
drop function if exists public.wc_admin_reset(text, text);
create or replace function public.wc_admin_reset(
  p_pin text, p_what text, p_tournament text default 'wc26')
returns text language plpgsql security definer set search_path to 'public'
as $function$
begin
  if p_pin is distinct from '1993' then raise exception 'BAD_PIN'; end if;

  if p_what in ('predictions', 'all') then
    delete from public.wc_predictions where tournament_id = p_tournament;
  end if;

  if p_what in ('results', 'all') then
    update public.wc_matches
       set home_score = null, away_score = null, finished = false, locked = false
     where tournament_id = p_tournament;
    -- knockout slots (World Cup id range) go back to "to be decided"
    update public.wc_matches
       set home_team = null, away_team = null, home_flag = null, away_flag = null
     where tournament_id = p_tournament and id >= 17;
  end if;

  return p_what;
end;
$function$;

-- ---- rebuild bracket — scoped to one tournament ----------------------------
drop function if exists public.wc_admin_rebuild_bracket(text);
create or replace function public.wc_admin_rebuild_bracket(
  p_pin text, p_tournament text default 'wc26')
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare
  r record; m public.wc_matches; winside text;
  w_name text; w_flag text; l_name text; l_flag text; lnk record;
begin
  if p_pin is distinct from '1993' then raise exception 'BAD_PIN'; end if;
  update public.wc_matches
     set home_team = null, away_team = null, home_flag = null, away_flag = null
   where tournament_id = p_tournament and id >= 17;
  for r in select id from public.wc_matches where tournament_id = p_tournament order by id loop
    select * into m from public.wc_matches where id = r.id;
    if not m.finished then continue; end if;
    if m.home_score > m.away_score then winside := 'home';
    elsif m.away_score > m.home_score then winside := 'away';
    elsif m.home_pen is not null and m.away_pen is not null and m.home_pen <> m.away_pen then
      winside := case when m.home_pen > m.away_pen then 'home' else 'away' end;
    else winside := null; end if;
    if winside is null then continue; end if;
    if winside = 'home' then
      w_name := m.home_team; w_flag := m.home_flag; l_name := m.away_team; l_flag := m.away_flag;
    else
      w_name := m.away_team; w_flag := m.away_flag; l_name := m.home_team; l_flag := m.home_flag;
    end if;
    for lnk in select * from public.wc_bracket where src = m.id loop
      if lnk.slot = 'home' then
        update public.wc_matches set
          home_team = case when lnk.result='W' then w_name else l_name end,
          home_flag = case when lnk.result='W' then w_flag else l_flag end
        where id = lnk.dst;
      else
        update public.wc_matches set
          away_team = case when lnk.result='W' then w_name else l_name end,
          away_flag = case when lnk.result='W' then w_flag else l_flag end
        where id = lnk.dst;
      end if;
    end loop;
  end loop;
end;
$function$;

-- ---- maintenance / reveal flags — scoped to one tournament -----------------
drop function if exists public.wc_admin_set_maintenance(boolean, text);
create or replace function public.wc_admin_set_maintenance(
  p_on boolean, p_pin text, p_tournament text default 'wc26')
returns text language plpgsql security definer set search_path to 'public'
as $function$
begin
  if p_pin is distinct from '1993' then raise exception 'BAD_PIN'; end if;
  insert into public.wc_settings (tournament_id, key, value, updated_at)
  values (p_tournament, 'maintenance', case when p_on then 'on' else 'off' end, now())
  on conflict (tournament_id, key) do update set value = excluded.value, updated_at = now();
  return case when p_on then 'on' else 'off' end;
end $function$;

drop function if exists public.wc_admin_set_reveal_finals(boolean, text);
create or replace function public.wc_admin_set_reveal_finals(
  p_on boolean, p_pin text, p_tournament text default 'wc26')
returns text language plpgsql security definer set search_path to 'public'
as $function$
begin
  if p_pin is distinct from '1993' then raise exception 'BAD_PIN'; end if;
  insert into public.wc_settings (tournament_id, key, value, updated_at)
  values (p_tournament, 'reveal_finals', case when p_on then 'on' else 'off' end, now())
  on conflict (tournament_id, key) do update set value = excluded.value, updated_at = now();
  return case when p_on then 'on' else 'off' end;
end $function$;

-- ---- admin champion set/delete — scoped to one tournament ------------------
drop function if exists public.wc_admin_set_champion(text, text, text);
create or replace function public.wc_admin_set_champion(
  p_name text, p_team text, p_pin text, p_tournament text default 'wc26')
returns wc_champion_picks language plpgsql security definer set search_path to 'public'
as $function$
declare
  nm  text := nullif(btrim(p_name), '');
  tm  text := nullif(btrim(p_team), '');
  row public.wc_champion_picks;
begin
  if p_pin is distinct from '1993' then raise exception 'BAD_PIN'; end if;
  if nm is null then raise exception 'NAME_REQUIRED'; end if;
  if tm is null then raise exception 'INVALID_TEAM';  end if;
  if not exists (select 1 from public.wc_matches
                 where tournament_id = p_tournament and (home_team = tm or away_team = tm)) then
    raise exception 'INVALID_TEAM';
  end if;
  update public.wc_champion_picks set team = tm
   where tournament_id = p_tournament and player_name = nm returning * into row;
  if not found then
    insert into public.wc_champion_picks (tournament_id, player_name, team)
    values (p_tournament, nm, tm) returning * into row;
  end if;
  return row;
end;
$function$;

drop function if exists public.wc_admin_delete_champion(text, text);
create or replace function public.wc_admin_delete_champion(
  p_name text, p_pin text, p_tournament text default 'wc26')
returns integer language plpgsql security definer set search_path to 'public'
as $function$
declare n integer;
begin
  if p_pin is distinct from '1993' then raise exception 'BAD_PIN'; end if;
  delete from public.wc_champion_picks
   where tournament_id = p_tournament and player_name = btrim(p_name);
  get diagnostics n = row_count;
  return n;
end $function$;

-- ---- admin delete player — scoped to one tournament ------------------------
drop function if exists public.wc_admin_delete_player(text, text);
create or replace function public.wc_admin_delete_player(
  p_name text, p_pin text, p_tournament text default 'wc26')
returns integer language plpgsql security definer set search_path to 'public'
as $function$
declare n integer;
begin
  if p_pin is distinct from '1993' then raise exception 'BAD_PIN'; end if;
  delete from public.wc_predictions
   where tournament_id = p_tournament and player_name = btrim(p_name);
  get diagnostics n = row_count;
  return n;
end;
$function$;

-- ---- admin upsert match — set tournament + group on insert -----------------
drop function if exists public.wc_admin_upsert_match(integer, text, integer, text, text, text, text, text, timestamptz, text);
create or replace function public.wc_admin_upsert_match(
  p_id integer, p_round text, p_match_no integer,
  p_home_team text, p_home_flag text, p_away_team text, p_away_flag text,
  p_venue text, p_kickoff timestamptz, p_pin text,
  p_tournament text default 'wc26', p_group text default null)
returns void language plpgsql security definer set search_path to 'public'
as $function$
begin
  if p_pin is distinct from '1993' then raise exception 'BAD_PIN'; end if;
  insert into public.wc_matches
    (id, tournament_id, round, group_label, match_no,
     home_team, home_flag, away_team, away_flag, venue, kickoff)
  values
    (p_id, p_tournament, p_round, nullif(btrim(p_group), ''), coalesce(p_match_no, 0),
     nullif(btrim(p_home_team), ''), nullif(btrim(p_home_flag), ''),
     nullif(btrim(p_away_team), ''), nullif(btrim(p_away_flag), ''),
     nullif(btrim(p_venue), ''), p_kickoff)
  on conflict (id) do update set
    round = excluded.round, match_no = excluded.match_no,
    group_label = coalesce(excluded.group_label, wc_matches.group_label),
    home_team = case when exists(select 1 from public.wc_predictions p where p.match_id = wc_matches.id)
                     then wc_matches.home_team else excluded.home_team end,
    home_flag = case when exists(select 1 from public.wc_predictions p where p.match_id = wc_matches.id)
                     then wc_matches.home_flag else excluded.home_flag end,
    away_team = case when exists(select 1 from public.wc_predictions p where p.match_id = wc_matches.id)
                     then wc_matches.away_team else excluded.away_team end,
    away_flag = case when exists(select 1 from public.wc_predictions p where p.match_id = wc_matches.id)
                     then wc_matches.away_flag else excluded.away_flag end,
    venue = excluded.venue, kickoff = excluded.kickoff;
end;
$function$;
