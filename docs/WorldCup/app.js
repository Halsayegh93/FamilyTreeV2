// ============================================================================
// Shared logic: Supabase client, scoring, data loading.
// ============================================================================
import { SUPABASE_URL, SUPABASE_ANON_KEY, POINTS } from './config.js?v=7';
import { demo } from './demo.js?v=7';

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

// The "match day" used for grouping in the schedule — simply the kickoff's own
// LOCAL calendar date, so every match appears under the exact date it is set to
// (WYSIWYG). A live match that runs past midnight still shows because the list
// keeps started-but-unfinished matches; only the day header follows the kickoff.
export function matchDay(kickoff) {
  if (!kickoff) return null;
  return new Date(kickoff);
}

// Map a flag emoji to a flagcdn country code so flags render as real images and
// look identical on every device (incl. England/Scotland/Wales, which many
// platforms show as a plain black flag). Returns null if it's not a flag emoji.
function flagCode(s) {
  if (!s) return null;
  const cps = [...String(s)].map((c) => c.codePointAt(0));
  const ri = cps.filter((cp) => cp >= 0x1F1E6 && cp <= 0x1F1FF);   // 🇦..🇿
  if (ri.length >= 2) return String.fromCharCode(ri[0] - 0x1F1E6 + 97, ri[1] - 0x1F1E6 + 97);
  const tags = cps.filter((cp) => cp >= 0xE0061 && cp <= 0xE007A)   // subdivision tag letters
                  .map((cp) => String.fromCharCode(cp - 0xE0000)).join('');
  return ({ gbeng: 'gb-eng', gbsct: 'gb-sct', gbwls: 'gb-wls', gbnir: 'gb-nir' })[tags] || null;
}

// Flag element: every flag renders as a real <img> with the SAME look, served
// from THIS site's own /flags folder (same origin) — so it never depends on an
// external CDN that might be blocked, and the UK subdivisions (England/Scotland/
// Wales) get a proper flag instead of a black square. Falls back to the stored
// emoji only if, somehow, the image can't be found.
export function flagHTML(emoji) {
  const e = String(emoji ?? '').replace(/[&<>"]/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const code = flagCode(emoji);
  if (code) {
    return `<img class="flag-img" src="flags/${code}.svg" alt="" loading="lazy" data-fb="${e || '⚽️'}" ` +
      `onerror="this.onerror=null;const s=document.createElement('span');s.className='flag';s.textContent=this.dataset.fb;this.replaceWith(s);" />`;
  }
  return `<span class="flag">${e || '⚽️'}</span>`;
}

// Is a match closed for predictions? ------------------------------------------
export function isLocked(match) {
  if (!match) return true;
  if (match.finished || match.locked) return true;
  if (match.kickoff && new Date(match.kickoff).getTime() <= Date.now()) return true;
  return false;
}

// Score the match result on the regular-time score (before penalties):
//   5 -> exact score
//   3 -> correct winner + the winning team's goals, OR a correct (non-exact) draw
//   1 -> correct winner only (score wrong)
//   0 -> wrong outcome
export function scorePrediction(predHome, predAway, actHome, actAway) {
  if (predHome == null || predAway == null || actHome == null || actAway == null) {
    return 0;
  }
  if (predHome === actHome && predAway === actAway) return POINTS.exact;   // 5
  const po = Math.sign(predHome - predAway);
  const ao = Math.sign(actHome - actAway);
  if (po !== ao) return 0;                  // wrong outcome
  if (ao === 0) return POINTS.draw;         // correct draw, not exact -> 3
  const winnerActual = Math.max(actHome, actAway);
  const winnerPred = actHome > actAway ? predHome : predAway;
  return winnerPred === winnerActual ? POINTS.winnerScore : POINTS.winner;   // 3 or 1
}

// The shootout winner a player predicted — from the pick button (pen_pick) or
// the entered penalty score (pen_home/pen_away). Returns 'home' | 'away' | null.
function predPenSide(p) {
  if (p.pen_pick === 'home' || p.pen_pick === 'away') return p.pen_pick;
  if (p.pen_home != null && p.pen_away != null && p.pen_home !== p.pen_away)
    return p.pen_home > p.pen_away ? 'home' : 'away';
  return null;
}

// Score one prediction ROW against a match (handles winner-only picks) ---------
//   - a winner-only pick ({pick:'home'|'away'}) scores 1 if that side won, else 0
//   - a full score row is scored with scorePrediction (5 / 3 / 1 / 0)
export function scoreRow(p, m) {
  if (!m || !m.finished) return 0;
  if (p && p.manual_points != null) return p.manual_points;   // admin override
  if (p && p.pick) {
    const diff = Math.sign((m.home_score ?? 0) - (m.away_score ?? 0));
    let winSide = diff > 0 ? 'home' : diff < 0 ? 'away' : null;
    // تعادل محسوم بركلات الترجيح -> الفائز بالركلات (توقّع المتأهّل)
    if (!winSide && m.home_pen != null && m.away_pen != null && m.home_pen !== m.away_pen)
      winSide = m.home_pen > m.away_pen ? 'home' : 'away';
    if (!winSide) return 0;              // تعادل بلا حسم -> توقّع الفائز ما ياخذ نقطة
    return p.pick === winSide ? POINTS.winner : 0;
  }
  // match-result points (5 / 3 / 1 / 0) on the regular-time score
  let pts = scorePrediction(p.home_score, p.away_score, m.home_score, m.away_score);

  // A draw prediction is also judged on the WINNER the player named (via the
  // pen_pick button or the entered shootout score):
  //   Match ends a real draw and a shootout decides it:
  //     exact-score draw      -> 5, and +2 for the correct shootout winner (7 / 5)
  //     different-score draw  -> 3 if the shootout winner is right, else 0
  //   Match is decided (regular OR extra time) but the player predicted a draw:
  //     -> 3 if they named the correct eventual winner, else 0
  const predictedDraw = p.home_score != null && p.home_score === p.away_score;
  if (predictedDraw) {
    const realDraw = m.home_score === m.away_score;
    const wentToPens = m.home_pen != null && m.away_pen != null && m.home_pen !== m.away_pen;
    let actualWinner = null;
    if (!realDraw) actualWinner = m.home_score > m.away_score ? 'home' : 'away';
    else if (wentToPens) actualWinner = m.home_pen > m.away_pen ? 'home' : 'away';
    const pickCorrect = actualWinner !== null && predPenSide(p) === actualWinner;

    if (realDraw && wentToPens) {
      if (p.home_score === m.home_score) {
        if (pickCorrect) pts += POINTS.penWinner;   // exact draw: 5 -> 7
      } else {
        pts = pickCorrect ? POINTS.draw : 0;         // different-score draw: 3 / 0
      }
    } else if (!realDraw) {
      pts = pickCorrect ? POINTS.draw : 0;           // decided match: 3 / 0
    }
  }
  return pts;
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

// Full edit history of every prediction (requires the wc-history.sql migration).
// Returns null when the table doesn't exist yet (feature not activated) so the
// UI can tell "not activated" apart from "activated but empty" ([]).
export async function loadPredictionHistory() {
  if (DEMO) return [];
  const sb = await client();
  const { data, error } = await sb
    .from('wc_prediction_history')
    .select('*')
    .order('changed_at', { ascending: true });
  if (error) return null;   // table not created yet -> feature disabled
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

export async function submitPrediction(matchId, name, home, away, penHome = null, penAway = null) {
  if (DEMO) return demo.submit(matchId, name, home, away, penHome, penAway);
  const sb = await client();
  const { data, error } = await sb.rpc('wc_submit_prediction', {
    p_match_id: matchId,
    p_name: name,
    p_home: home,
    p_away: away,
    p_pen_home: penHome,
    p_pen_away: penAway,
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

// Admin: add/replace a prediction for a player on a started (not finished) match.
export async function adminAddPrediction(matchId, name, home, away, pin, penHome = null, penAway = null) {
  if (DEMO) {
    if (pin !== '1993') throw new Error('BAD_PIN');
    return demo.addPrediction(matchId, name, home, away, penHome, penAway);
  }
  const sb = await client();
  const { data, error } = await sb.rpc('wc_admin_add_prediction', {
    p_match_id: matchId, p_name: name, p_home: home, p_away: away, p_pin: pin,
    p_pen_home: penHome, p_pen_away: penAway,
  });
  if (error) throw error;
  return data;
}

// Admin: delete a single player's prediction for one match (lets them re-predict).
export async function adminDeletePrediction(matchId, name, pin) {
  if (DEMO) {
    if (pin !== '1993') throw new Error('BAD_PIN');
    return demo.deletePrediction(matchId, name);
  }
  const sb = await client();
  const { data, error } = await sb.rpc('wc_admin_delete_prediction', {
    p_match_id: matchId, p_name: name, p_pin: pin,
  });
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
      if (pts > 0) rec.correct += 1;
    }
    players.set(p.player_name, rec);
  }

  return [...players.values()].sort(
    (a, b) => b.points - a.points || b.correct - a.correct || a.name.localeCompare(b.name, 'ar'),
  );
}

// Friendly Arabic error messages for RPC failures -----------------------------
export function friendlyError(err) {
  const msg = (err && err.message) || String(err);
  if (msg.includes('MATCH_FINISHED')) return 'المباراة خلصت — ما يمكن إضافة توقّع';
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
