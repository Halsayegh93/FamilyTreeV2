// ============================================================================
// Shared logic: Supabase client, scoring, data loading.
// ============================================================================
import { SUPABASE_URL, SUPABASE_ANON_KEY, POINTS } from './config.js?v=3';
import { demo } from './demo.js?v=3';

export { POINTS };

export const isConfigured =
  SUPABASE_URL && !SUPABASE_URL.includes('YOUR-PROJECT') &&
  SUPABASE_ANON_KEY && !SUPABASE_ANON_KEY.includes('YOUR-');

// In demo mode we skip the real client entirely (no network needed).
export const DEMO = !isConfigured;

// The Supabase library is loaded lazily, only when a real backend is used.
// This keeps demo mode fully offline.
let _client = null;
async function client() {
  if (_client) return _client;
  const { createClient } = await import('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm');
  _client = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  return _client;
}

// Round metadata (Arabic labels + display order) ------------------------------
export const ROUNDS = {
  R32:   { label: 'دور الـ32',           order: 1 },
  R16:   { label: 'دور الـ16',           order: 2 },
  QF:    { label: 'ربع النهائي',         order: 3 },
  SF:    { label: 'نصف النهائي',         order: 4 },
  '3RD': { label: 'تحديد المركز الثالث', order: 5 },
  FINAL: { label: 'النهائي',             order: 6 },
};

export function roundLabel(code) {
  return (ROUNDS[code] && ROUNDS[code].label) || code;
}

// Is a match closed for predictions? ------------------------------------------
export function isLocked(match) {
  if (!match) return true;
  if (match.finished || match.locked) return true;
  if (match.kickoff && new Date(match.kickoff).getTime() <= Date.now()) return true;
  return false;
}

// Score a single prediction against the actual result (highest tier wins) -----
//   5 -> exact score (both teams correct, draws included e.g. 3-3)
//   3 -> correct winning team + the winning team's goals correct
//   1 -> correct winning team only
//   0 -> wrong outcome — AND any non-exact draw (a draw has no winning team,
//        so the 3/1 tiers, which require correctly picking the winner, can't apply)
export function scorePrediction(predHome, predAway, actHome, actAway) {
  if (predHome == null || predAway == null || actHome == null || actAway == null) {
    return 0;
  }
  if (predHome === actHome && predAway === actAway) return POINTS.exact;

  const po = Math.sign(predHome - predAway);
  const ao = Math.sign(actHome - actAway);
  if (po !== ao) return 0; // wrong winner / wrong outcome
  if (ao === 0) return 0;  // correct draw but wrong score -> no winning team to credit

  // There is a winner and we predicted the right side. Did we also nail the
  // winning team's goal count?
  const winnerActual = Math.max(actHome, actAway);
  const winnerPred = actHome > actAway ? predHome : predAway;
  if (winnerPred === winnerActual) return POINTS.winnerScore;
  return POINTS.winner; // correct winning team only
}

// Score one prediction ROW against a match (handles winner-only picks) ---------
//   - a winner-only pick ({pick:'home'|'away'}) scores 1 if that side won, else 0
//   - a full score row is scored with scorePrediction (5/3/1/0)
export function scoreRow(p, m) {
  if (!m || !m.finished) return 0;
  if (p && p.manual_points != null) return p.manual_points;   // admin override
  if (p && p.pick) {
    const diff = Math.sign((m.home_score ?? 0) - (m.away_score ?? 0));
    if (diff === 0) return 0;            // draw -> winner-only pick can't win
    const winSide = diff > 0 ? 'home' : 'away';
    return p.pick === winSide ? POINTS.winner : 0;
  }
  return scorePrediction(p.home_score, p.away_score, m.home_score, m.away_score);
}

// Data loading ----------------------------------------------------------------
export async function loadMatches() {
  if (DEMO) return demo.matches();
  const sb = await client();
  const { data, error } = await sb
    .from('wc_matches')
    .select('*')
    .order('id', { ascending: true });
  if (error) throw error;
  return data || [];
}

export async function loadPredictions() {
  if (DEMO) return demo.predictions();
  const sb = await client();
  const { data, error } = await sb
    .from('wc_predictions')
    .select('*');
  if (error) throw error;
  return data || [];
}

export async function loadMyPredictions(name) {
  if (!name) return [];
  if (DEMO) return demo.myPredictions(name);
  const sb = await client();
  const { data, error } = await sb
    .from('wc_predictions')
    .select('*')
    .eq('player_name', name);
  if (error) throw error;
  return data || [];
}

export async function submitPrediction(matchId, name, home, away) {
  if (DEMO) return demo.submit(matchId, name, home, away);
  const sb = await client();
  const { data, error } = await sb.rpc('wc_submit_prediction', {
    p_match_id: matchId,
    p_name: name,
    p_home: home,
    p_away: away,
  });
  if (error) throw error;
  return data;
}

// Submit a winner-only prediction (1 point if the picked side wins) -----------
export async function submitWinner(matchId, name, pick) {
  if (DEMO) return demo.submitWinner(matchId, name, pick);
  const sb = await client();
  const { data, error } = await sb.rpc('wc_submit_winner', {
    p_match_id: matchId,
    p_name: name,
    p_pick: pick,
  });
  if (error) throw error;
  return data;
}

// Admin operations (demo-aware) -----------------------------------------------
export async function adminSetResult(matchId, home, away, pin, winner = null, homePen = null, awayPen = null) {
  if (DEMO) {
    if (pin !== '1993') throw new Error('BAD_PIN');
    return demo.setResult(matchId, home, away, winner, homePen, awayPen);
  }
  const sb = await client();
  const { data, error } = await sb.rpc('wc_admin_set_result', {
    p_match_id: matchId, p_home: home, p_away: away, p_pin: pin, p_winner: winner,
    p_home_pen: homePen, p_away_pen: awayPen,
  });
  if (error) throw error;
  return data;
}

export async function adminSaveMatch(matchId, fields, pin) {
  if (DEMO) {
    if (pin !== '1993') throw new Error('BAD_PIN');
    return demo.saveMatch(matchId, fields);
  }
  const sb = await client();
  const { data, error } = await sb.rpc('wc_admin_save_match', {
    p_match_id: matchId,
    p_home_team: fields.home_team,
    p_away_team: fields.away_team,
    p_home_flag: fields.home_flag,
    p_away_flag: fields.away_flag,
    p_venue: fields.venue ?? null,
    p_kickoff: fields.kickoff ?? null,
    p_locked: fields.locked ?? null,
    p_pin: pin,
  });
  if (error) throw error;
  return data;
}

// Admin reset — wipe predictions and/or results.
export async function adminReset(what, pin) {
  if (DEMO) {
    if (pin !== '1993') throw new Error('BAD_PIN');
    return demo.resetWhat(what);
  }
  const sb = await client();
  const { data, error } = await sb.rpc('wc_admin_reset', { p_pin: pin, p_what: what });
  if (error) throw error;
  return data;
}

// Admin: re-open a finished match (clear its result, show it again).
export async function adminReopenMatch(matchId, pin) {
  if (DEMO) {
    if (pin !== '1993') throw new Error('BAD_PIN');
    return demo.reopenMatch(matchId);
  }
  const sb = await client();
  const { data, error } = await sb.rpc('wc_admin_reopen_match', {
    p_match_id: matchId, p_pin: pin,
  });
  if (error) throw error;
  return data;
}

// Admin: manually set/override a player's points for a match (null = auto).
export async function adminSetPoints(matchId, name, points, pin) {
  if (DEMO) {
    if (pin !== '1993') throw new Error('BAD_PIN');
    return demo.setPoints(matchId, name, points);
  }
  const sb = await client();
  const { data, error } = await sb.rpc('wc_admin_set_points', {
    p_match_id: matchId, p_name: name, p_points: points, p_pin: pin,
  });
  if (error) throw error;
  return data;
}

// Admin: delete one player's predictions (remove them from the leaderboard).
export async function adminDeletePlayer(name, pin) {
  if (DEMO) {
    if (pin !== '1993') throw new Error('BAD_PIN');
    return demo.deletePlayer(name);
  }
  const sb = await client();
  const { data, error } = await sb.rpc('wc_admin_delete_player', { p_name: name, p_pin: pin });
  if (error) throw error;
  return data;
}

// Verify the admin PIN without mutating anything.
export async function adminVerifyPin(pin) {
  if (DEMO) return pin === '1993';
  const sb = await client();
  const { error } = await sb.rpc('wc_admin_set_result', {
    p_match_id: 0, p_home: null, p_away: null, p_pin: pin,
  });
  const msg = (error && error.message) || '';
  if (msg.includes('BAD_PIN')) return false;
  return true; // MATCH_NOT_FOUND (expected) or no error => PIN accepted
}

// Auto-update: call `onChange` whenever matches or predictions change ----------
// Real mode uses Supabase Realtime; demo mode listens for cross-tab storage
// events. A periodic poll backs both up. Returns an unsubscribe function.
export function watch(onChange, pollMs = 20000) {
  const timer = setInterval(onChange, pollMs);

  if (DEMO) {
    const h = (e) => { if (!e.key || e.key.indexOf('wc_demo_') === 0) onChange(); };
    window.addEventListener('storage', h);
    return () => { clearInterval(timer); window.removeEventListener('storage', h); };
  }

  let channel = null;
  client().then((sb) => {
    channel = sb.channel('wc-changes')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'wc_matches' }, onChange)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'wc_predictions' }, onChange)
      .subscribe();
  }).catch(() => {});
  return () => { clearInterval(timer); if (channel) channel.unsubscribe(); };
}

// Build the leaderboard from predictions + finished matches -------------------
// rec: { name, points, exact, correct, played, predicted }
//   predicted = total matches the player predicted (any status)
//   played    = how many of those have finished (counted toward points)
export function buildLeaderboard(matches, predictions) {
  const byId = new Map(matches.map((m) => [m.id, m]));
  const players = new Map();

  for (const p of predictions) {
    const m = byId.get(p.match_id);
    const rec = players.get(p.player_name) || {
      name: p.player_name, points: 0, exact: 0, correct: 0, played: 0, predicted: 0,
    };
    rec.predicted += 1;                 // every prediction counts here
    if (m && m.finished) {
      const pts = scoreRow(p, m);
      rec.points += pts;
      rec.played += 1;
      if (pts === POINTS.exact) rec.exact += 1;
      if (pts > 0) rec.correct += 1;
    }
    players.set(p.player_name, rec);
  }

  return [...players.values()].sort(
    (a, b) => b.points - a.points || b.exact - a.exact || a.name.localeCompare(b.name, 'ar'),
  );
}

// Friendly Arabic error messages for RPC failures -----------------------------
export function friendlyError(err) {
  const msg = (err && err.message) || String(err);
  if (msg.includes('MATCH_LOCKED'))   return 'انتهى وقت التوقع لهذه المباراة 🔒';
  if (msg.includes('NAME_REQUIRED'))  return 'اكتب اسمك أول';
  if (msg.includes('INVALID_SCORE'))  return 'النتيجة غير صحيحة';
  if (msg.includes('INVALID_PICK'))   return 'اختر الفريق الفائز';
  if (msg.includes('BAD_PIN'))        return 'كلمة السر غير صحيحة';
  if (msg.includes('MATCH_NOT_FOUND'))return 'المباراة غير موجودة';
  if (msg.includes('PGRST202') || msg.includes('Could not find the function') ||
      msg.includes('schema cache') || msg.includes('wc_admin_reset'))
    return 'لازم تشغّل db.sql في Supabase أول (الدالة غير موجودة بعد) 🔧';
  return msg;
}
