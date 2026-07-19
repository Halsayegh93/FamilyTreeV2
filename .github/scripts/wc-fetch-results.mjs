// ============================================================================
// (Runs on a 20-min cron, on manual dispatch, and on push to main.)
// World Cup auto-fetch — pulls fixtures/results from football-data.org and
// pushes them into the Supabase DB via the admin RPCs. Runs in GitHub Actions
// (see .github/workflows/wc-autofetch.yml).
//
// EXPERIMENTAL: football-data.org's free tier coverage of the 2026 World Cup
// and its stage names are not guaranteed. The script logs everything so you can
// see, in the Action run logs, exactly what it matched and updated.
//
// Required env (set as GitHub repo Secrets, except the public ones):
//   FOOTBALL_API_KEY   - your football-data.org token        (secret)
//   WC_ADMIN_PIN       - the admin PIN (default 1993)        (secret)
//   SUPABASE_URL       - public project URL
//   SUPABASE_ANON_KEY  - public anon/publishable key
// ============================================================================

const API_KEY = process.env.FOOTBALL_API_KEY;
const PIN = process.env.WC_ADMIN_PIN || '1993';
const SB_URL = process.env.SUPABASE_URL;
const SB_KEY = process.env.SUPABASE_ANON_KEY;
// The source brings teams, flags, kickoff AND the official result (aligned to our
// orientation by team name). The admin can still override any result by hand.
// Set WC_AUTO_RESULTS=0 to stop auto-filling results.
const AUTO_RESULTS = process.env.WC_AUTO_RESULTS !== '0';
// Knockout-only game: group-stage matches are not imported. Set
// WC_IMPORT_GROUPS=1 to bring them back.
const IMPORT_GROUPS = process.env.WC_IMPORT_GROUPS === '1';

if (!API_KEY || !SB_URL || !SB_KEY) {
  console.error('Missing FOOTBALL_API_KEY / SUPABASE_URL / SUPABASE_ANON_KEY');
  process.exit(1);
}

// Team names are kept in ENGLISH (as returned by the API). We only add a flag.
const FLAGS = {
  'mexico': '🇲🇽', 'south africa': '🇿🇦', 'south korea': '🇰🇷', 'korea republic': '🇰🇷',
  'czech republic': '🇨🇿', 'czechia': '🇨🇿', 'canada': '🇨🇦', 'switzerland': '🇨🇭',
  'qatar': '🇶🇦', 'bosnia and herzegovina': '🇧🇦', 'brazil': '🇧🇷', 'morocco': '🇲🇦',
  'scotland': '🏴󠁧󠁢󠁳󠁣󠁴󠁿', 'haiti': '🇭🇹', 'united states': '🇺🇸', 'usa': '🇺🇸', 'paraguay': '🇵🇾',
  'australia': '🇦🇺', 'turkey': '🇹🇷', 'türkiye': '🇹🇷', 'turkiye': '🇹🇷', 'germany': '🇩🇪',
  'curaçao': '🇨🇼', 'curacao': '🇨🇼', 'costa rica': '🇨🇷', 'ecuador': '🇪🇨',
  'netherlands': '🇳🇱', 'japan': '🇯🇵', 'tunisia': '🇹🇳', 'sweden': '🇸🇪', 'belgium': '🇧🇪',
  'egypt': '🇪🇬', 'iran': '🇮🇷', 'ir iran': '🇮🇷', 'new zealand': '🇳🇿', 'spain': '🇪🇸',
  'cape verde': '🇨🇻', 'cabo verde': '🇨🇻', 'saudi arabia': '🇸🇦', 'uruguay': '🇺🇾',
  'france': '🇫🇷', 'senegal': '🇸🇳', 'norway': '🇳🇴', 'iraq': '🇮🇶', 'argentina': '🇦🇷',
  'algeria': '🇩🇿', 'austria': '🇦🇹', 'jordan': '🇯🇴', 'portugal': '🇵🇹', 'colombia': '🇨🇴',
  'uzbekistan': '🇺🇿', 'dr congo': '🇨🇩', 'congo dr': '🇨🇩', 'england': '🏴󠁧󠁢󠁥󠁮󠁧󠁿',
  'croatia': '🇭🇷', 'ghana': '🇬🇭', 'panama': '🇵🇦',
  'ivory coast': '🇨🇮', "cote d'ivoire": '🇨🇮', 'côte d’ivoire': '🇨🇮',
};

// Confirmed Round-of-32 matchups (slot id -> [home, away]). Used as a fallback to
// fill teams the source still returns as null. The source overrides if it later
// publishes a value. Order matches the source's date-sorted slot assignment.
const R32_FALLBACK = {
  1: ['South Africa', 'Canada'],
  2: ['Brazil', 'Japan'],
  3: ['Germany', 'Paraguay'],
  4: ['Netherlands', 'Morocco'],
  5: ['Ivory Coast', 'Norway'],
  6: ['France', 'Sweden'],
  7: ['Mexico', 'Ecuador'],
  8: ['England', 'DR Congo'],
  9: ['Belgium', 'Senegal'],
  10: ['United States', 'Bosnia and Herzegovina'],
  11: ['Spain', 'Austria'],
  12: ['Portugal', 'Croatia'],
  13: ['Switzerland', 'Algeria'],
  14: ['Australia', 'Egypt'],
  15: ['Argentina', 'Cape Verde'],
  16: ['Colombia', 'Ghana'],
};

function teamInfo(name) {
  if (!name) return [null, '⚽️'];
  return [name, FLAGS[String(name).trim().toLowerCase()] || '⚽️'];
}

// Flag DERIVED from a team name — returns null (not the '⚽️' placeholder) when
// the name is empty or unknown. Passing null to save_match keeps whatever flag
// is already stored, so an undecided slot never wipes a real flag that bracket
// propagation set on a match that has no predictions yet.
function flagFor(name) {
  return name ? (FLAGS[String(name).trim().toLowerCase()] || null) : null;
}

// football-data stage -> our match id ranges (in order within the stage)
const STAGE_TO_IDS = {
  LAST_32: [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16],
  ROUND_OF_32: [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16],
  LAST_16: [17,18,19,20,21,22,23,24],
  ROUND_OF_16: [17,18,19,20,21,22,23,24],
  QUARTER_FINALS: [25,26,27,28],
  QUARTER_FINAL: [25,26,27,28],
  SEMI_FINALS: [29,30],
  SEMI_FINAL: [29,30],
  THIRD_PLACE: [31],
  FINAL: [32],
};

async function sbRpc(fn, body) {
  const r = await fetch(`${SB_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SB_KEY,
      Authorization: `Bearer ${SB_KEY}`,
    },
    body: JSON.stringify(body),
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`${fn} -> ${r.status} ${text}`);
  return text;
}

async function sbGet(path) {
  const r = await fetch(`${SB_URL}/rest/v1/${path}`, {
    headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}` },
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`GET ${path} -> ${r.status} ${text}`);
  return JSON.parse(text);
}

const norm = (s) => String(s || '').trim().toLowerCase().replace(/\s+/g, ' ');

// Align the API's scores to OUR stored home/away by TEAM NAME, so a result is
// never stored reversed even if our home/away orientation differs from the API's
// (which otherwise mis-scores predictions). Returns { gh, ga, ph, pa, flipped }.

// Split the API score into GOALS (incl. extra time) and the PENALTY SHOOTOUT.
// football-data.org quirk: when a match ends in a shootout, score.fullTime
// INCLUDES the shootout kicks — storing it as-is shows e.g. "4-5" for a 1-1
// match decided 3-4 on penalties. The real goals are regularTime + extraTime
// (fallback: fullTime minus penalties).
function splitScore(api) {
  const s = api.score || {};
  let gh = s.fullTime?.home, ga = s.fullTime?.away;
  let ph = null, pa = null;
  if (s.duration === 'PENALTY_SHOOTOUT'
      && s.penalties?.home != null && s.penalties?.away != null) {
    ph = s.penalties.home; pa = s.penalties.away;
    if (s.regularTime?.home != null && s.regularTime?.away != null) {
      gh = s.regularTime.home + (s.extraTime?.home || 0);
      ga = s.regularTime.away + (s.extraTime?.away || 0);
    } else if (gh != null && ga != null) {
      gh -= ph; ga -= pa;
    }
  }
  return { gh, ga, ph, pa };
}

// A shootout match whose score can't be split into goals vs. kicks: the list
// endpoint often sends only fullTime (which INCLUDES the shootout kicks) with
// no penalties/regularTime breakdown. Storing that as-is merges the kicks into
// the goals (a 1-1 match decided 4-3 shows as 5-4) and breaks the scoring.
function unsplittable(api) {
  const s = api.score || {};
  return s.duration === 'PENALTY_SHOOTOUT'
    && (s.penalties?.home == null || s.penalties?.away == null);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// The single-match endpoint DOES carry the full breakdown (regularTime,
// extraTime, penalties). Fetched only for shootout matches the list response
// left unsplittable. Returns the match object or null.
async function fetchMatchDetail(apiId) {
  try {
    await sleep(6500);   // free tier: 10 calls/min — stay under the limit
    const r = await fetch(`https://api.football-data.org/v4/matches/${apiId}`, {
      headers: { 'X-Auth-Token': API_KEY },
    });
    if (!r.ok) { console.error(`match detail ${apiId} -> ${r.status}`); return null; }
    const d = await r.json();
    return d.match || d;
  } catch (e) { console.error(`match detail ${apiId}:`, e.message); return null; }
}

function alignToStored(storedHome, api) {
  const { gh, ga, ph, pa } = splitScore(api);
  const ourH = norm(storedHome);
  const apiH = norm(api.homeTeam?.name);
  const apiA = norm(api.awayTeam?.name);
  if (ourH && ourH === apiA && ourH !== apiH)
    return { gh: ga, ga: gh, ph: pa, pa: ph, flipped: true };
  return { gh, ga, ph, pa, flipped: false };
}

async function main() {
  console.log('Fetching World Cup matches from football-data.org ...');
  const res = await fetch('https://api.football-data.org/v4/competitions/WC/matches', {
    headers: { 'X-Auth-Token': API_KEY },
  });
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`football-data API ${res.status}: ${t}\n` +
      'If 403/forbidden, your plan likely does not cover this competition.');
  }
  const data = await res.json();
  const matches = data.matches || [];
  console.log(`Got ${matches.length} matches. Stages present:`,
    [...new Set(matches.map((m) => m.stage))].join(', ') || '(none)');

  // group knockout matches by stage, sorted by date
  const byStage = {};
  for (const m of matches) {
    if (!STAGE_TO_IDS[m.stage]) continue; // skip group stage / unknown
    (byStage[m.stage] ||= []).push(m);
  }

  let teamUpdates = 0, groupUpdates = 0, resultUpdates = 0;
  // finished matches to score AFTER we know our stored orientation
  const finishedJobs = []; // { ourId, api }

  // Snapshot current teams/flags BEFORE Phase A, so a slot whose team is
  // already known (e.g. filled by bracket propagation) can heal a lost flag
  // even when the source still reports the slot as undecided.
  let preDb = new Map();
  try {
    const rows = await sbGet('wc_matches?select=id,home_team,away_team,home_flag,away_flag');
    preDb = new Map(rows.map((r) => [r.id, r]));
  } catch (e) { console.error('read wc_matches (pre):', e.message); }

  // ----- PHASE A: set teams / kickoff (knockout slots) -----
  for (const [stage, ids] of Object.entries(STAGE_TO_IDS)) {
    const list = (byStage[stage] || []).slice()
      .sort((a, b) => new Date(a.utcDate) - new Date(b.utcDate) || a.id - b.id);
    for (let i = 0; i < list.length && i < ids.length; i++) {
      const api = list[i];
      const ourId = ids[i];
      const fb = R32_FALLBACK[ourId];
      const stored = preDb.get(ourId);
      // team name: source, else the confirmed bracket fallback, else whatever
      // bracket propagation already stored (winners of earlier rounds).
      const hN = api.homeTeam?.name || (fb ? fb[0] : null) || stored?.home_team || null;
      const aN = api.awayTeam?.name || (fb ? fb[1] : null) || stored?.away_team || null;
      // flag derived from the NAME — never the '⚽️' placeholder. null = keep
      // the stored flag, so an undecided slot can't wipe a real flag.
      const hF = flagFor(hN);
      const aF = flagFor(aN);
      try {
        await sbRpc('wc_admin_save_match', {
          p_match_id: ourId,
          p_home_team: hN, p_away_team: aN,
          p_home_flag: hF, p_away_flag: aF,
          p_venue: api.venue || null,
          p_kickoff: api.utcDate || null,
          p_locked: null,
          p_pin: PIN,
        });
        teamUpdates++;
        console.log(`teams  #${ourId} [${stage}]  ${hN} vs ${aN}`);
      } catch (e) { console.error(`save_match #${ourId}:`, e.message); }

      if (api.status === 'FINISHED' && api.score?.fullTime?.home != null) {
        finishedJobs.push({ ourId, api });
      }
    }
  }

  // ----- PHASE A (group-stage matches) -----
  const groupLabel = () => 'دور المجموعات';
  for (const api of (IMPORT_GROUPS ? matches.filter((m) => m.stage === 'GROUP_STAGE') : [])) {
    const [hN, hF] = teamInfo(api.homeTeam?.name);
    const [aN, aF] = teamInfo(api.awayTeam?.name);
    try {
      await sbRpc('wc_admin_upsert_match', {
        p_id: api.id,
        p_round: groupLabel(api.group),
        p_match_no: api.matchday || 0,
        p_home_team: hN, p_home_flag: hF, p_away_team: aN, p_away_flag: aF,
        p_venue: api.venue || null, p_kickoff: api.utcDate || null, p_pin: PIN,
      });
      groupUpdates++;
      if (api.status === 'FINISHED' && api.score?.fullTime?.home != null) {
        finishedJobs.push({ ourId: api.id, api });
      }
    } catch (e) { console.error(`group #${api.id}:`, e.message); }
  }
  console.log(IMPORT_GROUPS
    ? `Group-stage matches upserted: ${groupUpdates}`
    : 'Group-stage import skipped (knockout-only game).');

  // ----- PHASE B: results -----
  if (!AUTO_RESULTS) {
    console.log(`Auto-results OFF — ${finishedJobs.length} finished match(es) left for ` +
      'the admin to enter manually. (Set WC_AUTO_RESULTS=1 to auto-fill.)');
  } else {
    // read back OUR stored orientation + current result (reflects frozen +
    // freshly-set teams, and lets us keep data the API doesn't resend)
    let dbById = new Map();
    try {
      const db = await sbGet('wc_matches?select=id,home_team,away_team,home_score,away_score,home_pen,away_pen,finished');
      dbById = new Map(db.map((m) => [m.id, m]));
    } catch (e) { console.error('read wc_matches:', e.message); }

    // set results, aligned to OUR orientation by team name; the penalty
    // shootout (if any) is stored separately in home_pen/away_pen — never
    // mixed into the goals.
    for (const { ourId, api } of finishedJobs) {
      const stored = dbById.get(ourId);

      // shootout without a breakdown -> get the real goals/kicks split from the
      // single-match endpoint; NEVER store a merged goals+kicks number.
      let src = api;
      if (unsplittable(src)) {
        const detail = await fetchMatchDetail(api.id);
        if (detail && !unsplittable(detail)) {
          src = detail;
        } else if (stored?.finished) {
          console.log(`result #${ourId}  kept stored result (shootout breakdown unavailable)`);
          continue;
        } else {
          console.log(`result #${ourId}  SKIPPED — shootout breakdown unavailable; ` +
            'enter it from the admin page or wait for the next run.');
          continue;
        }
      }

      let { gh, ga, ph, pa, flipped } = alignToStored(stored?.home_team, src);
      // The matches endpoint often omits the shootout breakdown for a finished
      // draw — never let that erase a shootout score already stored (entered by
      // the admin or a previous run), or the pens vanish from the site on every
      // cron tick.
      if (gh != null && gh === ga && (ph == null || pa == null)
          && stored?.home_pen != null && stored?.away_pen != null) {
        ph = stored.home_pen; pa = stored.away_pen;
        console.log(`result #${ourId}  keeping stored pens ${ph}-${pa} (API sent none)`);
      }
      // identical to what's stored -> skip the write entirely, so manual admin
      // fixes aren't churned every 20 minutes
      if (stored?.finished
          && stored.home_score === gh && stored.away_score === ga
          && (stored.home_pen ?? null) === (ph ?? null)
          && (stored.away_pen ?? null) === (pa ?? null)) {
        continue;
      }
      let winner = null;
      if (gh === ga && (ph == null || pa == null)) {
        const w = src.score.winner; // penalties decider (shootout score unknown)
        if (w === 'HOME_TEAM') winner = flipped ? 'away' : 'home';
        else if (w === 'AWAY_TEAM') winner = flipped ? 'home' : 'away';
      }
      try {
        await sbRpc('wc_admin_set_result', {
          p_match_id: ourId, p_home: gh, p_away: ga, p_pin: PIN, p_winner: winner,
          p_home_pen: ph, p_away_pen: pa,
        });
        resultUpdates++;
        console.log(`result #${ourId}  ${gh}-${ga}` +
          `${ph != null ? ` (pens ${ph}-${pa})` : ''}` +
          `${flipped ? ' (aligned by name)' : ''}${winner ? ` (pen:${winner})` : ''}`);
      } catch (e) { console.error(`set_result #${ourId}:`, e.message); }
    }
  }

  console.log(`Done. Team updates: ${teamUpdates}, group: ${groupUpdates}, result updates: ${resultUpdates}.`);
  if (teamUpdates === 0 && groupUpdates === 0)
    console.log('NOTE: no matches matched — the competition may not be covered ' +
      'by your plan, or stages are not published yet.');
}

main().catch((e) => { console.error(e); process.exit(1); });
