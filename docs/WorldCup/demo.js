// ============================================================================
// Demo mode — runs automatically when config.js is not filled in yet.
// Sample matches + predictions stored in localStorage so you can preview the
// whole site (predictions, leaderboard, admin, auto-advancing bracket) without
// a Supabase project. Once you fill in config.js it switches to the real backend.
// ============================================================================

// Bracket links: when `src` finishes, the winner (W) / loser (L) is copied into
// `dst` at the given slot — this is what auto-fills the later rounds.
// Official FIFA World Cup 2026 knockout bracket (matches numbered 1..16 = R32,
// 17..24 = R16, 25..28 = QF, 29..30 = SF, 31 = 3rd, 32 = Final). The R32→R16
// feed is NOT adjacent: it follows the real bracket (e.g. R16 #17 = W2 vs W5).
export const BRACKET = [
  // R32 winners -> R16
  [2,'W',17,'home'],[5,'W',17,'away'],
  [1,'W',18,'home'],[3,'W',18,'away'],
  [4,'W',19,'home'],[6,'W',19,'away'],
  [7,'W',20,'home'],[8,'W',20,'away'],
  [11,'W',21,'home'],[12,'W',21,'away'],
  [9,'W',22,'home'],[10,'W',22,'away'],
  [14,'W',23,'home'],[16,'W',23,'away'],
  [13,'W',24,'home'],[15,'W',24,'away'],
  // R16 winners -> QF
  [17,'W',25,'home'],[18,'W',25,'away'],
  [21,'W',26,'home'],[22,'W',26,'away'],
  [19,'W',27,'home'],[20,'W',27,'away'],
  [23,'W',28,'home'],[24,'W',28,'away'],
  // QF winners -> SF
  [25,'W',29,'home'],[26,'W',29,'away'],
  [27,'W',30,'home'],[28,'W',30,'away'],
  // SF winners -> Final, losers -> 3rd place
  [29,'W',32,'home'],[30,'W',32,'away'],
  [29,'L',31,'home'],[30,'L',31,'away'],
];

// Round of 32 — teams + flags + venues (same data the real db.sql seeds).
const R32 = [
  ['البرازيل','🇧🇷','كوريا الجنوبية','🇰🇷','SoFi Stadium, Los Angeles','2026-06-28T20:00:00Z'],
  ['الأرجنتين','🇦🇷','نيجيريا','🇳🇬','Estadio Azteca, Mexico City','2026-06-28T23:00:00Z'],
  ['فرنسا','🇫🇷','السنغال','🇸🇳','NRG Stadium, Houston','2026-06-29T20:00:00Z'],
  ['إنجلترا','🏴','اليابان','🇯🇵','Gillette Stadium, Boston','2026-06-29T23:00:00Z'],
  ['إسبانيا','🇪🇸','المغرب','🇲🇦','Estadio BBVA, Monterrey','2026-06-30T18:00:00Z'],
  ['ألمانيا','🇩🇪','المكسيك','🇲🇽','AT&T Stadium, Dallas','2026-06-30T21:00:00Z'],
  ['البرتغال','🇵🇹','كرواتيا','🇭🇷','MetLife Stadium, New York/NJ','2026-06-30T23:00:00Z'],
  ['هولندا','🇳🇱','أمريكا','🇺🇸','Estadio Azteca, Mexico City','2026-07-01T18:00:00Z'],
  ['بلجيكا','🇧🇪','الأوروغواي','🇺🇾','Mercedes-Benz Stadium, Atlanta','2026-07-01T21:00:00Z'],
  ['إيطاليا','🇮🇹','أستراليا','🇦🇺','Lumen Field, Seattle','2026-07-01T23:00:00Z'],
  ['السعودية','🇸🇦','سويسرا','🇨🇭',"Levi's Stadium, San Francisco Bay",'2026-07-02T20:00:00Z'],
  ['كولومبيا','🇨🇴','الدنمارك','🇩🇰','SoFi Stadium, Los Angeles','2026-07-02T23:00:00Z'],
  ['قطر','🇶🇦','الإكوادور','🇪🇨','BMO Field, Toronto','2026-07-02T20:00:00Z'],
  ['كندا','🇨🇦','غانا','🇬🇭','BC Place, Vancouver','2026-07-03T22:00:00Z'],
  ['النرويج','🇳🇴','بولندا','🇵🇱','Hard Rock Stadium, Miami','2026-07-03T20:00:00Z'],
  ['مصر','🇪🇬','صربيا','🇷🇸','Arrowhead Stadium, Kansas City','2026-07-03T23:00:00Z'],
];

const LATER = [
  // round, count, venues+dates
  ['R16', 1, 'Lincoln Financial Field, Philadelphia','2026-07-04T20:00:00Z'],
  ['R16', 2, 'NRG Stadium, Houston','2026-07-04T23:00:00Z'],
  ['R16', 3, 'AT&T Stadium, Dallas','2026-07-05T20:00:00Z'],
  ['R16', 4, 'Lumen Field, Seattle','2026-07-05T23:00:00Z'],
  ['R16', 5, 'Mercedes-Benz Stadium, Atlanta','2026-07-06T20:00:00Z'],
  ['R16', 6, 'SoFi Stadium, Los Angeles','2026-07-06T23:00:00Z'],
  ['R16', 7, 'Gillette Stadium, Boston','2026-07-07T20:00:00Z'],
  ['R16', 8, 'Arrowhead Stadium, Kansas City','2026-07-07T23:00:00Z'],
  ['QF', 1, 'Gillette Stadium, Boston','2026-07-09T21:00:00Z'],
  ['QF', 2, 'SoFi Stadium, Los Angeles','2026-07-10T23:00:00Z'],
  ['QF', 3, 'Arrowhead Stadium, Kansas City','2026-07-10T20:00:00Z'],
  ['QF', 4, 'Hard Rock Stadium, Miami','2026-07-11T20:00:00Z'],
  ['SF', 1, 'AT&T Stadium, Dallas','2026-07-14T23:00:00Z'],
  ['SF', 2, 'Mercedes-Benz Stadium, Atlanta','2026-07-15T23:00:00Z'],
  ['3RD', 1, 'Hard Rock Stadium, Miami','2026-07-18T20:00:00Z'],
  ['FINAL', 1, 'MetLife Stadium, New York/NJ','2026-07-19T19:00:00Z'],
];

// A few finished R32 results for the demo: [matchId, home, away, penWinner?]
const DEMO_RESULTS = [
  [1, 3, 1], [2, 2, 0], [3, 1, 1, 'home'], [4, 0, 2],
];

function applyBracket(matches, m, winSide) {
  if (!winSide) return;
  const w = winSide === 'home'
    ? { n: m.home_team, f: m.home_flag } : { n: m.away_team, f: m.away_flag };
  const l = winSide === 'home'
    ? { n: m.away_team, f: m.away_flag } : { n: m.home_team, f: m.home_flag };
  for (const [src, result, dst, slot] of BRACKET) {
    if (src !== m.id) continue;
    const t = matches.find((x) => x.id === dst);
    if (!t) continue;
    const who = result === 'W' ? w : l;
    t[`${slot}_team`] = who.n;
    t[`${slot}_flag`] = who.f;
  }
}

function decideWinner(m, pen) {
  if (m.home_score == null || m.away_score == null) return null;
  if (m.home_score > m.away_score) return 'home';
  if (m.away_score > m.home_score) return 'away';
  return pen || null;
}

function seedMatches() {
  const out = [];
  R32.forEach(([h, hf, a, af, venue, kickoff], i) => {
    out.push({
      id: i + 1, round: 'R32', match_no: i + 1,
      home_team: h, away_team: a, home_flag: hf, away_flag: af,
      venue, kickoff, home_score: null, away_score: null,
      finished: false, locked: false,
    });
  });
  let id = 17;
  for (const [round, match_no, venue, kickoff] of LATER) {
    out.push({
      id, round, match_no,
      home_team: null, away_team: null, home_flag: null, away_flag: null,
      venue, kickoff, home_score: null, away_score: null,
      finished: false, locked: false,
    });
    id++;
  }
  // Apply the demo results + advance the bracket.
  for (const [mid, hs, as_, pen] of DEMO_RESULTS) {
    const m = out.find((x) => x.id === mid);
    m.home_score = hs; m.away_score = as_;
    m.finished = true; m.locked = true; m.kickoff = null;
    applyBracket(out, m, decideWinner(m, pen));
  }
  return out;
}

function seedPredictions() {
  // ph/pa = predicted penalty-shootout score on a drawn prediction (qualifier = higher)
  const p = (match_id, player_name, h, a, ph = null, pa = null) => ({
    match_id, player_name, home_score: h, away_score: a,
    pen_home: h === a ? ph : null, pen_away: h === a ? pa : null,
    pen_pick: (h === a && ph != null && pa != null) ? (ph > pa ? 'home' : 'away') : null,
  });
  return [
    p(1, 'حسن', 3, 1), p(2, 'حسن', 2, 1), p(3, 'حسن', 1, 1, 4, 2), p(4, 'حسن', 1, 1, 3, 5), p(5, 'حسن', 2, 0),
    p(1, 'عبدالله', 2, 1), p(2, 'عبدالله', 2, 0), p(3, 'عبدالله', 0, 0, 2, 4), p(4, 'عبدالله', 0, 2),
    p(1, 'فهد', 1, 0), p(2, 'فهد', 3, 1), p(3, 'فهد', 2, 1), p(4, 'فهد', 0, 1), p(5, 'فهد', 1, 1, 5, 4),
    p(1, 'سارة', 3, 1), p(2, 'سارة', 1, 0), p(3, 'سارة', 1, 1, 4, 3), p(4, 'سارة', 0, 2),
  ];
}

const MKEY = 'wc_demo_matches';
const PKEY = 'wc_demo_preds';

function readStore(key, seed) {
  try {
    const raw = localStorage.getItem(key);
    if (raw) return JSON.parse(raw);
  } catch (_) {}
  const data = seed();
  try { localStorage.setItem(key, JSON.stringify(data)); } catch (_) {}
  return data;
}
function writeStore(key, data) {
  try { localStorage.setItem(key, JSON.stringify(data)); } catch (_) {}
}

export const demo = {
  matches() { return readStore(MKEY, seedMatches); },
  predictions() { return readStore(PKEY, seedPredictions); },

  myPredictions(name) {
    return this.predictions().filter((p) => p.player_name === name);
  },

  submit(matchId, name, h, a, penHome = null, penAway = null) {
    const m = this.matches().find((x) => x.id === matchId);
    if (m && (m.finished || m.locked)) throw new Error('MATCH_LOCKED');
    // the penalty score only applies to a drawn prediction (and can't be a tie)
    let ph = null, pa = null, pen = null;
    if (h === a && penHome != null && penAway != null && penHome !== penAway) {
      ph = penHome; pa = penAway; pen = penHome > penAway ? 'home' : 'away';
    }
    const preds = this.predictions();
    const ex = preds.find((p) => p.match_id === matchId && p.player_name === name);
    if (ex) { ex.home_score = h; ex.away_score = a; ex.pick = null; ex.pen_pick = pen; ex.pen_home = ph; ex.pen_away = pa; }
    else preds.push({ match_id: matchId, player_name: name, home_score: h, away_score: a, pick: null, pen_pick: pen, pen_home: ph, pen_away: pa });
    writeStore(PKEY, preds);
    return { match_id: matchId, player_name: name, home_score: h, away_score: a, pen_pick: pen, pen_home: ph, pen_away: pa };
  },

  submitWinner(matchId, name, pick) {
    const m = this.matches().find((x) => x.id === matchId);
    if (m && (m.finished || m.locked)) throw new Error('MATCH_LOCKED');
    if (pick !== 'home' && pick !== 'away') throw new Error('INVALID_PICK');
    const preds = this.predictions();
    const ex = preds.find((p) => p.match_id === matchId && p.player_name === name);
    if (ex) { ex.home_score = null; ex.away_score = null; ex.pick = pick; ex.pen_pick = null; ex.pen_home = null; ex.pen_away = null; }
    else preds.push({ match_id: matchId, player_name: name, home_score: null, away_score: null, pick, pen_pick: null, pen_home: null, pen_away: null });
    writeStore(PKEY, preds);
    return { match_id: matchId, player_name: name, pick };
  },

  setPoints(matchId, name, points) {
    const preds = this.predictions();
    const ex = preds.find((p) => p.match_id === matchId && p.player_name === name);
    if (!ex) throw new Error('MATCH_NOT_FOUND');
    ex.manual_points = points;
    writeStore(PKEY, preds);
    return ex;
  },

  reopenMatch(matchId) {
    const matches = this.matches();
    const m = matches.find((x) => x.id === matchId);
    if (!m) throw new Error('MATCH_NOT_FOUND');
    m.home_score = null; m.away_score = null; m.finished = false; m.locked = false;
    writeStore(MKEY, matches);
    return m;
  },

  setResult(matchId, h, a, winner, homePen = null, awayPen = null) {
    const matches = this.matches();
    const m = matches.find((x) => x.id === matchId);
    if (!m) throw new Error('MATCH_NOT_FOUND');
    m.home_score = h; m.away_score = a;
    m.home_pen = (h != null && a != null && h === a) ? homePen : null;
    m.away_pen = (h != null && a != null && h === a) ? awayPen : null;
    m.finished = h != null && a != null;
    m.locked = m.locked || m.finished;
    if (m.finished) applyBracket(matches, m, decideWinner(m, winner));
    writeStore(MKEY, matches);
    return m;
  },

  saveMatch(matchId, fields) {
    const matches = this.matches();
    const m = matches.find((x) => x.id === matchId);
    if (!m) throw new Error('MATCH_NOT_FOUND');
    Object.assign(m, fields);
    writeStore(MKEY, matches);
    return m;
  },

  reset() { writeStore(MKEY, seedMatches()); writeStore(PKEY, seedPredictions()); },

  deletePlayer(name) {
    const preds = this.predictions().filter((p) => p.player_name !== String(name).trim());
    writeStore(PKEY, preds);
    return 1;
  },

  addPrediction(matchId, name, h, a, penHome = null, penAway = null) {
    const m = this.matches().find((x) => x.id === matchId);
    if (!m) throw new Error('MATCH_NOT_FOUND');
    if (m.finished) throw new Error('MATCH_FINISHED');   // admin bypasses lock, not result
    let ph = null, pa = null, pen = null;
    if (h === a && penHome != null && penAway != null && penHome !== penAway) {
      ph = penHome; pa = penAway; pen = penHome > penAway ? 'home' : 'away';
    }
    const preds = this.predictions();
    const ex = preds.find((p) => p.match_id === matchId && p.player_name === String(name).trim());
    if (ex) { ex.home_score = h; ex.away_score = a; ex.pick = null; ex.pen_pick = pen; ex.pen_home = ph; ex.pen_away = pa; }
    else preds.push({ match_id: matchId, player_name: String(name).trim(), home_score: h, away_score: a, pick: null, pen_pick: pen, pen_home: ph, pen_away: pa });
    writeStore(PKEY, preds);
    return { match_id: matchId, player_name: name };
  },

  deletePrediction(matchId, name) {
    const nm = String(name).trim();
    const preds = this.predictions().filter(
      (p) => !(p.match_id === matchId && p.player_name === nm));
    writeStore(PKEY, preds);
    return 1;
  },

  resetWhat(what) {
    if (what === 'predictions' || what === 'all') writeStore(PKEY, []);
    if (what === 'results' || what === 'all') {
      const matches = this.matches();
      for (const m of matches) {
        m.home_score = null; m.away_score = null; m.finished = false; m.locked = false;
        if (m.id >= 17) { m.home_team = null; m.away_team = null; m.home_flag = null; m.away_flag = null; }
      }
      writeStore(MKEY, matches);
    }
    return what;
  },
};
