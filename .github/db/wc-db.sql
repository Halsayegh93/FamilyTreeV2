-- ============================================================================
-- World Cup 2026 Prediction Site — Supabase setup
-- ============================================================================
-- HOW TO USE:
--   1) Open your Supabase project  →  SQL Editor  →  New query
--   2) Paste this ENTIRE file and press Run
--   3) IMPORTANT: change the admin PIN below (search for 'CHANGE_ME')
--   4) Copy your project URL + anon (publishable) key into config.js
--
-- This script is standalone. It only creates objects prefixed with `wc_`
-- and does not touch any other tables in your database.
-- ============================================================================

-- ---------- Tables ----------------------------------------------------------

create table if not exists public.wc_matches (
  id         integer primary key,           -- match number (1..32)
  round      text    not null,              -- R32 | R16 | QF | SF | 3RD | FINAL
  match_no   integer not null,              -- ordering within a round
  home_team  text,                          -- null until the team is known
  away_team  text,
  home_flag  text,                          -- optional emoji/code
  away_flag  text,
  venue      text,                          -- stadium / city
  kickoff    timestamptz,                   -- optional; locks predictions once passed
  home_score integer,                       -- actual result (admin only)
  away_score integer,
  finished   boolean not null default false,
  locked     boolean not null default false -- admin can lock predictions early
);

create table if not exists public.wc_predictions (
  id          uuid primary key default gen_random_uuid(),
  match_id    integer not null references public.wc_matches(id) on delete cascade,
  player_name text    not null,
  home_score  integer,                     -- null for a winner-only pick
  away_score  integer,                     -- null for a winner-only pick
  pick        text check (pick in ('home','away')),  -- set for winner-only picks
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (match_id, player_name)
);

-- Upgrade older installs: allow winner-only rows (scores nullable + pick column).
alter table public.wc_predictions alter column home_score drop not null;
alter table public.wc_predictions alter column away_score drop not null;
alter table public.wc_predictions add column if not exists pick text;
do $$ begin
  alter table public.wc_predictions
    add constraint wc_predictions_pick_chk check (pick in ('home','away'));
exception when duplicate_object then null; end $$;

create index if not exists wc_predictions_match_idx  on public.wc_predictions(match_id);
create index if not exists wc_predictions_player_idx on public.wc_predictions(lower(player_name));

-- ---------- Bracket links ---------------------------------------------------
-- How teams advance: when match `src` finishes, the WINNER (result='W') or the
-- LOSER (result='L') is copied into `dst` at slot 'home' or 'away'. This is what
-- auto-fills later rounds, so the admin only ever enters scores.

create table if not exists public.wc_bracket (
  src    integer not null,
  result text    not null check (result in ('W','L')),
  dst    integer not null,
  slot   text    not null check (slot in ('home','away')),
  primary key (src, result)
);

insert into public.wc_bracket (src, result, dst, slot) values
  -- Round of 32 winners -> Round of 16
  (1,'W',17,'home'),(2,'W',17,'away'),
  (3,'W',18,'home'),(4,'W',18,'away'),
  (5,'W',19,'home'),(6,'W',19,'away'),
  (7,'W',20,'home'),(8,'W',20,'away'),
  (9,'W',21,'home'),(10,'W',21,'away'),
  (11,'W',22,'home'),(12,'W',22,'away'),
  (13,'W',23,'home'),(14,'W',23,'away'),
  (15,'W',24,'home'),(16,'W',24,'away'),
  -- Round of 16 winners -> Quarter-finals
  (17,'W',25,'home'),(18,'W',25,'away'),
  (19,'W',26,'home'),(20,'W',26,'away'),
  (21,'W',27,'home'),(22,'W',27,'away'),
  (23,'W',28,'home'),(24,'W',28,'away'),
  -- Quarter-final winners -> Semi-finals
  (25,'W',29,'home'),(26,'W',29,'away'),
  (27,'W',30,'home'),(28,'W',30,'away'),
  -- Semi-final winners -> Final, losers -> Third place
  (29,'W',32,'home'),(30,'W',32,'away'),
  (29,'L',31,'home'),(30,'L',31,'away')
on conflict (src, result) do nothing;

-- ---------- Row Level Security ---------------------------------------------
-- Everyone (anon) may READ. Nobody may write directly.
-- All writes go through the SECURITY DEFINER functions below, which enforce
-- the locking rules and the admin PIN server-side.

alter table public.wc_matches     enable row level security;
alter table public.wc_predictions enable row level security;

drop policy if exists wc_matches_read     on public.wc_matches;
drop policy if exists wc_predictions_read  on public.wc_predictions;

create policy wc_matches_read    on public.wc_matches     for select using (true);
create policy wc_predictions_read on public.wc_predictions for select using (true);

-- Enable Realtime so the site auto-updates when results/predictions change.
do $$ begin
  alter publication supabase_realtime add table public.wc_matches;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.wc_predictions;
exception when duplicate_object then null; end $$;

-- ---------- Submit a prediction (public) ------------------------------------
-- Rejects the submission if the match is finished, locked, or kicked off.

create or replace function public.wc_submit_prediction(
  p_match_id integer,
  p_name     text,
  p_home     integer,
  p_away     integer
) returns public.wc_predictions
language plpgsql security definer set search_path = public as $$
declare
  m   public.wc_matches;
  row public.wc_predictions;
  nm  text := nullif(btrim(p_name), '');
begin
  if nm is null then
    raise exception 'NAME_REQUIRED';
  end if;
  if p_home is null or p_away is null or p_home < 0 or p_away < 0
     or p_home > 99 or p_away > 99 then
    raise exception 'INVALID_SCORE';
  end if;

  select * into m from public.wc_matches where id = p_match_id;
  if not found then
    raise exception 'MATCH_NOT_FOUND';
  end if;
  if m.finished or m.locked
     or (m.kickoff is not null and m.kickoff <= now()) then
    raise exception 'MATCH_LOCKED';
  end if;

  insert into public.wc_predictions (match_id, player_name, home_score, away_score, pick)
  values (p_match_id, nm, p_home, p_away, null)
  on conflict (match_id, player_name)
  do update set home_score = excluded.home_score,
               away_score = excluded.away_score,
               pick       = null,
               updated_at = now()
  returning * into row;

  return row;
end;
$$;

-- ---------- Submit a WINNER-ONLY pick (public) ------------------------------
-- A quick prediction of who wins (1 point) without entering a score.
create or replace function public.wc_submit_winner(
  p_match_id integer,
  p_name     text,
  p_pick     text
) returns public.wc_predictions
language plpgsql security definer set search_path = public as $$
declare
  m   public.wc_matches;
  row public.wc_predictions;
  nm  text := nullif(btrim(p_name), '');
begin
  if nm is null then
    raise exception 'NAME_REQUIRED';
  end if;
  if p_pick is null or p_pick not in ('home','away') then
    raise exception 'INVALID_PICK';
  end if;

  select * into m from public.wc_matches where id = p_match_id;
  if not found then
    raise exception 'MATCH_NOT_FOUND';
  end if;
  if m.finished or m.locked
     or (m.kickoff is not null and m.kickoff <= now()) then
    raise exception 'MATCH_LOCKED';
  end if;

  insert into public.wc_predictions (match_id, player_name, home_score, away_score, pick)
  values (p_match_id, nm, null, null, p_pick)
  on conflict (match_id, player_name)
  do update set home_score = null,
               away_score = null,
               pick       = excluded.pick,
               updated_at = now()
  returning * into row;

  return row;
end;
$$;

-- ---------- Admin: set the official result ----------------------------------

-- p_winner: 'home' | 'away' | null. Only needed to break a draw (penalties).
create or replace function public.wc_admin_set_result(
  p_match_id integer,
  p_home     integer,
  p_away     integer,
  p_pin      text,
  p_winner   text default null
) returns public.wc_matches
language plpgsql security definer set search_path = public as $$
declare
  row     public.wc_matches;
  winside text;   -- 'home' | 'away' | null
  lnk     record;
  w_name  text; w_flag text; l_name text; l_flag text;
begin
  -- CHANGE_ME: set your admin PIN here. The PIN is validated server-side only.
  if p_pin is distinct from '1993' then
    raise exception 'BAD_PIN';
  end if;

  if p_home is not null and (p_home < 0 or p_home > 99) then
    raise exception 'INVALID_SCORE';
  end if;
  if p_away is not null and (p_away < 0 or p_away > 99) then
    raise exception 'INVALID_SCORE';
  end if;

  update public.wc_matches
     set home_score = p_home,
         away_score = p_away,
         finished   = (p_home is not null and p_away is not null),
         locked     = locked or (p_home is not null and p_away is not null)
   where id = p_match_id
   returning * into row;

  if not found then
    raise exception 'MATCH_NOT_FOUND';
  end if;

  -- Decide the winning side (for bracket progression).
  if row.finished then
    if p_home > p_away then winside := 'home';
    elsif p_away > p_home then winside := 'away';
    elsif p_winner in ('home','away') then winside := p_winner;  -- penalties
    else winside := null;                                        -- draw, undecided
    end if;
  end if;

  -- Propagate winner / loser into the next matches.
  if winside is not null then
    if winside = 'home' then
      w_name := row.home_team; w_flag := row.home_flag;
      l_name := row.away_team; l_flag := row.away_flag;
    else
      w_name := row.away_team; w_flag := row.away_flag;
      l_name := row.home_team; l_flag := row.home_flag;
    end if;

    for lnk in select * from public.wc_bracket where src = p_match_id loop
      if lnk.slot = 'home' then
        update public.wc_matches
           set home_team = case when lnk.result='W' then w_name else l_name end,
               home_flag = case when lnk.result='W' then w_flag else l_flag end
         where id = lnk.dst;
      else
        update public.wc_matches
           set away_team = case when lnk.result='W' then w_name else l_name end,
               away_flag = case when lnk.result='W' then w_flag else l_flag end
         where id = lnk.dst;
      end if;
    end loop;
  end if;

  return row;
end;
$$;

-- ---------- Admin: edit teams / kickoff / lock ------------------------------

create or replace function public.wc_admin_save_match(
  p_match_id  integer,
  p_home_team text,
  p_away_team text,
  p_home_flag text,
  p_away_flag text,
  p_venue     text,
  p_kickoff   timestamptz,
  p_locked    boolean,
  p_pin       text
) returns public.wc_matches
language plpgsql security definer set search_path = public as $$
declare
  row public.wc_matches;
  has_preds boolean;
begin
  if p_pin is distinct from '1993' then       -- CHANGE_ME: same PIN as above
    raise exception 'BAD_PIN';
  end if;

  -- Once anyone has predicted this match, FREEZE the team identities/orientation
  -- so the auto-fetch can't swap home/away under the players (which would corrupt
  -- scoring). Kickoff/venue/lock still update.
  select exists(select 1 from public.wc_predictions where match_id = p_match_id) into has_preds;

  update public.wc_matches
     set home_team = case when has_preds then home_team else nullif(btrim(p_home_team), '') end,
         away_team = case when has_preds then away_team else nullif(btrim(p_away_team), '') end,
         home_flag = case when has_preds then home_flag else nullif(btrim(p_home_flag), '') end,
         away_flag = case when has_preds then away_flag else nullif(btrim(p_away_flag), '') end,
         venue     = nullif(btrim(p_venue), ''),
         kickoff   = p_kickoff,
         locked    = coalesce(p_locked, locked)
   where id = p_match_id
   returning * into row;

  if not found then
    raise exception 'MATCH_NOT_FOUND';
  end if;
  return row;
end;
$$;

-- ---------- Admin: reset (zero the counter) ---------------------------------
-- p_what: 'predictions' (delete everyone's predictions) | 'results' (clear all
-- official results + reset later-round teams) | 'all' (both).
create or replace function public.wc_admin_reset(p_pin text, p_what text)
returns text
language plpgsql security definer set search_path = public as $$
begin
  if p_pin is distinct from '1993' then          -- CHANGE_ME: same admin PIN
    raise exception 'BAD_PIN';
  end if;

  if p_what in ('predictions', 'all') then
    delete from public.wc_predictions where true;   -- WHERE required by safe-update mode
  end if;

  if p_what in ('results', 'all') then
    update public.wc_matches
       set home_score = null, away_score = null, finished = false, locked = false
     where true;                                     -- WHERE required by safe-update mode
    -- rounds after the Round of 32 go back to "to be decided"
    update public.wc_matches
       set home_team = null, away_team = null, home_flag = null, away_flag = null
     where id >= 17;
  end if;

  return p_what;
end;
$$;

-- ---------- Admin: upsert a match (create or update) ------------------------
-- Used by the auto-fetch to add group-stage matches (and any new matches) that
-- are not part of the pre-seeded 32 knockout rows.
create or replace function public.wc_admin_upsert_match(
  p_id integer, p_round text, p_match_no integer,
  p_home_team text, p_home_flag text, p_away_team text, p_away_flag text,
  p_venue text, p_kickoff timestamptz, p_pin text
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_pin is distinct from '1993' then          -- CHANGE_ME: same admin PIN
    raise exception 'BAD_PIN';
  end if;
  insert into public.wc_matches
    (id, round, match_no, home_team, home_flag, away_team, away_flag, venue, kickoff)
  values
    (p_id, p_round, coalesce(p_match_no, 0),
     nullif(btrim(p_home_team), ''), nullif(btrim(p_home_flag), ''),
     nullif(btrim(p_away_team), ''), nullif(btrim(p_away_flag), ''),
     nullif(btrim(p_venue), ''), p_kickoff)
  on conflict (id) do update set
    round = excluded.round, match_no = excluded.match_no,
    -- freeze team identities once the match has predictions (see save_match)
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
$$;

-- ---------- Admin: re-open a finished match (undo its result) ---------------
-- Clears the result + unlocks the match so it shows in the schedule again.
create or replace function public.wc_admin_reopen_match(p_match_id integer, p_pin text)
returns public.wc_matches
language plpgsql security definer set search_path = public as $$
declare row public.wc_matches;
begin
  if p_pin is distinct from '1993' then          -- CHANGE_ME: same admin PIN
    raise exception 'BAD_PIN';
  end if;
  update public.wc_matches
     set home_score = null, away_score = null, finished = false, locked = false
   where id = p_match_id
   returning * into row;
  if not found then
    raise exception 'MATCH_NOT_FOUND';
  end if;
  return row;
end;
$$;

-- ---------- Admin: delete one player from the leaderboard -------------------
create or replace function public.wc_admin_delete_player(p_name text, p_pin text)
returns integer
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if p_pin is distinct from '1993' then          -- CHANGE_ME: same admin PIN
    raise exception 'BAD_PIN';
  end if;
  delete from public.wc_predictions where player_name = btrim(p_name);
  get diagnostics n = row_count;
  return n;
end;
$$;

grant execute on function public.wc_submit_prediction(integer, text, integer, integer) to anon, authenticated;
grant execute on function public.wc_submit_winner(integer, text, text) to anon, authenticated;
grant execute on function public.wc_admin_reopen_match(integer, text) to anon, authenticated;
grant execute on function public.wc_admin_set_result(integer, integer, integer, text, text) to anon, authenticated;
grant execute on function public.wc_admin_save_match(integer, text, text, text, text, text, timestamptz, boolean, text) to anon, authenticated;
grant execute on function public.wc_admin_reset(text, text) to anon, authenticated;
grant execute on function public.wc_admin_upsert_match(integer, text, integer, text, text, text, text, text, timestamptz, text) to anon, authenticated;
grant execute on function public.wc_admin_delete_player(text, text) to anon, authenticated;

-- ---------- Seed the 32 knockout matches ------------------------------------
-- Real FIFA World Cup 2026 knockout SCHEDULE (dates + host venues).
-- Team names are left empty on purpose: the Round-of-32 matchups are only
-- finalised once the group stage ends (27 June 2026). Fill team names from the
-- Admin page as groups conclude. Dates/venues below are a starting point —
-- adjust exact kickoff times from the Admin page if needed.
-- Times are stored in UTC; tweak per match in the panel.

-- Round of 32: real official dates + venues. Teams are left "to be decided" —
-- the real matchups are only known once the group stage ends, so the admin sets
-- them from the panel; later rounds then auto-fill from results.
insert into public.wc_matches (id, round, match_no, venue, kickoff) values
  (1, 'R32', 1,  'SoFi Stadium, Los Angeles',          '2026-06-28 20:00+00'),
  (2, 'R32', 2,  'Estadio Azteca, Mexico City',        '2026-06-28 23:00+00'),
  (3, 'R32', 3,  'NRG Stadium, Houston',               '2026-06-29 20:00+00'),
  (4, 'R32', 4,  'Gillette Stadium, Boston',           '2026-06-29 23:00+00'),
  (5, 'R32', 5,  'Estadio BBVA, Monterrey',            '2026-06-30 18:00+00'),
  (6, 'R32', 6,  'AT&T Stadium, Dallas',               '2026-06-30 21:00+00'),
  (7, 'R32', 7,  'MetLife Stadium, New York/NJ',       '2026-06-30 23:00+00'),
  (8, 'R32', 8,  'Estadio Azteca, Mexico City',        '2026-07-01 18:00+00'),
  (9, 'R32', 9,  'Mercedes-Benz Stadium, Atlanta',     '2026-07-01 21:00+00'),
  (10,'R32', 10, 'Lumen Field, Seattle',               '2026-07-01 23:00+00'),
  (11,'R32', 11, 'Levi''s Stadium, San Francisco Bay', '2026-07-02 20:00+00'),
  (12,'R32', 12, 'SoFi Stadium, Los Angeles',          '2026-07-02 23:00+00'),
  (13,'R32', 13, 'BMO Field, Toronto',                 '2026-07-02 20:00+00'),
  (14,'R32', 14, 'BC Place, Vancouver',                '2026-07-03 22:00+00'),
  (15,'R32', 15, 'Hard Rock Stadium, Miami',           '2026-07-03 20:00+00'),
  (16,'R32', 16, 'Arrowhead Stadium, Kansas City',     '2026-07-03 23:00+00'),
  -- Round of 16 → Final: teams fill in automatically as results are entered.
  (17,'R16', 1, 'Lincoln Financial Field, Philadelphia','2026-07-04 20:00+00'),
  (18,'R16', 2, 'NRG Stadium, Houston',                 '2026-07-04 23:00+00'),
  (19,'R16', 3, 'AT&T Stadium, Dallas',                 '2026-07-05 20:00+00'),
  (20,'R16', 4, 'Lumen Field, Seattle',                 '2026-07-05 23:00+00'),
  (21,'R16', 5, 'Mercedes-Benz Stadium, Atlanta',       '2026-07-06 20:00+00'),
  (22,'R16', 6, 'SoFi Stadium, Los Angeles',            '2026-07-06 23:00+00'),
  (23,'R16', 7, 'Gillette Stadium, Boston',             '2026-07-07 20:00+00'),
  (24,'R16', 8, 'Arrowhead Stadium, Kansas City',       '2026-07-07 23:00+00'),
  (25,'QF', 1, 'Gillette Stadium, Boston',          '2026-07-09 21:00+00'),
  (26,'QF', 2, 'SoFi Stadium, Los Angeles',         '2026-07-10 23:00+00'),
  (27,'QF', 3, 'Arrowhead Stadium, Kansas City',    '2026-07-10 20:00+00'),
  (28,'QF', 4, 'Hard Rock Stadium, Miami',          '2026-07-11 20:00+00'),
  (29,'SF', 1, 'AT&T Stadium, Dallas',              '2026-07-14 23:00+00'),
  (30,'SF', 2, 'Mercedes-Benz Stadium, Atlanta',    '2026-07-15 23:00+00'),
  (31,'3RD', 1, 'Hard Rock Stadium, Miami',         '2026-07-18 20:00+00'),
  (32,'FINAL', 1, 'MetLife Stadium, New York/NJ',   '2026-07-19 19:00+00')
on conflict (id) do nothing;

-- Force PostgREST to pick up the new functions immediately (so the reset and
-- other RPCs work right after running this file).
notify pgrst, 'reload schema';
