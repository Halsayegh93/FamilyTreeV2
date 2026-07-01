-- ============================================================================
-- World Cup 2026 — Prediction EDIT HISTORY (سجل تعديلات التوقّعات)
-- ============================================================================
-- HOW TO USE:
--   1) Supabase → SQL Editor → New query
--   2) Paste this ENTIRE file → Run
--   3) From now on every change to a prediction (create/edit) is logged with
--      its exact time, so the transparency page can show old → new.
--
-- Safe to run more than once (idempotent). Standalone — only touches wc_* objects.
-- NOTE: history starts recording from the moment you run this. Edits made
--       BEFORE running it were never captured and cannot be recovered.
-- ============================================================================

-- ---------- History table ---------------------------------------------------
create table if not exists public.wc_prediction_history (
  id          uuid primary key default gen_random_uuid(),
  match_id    integer not null,
  player_name text    not null,
  home_score  integer,
  away_score  integer,
  pick        text,
  pen_pick    text,
  pen_home    integer,
  pen_away    integer,
  action      text    not null,                    -- 'created' | 'updated'
  changed_at  timestamptz not null default now()
);

create index if not exists wc_prediction_history_lookup_idx
  on public.wc_prediction_history (match_id, player_name, changed_at);

-- ---------- Read access (public read, no client writes) ---------------------
alter table public.wc_prediction_history enable row level security;
drop policy if exists wc_prediction_history_read on public.wc_prediction_history;
create policy wc_prediction_history_read
  on public.wc_prediction_history for select using (true);
grant select on public.wc_prediction_history to anon, authenticated;

-- ---------- Trigger: snapshot a row on every real prediction change ----------
create or replace function public.wc_log_prediction_change()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into public.wc_prediction_history
      (match_id, player_name, home_score, away_score, pick,
       pen_pick, pen_home, pen_away, action, changed_at)
    values
      (new.match_id, new.player_name, new.home_score, new.away_score, new.pick,
       new.pen_pick, new.pen_home, new.pen_away, 'created', now());
    return new;
  end if;

  -- UPDATE: only log when the PREDICTION itself changed
  -- (ignore admin manual_points edits and plain updated_at bumps)
  if new.home_score is distinct from old.home_score
     or new.away_score is distinct from old.away_score
     or new.pick      is distinct from old.pick
     or new.pen_pick  is distinct from old.pen_pick
     or new.pen_home  is distinct from old.pen_home
     or new.pen_away  is distinct from old.pen_away then
    insert into public.wc_prediction_history
      (match_id, player_name, home_score, away_score, pick,
       pen_pick, pen_home, pen_away, action, changed_at)
    values
      (new.match_id, new.player_name, new.home_score, new.away_score, new.pick,
       new.pen_pick, new.pen_home, new.pen_away, 'updated', now());
  end if;
  return new;
end;
$$;

drop trigger if exists wc_predictions_history_trg on public.wc_predictions;
create trigger wc_predictions_history_trg
  after insert or update on public.wc_predictions
  for each row execute function public.wc_log_prediction_change();

-- ---------- Seed a baseline for predictions that already exist ---------------
-- Records each current prediction once (as 'created') using its original
-- created_at, so the history isn't empty for predictions made before this ran.
insert into public.wc_prediction_history
  (match_id, player_name, home_score, away_score, pick,
   pen_pick, pen_home, pen_away, action, changed_at)
select p.match_id, p.player_name, p.home_score, p.away_score, p.pick,
       p.pen_pick, p.pen_home, p.pen_away, 'created', coalesce(p.created_at, now())
from public.wc_predictions p
where not exists (
  select 1 from public.wc_prediction_history h
  where h.match_id = p.match_id and h.player_name = p.player_name
);

-- Done. The transparency page will read wc_prediction_history automatically.
