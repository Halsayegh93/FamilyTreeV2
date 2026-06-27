// ============================================================================
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

  let teamUpdates = 0, resultUpdates = 0;

  for (const [stage, ids] of Object.entries(STAGE_TO_IDS)) {
    const list = (byStage[stage] || []).slice()
      .sort((a, b) => new Date(a.utcDate) - new Date(b.utcDate) || a.id - b.id);
    for (let i = 0; i < list.length && i < ids.length; i++) {
      const api = list[i];
      const ourId = ids[i];
      const [hN, hF] = teamInfo(api.homeTeam?.name);
      const [aN, aF] = teamInfo(api.awayTeam?.name);

      // set teams + kickoff (+ venue) for this match
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

      // finished -> push the result
      if (api.status === 'FINISHED' && api.score?.fullTime) {
        const h = api.score.fullTime.home;
        const a = api.score.fullTime.away;
        let winner = null;
        if (h === a) winner = api.score.winner === 'AWAY_TEAM' ? 'away'
          : api.score.winner === 'HOME_TEAM' ? 'home' : null;
        if (h != null && a != null) {
          try {
            await sbRpc('wc_admin_set_result', {
              p_match_id: ourId, p_home: h, p_away: a, p_pin: PIN, p_winner: winner,
            });
            resultUpdates++;
            console.log(`result #${ourId}  ${h}-${a}${winner ? ` (pen:${winner})` : ''}`);
          } catch (e) { console.error(`set_result #${ourId}:`, e.message); }
        }
      }
    }
  }

  console.log(`Done. Team updates: ${teamUpdates}, result updates: ${resultUpdates}.`);
  if (teamUpdates === 0)
    console.log('NOTE: no knockout matches matched — the competition may not be ' +
      'covered by your plan yet, or stages are not published. This is expected ' +
      'before the knockout stage begins.');
}

main().catch((e) => { console.error(e); process.exit(1); });
