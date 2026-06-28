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
  'scotland': '🏴', 'haiti': '🇭🇹', 'united states': '🇺🇸', 'usa': '🇺🇸', 'paraguay': '🇵🇾',
  'australia': '🇦🇺', 'turkey': '🇹🇷', 'türkiye': '🇹🇷', 'turkiye': '🇹🇷', 'germany': '🇩🇪',
  'curaçao': '🇨🇼', 'curacao': '🇨🇼', 'costa rica': '🇨🇷', 'ecuador': '🇪🇨',
  'netherlands': '🇳🇱', 'japan': '🇯🇵', 'tunisia': '🇹🇳', 'sweden': '🇸🇪', 'belgium': '🇧🇪',
  'egypt': '🇪🇬', 'iran': '🇮🇷', 'ir iran': '🇮🇷', 'new zealand': '🇳🇿', 'spain': '🇪🇸',
  'cape verde': '🇨🇻', 'cabo verde': '🇨🇻', 'saudi arabia': '🇸🇦', 'uruguay': '🇺🇾',
  'france': '🇫🇷', 'senegal': '🇸🇳', 'norway': '🇳🇴', 'iraq': '🇮🇶', 'argentina': '🇦🇷',
  'algeria': '🇩🇿', 'austria': '🇦🇹', 'jordan': '🇯🇴', 'portugal': '🇵🇹', 'colombia': '🇨🇴',
  'uzbekistan': '🇺🇿', 'dr congo': '🇨🇩', 'congo dr': '🇨🇩', 'england': '🏴',
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
// (which otherwise mis-scores predictions). Returns { ph, pa, flipped }.
function alignToStored(storedHome, api) {
  const sh = api.score.fullTime.home;
  const sa = api.score.fullTime.away;
  const ourH = norm(storedHome);
  const apiH = norm(api.homeTeam?.name);
  const apiA = norm(api.awayTeam?.name);
  if (ourH && ourH === apiA && ourH !== apiH) return { ph: sa, pa: sh, flipped: true };
  return { ph: sh, pa: sa, flipped: false };
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

  // ----- PHASE A: set teams / kickoff (knockout slots) -----
  for (const [stage, ids] of Object.entries(STAGE_TO_IDS)) {
    const list = (byStage[stage] || []).slice()
      .sort((a, b) => new Date(a.utcDate) - new Date(b.utcDate) || a.id - b.id);
    for (let i = 0; i < list.length && i < ids.length; i++) {
      const api = list[i];
      const ourId = ids[i];
      let [hN, hF] = teamInfo(api.homeTeam?.name);
      let [aN, aF] = teamInfo(api.awayTeam?.name);
      // fill any team the source hasn't decided yet from the confirmed bracket
      const fb = R32_FALLBACK[ourId];
      if (fb) {
        if (!hN) [hN, hF] = teamInfo(fb[0]);
        if (!aN) [aN, aF] = teamInfo(fb[1]);
      }
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

  // ----- DEBUG: stored R32 dates -----
  try {
    const r32 = await sbGet('wc_matches?select=id,round,home_team,away_team,kickoff&id=lte.16&order=id.asc');
    for (const m of r32) console.log(`#${m.id} [${m.round}] ${m.home_team}-${m.away_team} @ ${m.kickoff}`);
  } catch (e) { console.error('dbg:', e.message); }

  // ----- PHASE B: results -----
  if (!AUTO_RESULTS) {
    console.log(`Auto-results OFF — ${finishedJobs.length} finished match(es) left for ` +
      'the admin to enter manually. (Set WC_AUTO_RESULTS=1 to auto-fill.)');
  } else {
    // read back OUR stored orientation (reflects frozen + freshly-set teams)
    let dbById = new Map();
    try {
      const db = await sbGet('wc_matches?select=id,home_team,away_team');
      dbById = new Map(db.map((m) => [m.id, m]));
    } catch (e) { console.error('read wc_matches:', e.message); }

    // set results, aligned to OUR orientation by team name
    for (const { ourId, api } of finishedJobs) {
      const stored = dbById.get(ourId);
      const { ph, pa, flipped } = alignToStored(stored?.home_team, api);
      let winner = null;
      if (ph === pa) {
        const w = api.score.winner; // penalties decider
        if (w === 'HOME_TEAM') winner = flipped ? 'away' : 'home';
        else if (w === 'AWAY_TEAM') winner = flipped ? 'home' : 'away';
      }
      try {
        await sbRpc('wc_admin_set_result', {
          p_match_id: ourId, p_home: ph, p_away: pa, p_pin: PIN, p_winner: winner,
        });
        resultUpdates++;
        console.log(`result #${ourId}  ${ph}-${pa}${flipped ? ' (aligned by name)' : ''}` +
          `${winner ? ` (pen:${winner})` : ''}`);
      } catch (e) { console.error(`set_result #${ourId}:`, e.message); }
    }
  }

  console.log(`Done. Team updates: ${teamUpdates}, group: ${groupUpdates}, result updates: ${resultUpdates}.`);
  if (teamUpdates === 0 && groupUpdates === 0)
    console.log('NOTE: no matches matched — the competition may not be covered ' +
      'by your plan, or stages are not published yet.');
}

main().catch((e) => { console.error(e); process.exit(1); });
