// ============================================================================
// wc-auto-results — auto-approve World Cup match results
// ----------------------------------------------------------------------------
// Runs on a schedule (pg_cron → pg_net → this function). For every match that
// has both teams, has kicked off, and is NOT finished yet, it looks up the real
// result and, if the match is over, approves it via wc_admin_set_result (which
// also advances the bracket and recomputes points).
//
//   Primary source : ESPN scoreboard  (free, no key, includes shootout scores)
//   Cross-check     : API-Football     (optional — only if APIFOOTBALL_KEY set)
//
// Safety:
//   • Only touches matches with finished=false, so admin edits are never
//     overwritten. If an admin re-opens a match it will be re-fetched.
//   • If the cross-check source disagrees on the regular-time score, the match
//     is SKIPPED (reported as a conflict) instead of written.
//   • Protected by a shared secret header (x-cron-secret). See README.
//
// NOTE: the live deployment injects CRON_SECRET (kept out of git). Set it as a
// function secret, or bake it before deploying — see README.md.
// ============================================================================

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const CRON_SECRET = Deno.env.get("CRON_SECRET") ?? "";

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SVC = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const PIN = Deno.env.get("WC_ADMIN_PIN") ?? "1993";
const APIFOOTBALL_KEY = Deno.env.get("APIFOOTBALL_KEY") ?? "";

const ESPN = (yyyymmdd: string) =>
  `https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/scoreboard?dates=${yyyymmdd}`;

const FINISHED = new Set([
  "STATUS_FULL_TIME", "STATUS_FINAL", "STATUS_FINAL_AET", "STATUS_FINAL_PEN",
]);
// statuses where the match has NOT started — everything else (and not FINISHED)
// counts as in-progress, and its score is mirrored live into wc_matches
const NOT_STARTED = new Set([
  "STATUS_SCHEDULED", "STATUS_POSTPONED", "STATUS_CANCELED", "STATUS_DELAYED",
]);

// Canonicalise a team name so the same team from any source compares equal.
function canon(s: string): string {
  let t = (s ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "");
  t = t.toLowerCase().replace(/[^a-z ]/g, " ").replace(/\s+/g, " ").trim();
  const A: Record<string, string> = {
    "cape verde islands": "cape verde",
    "cabo verde": "cape verde",
    "united states": "usa",
    "cote divoire": "ivory coast",
    "cote d ivoire": "ivory coast",
    "korea republic": "south korea",
    "bosnia and herzegovina": "bosnia herzegovina",
    "dr congo": "congo dr",
  };
  return A[t] ?? t;
}
const pairKey = (a: string, b: string) => [canon(a), canon(b)].sort().join("|");

function ymd(d: Date): string {
  return d.toISOString().slice(0, 10).replace(/-/g, "");
}
function daysAround(iso: string): string[] {
  const base = new Date(iso);
  const out: string[] = [];
  for (const off of [-1, 0, 1]) {
    const d = new Date(base);
    d.setUTCDate(d.getUTCDate() + off);
    out.push(ymd(d));
  }
  return out;
}

type Fix = {
  home: string; away: string;
  hs: number | null; as: number | null;
  hp: number | null; ap: number | null;
  finished: boolean;
  live: boolean;   // kicked off, still in progress
};

// ---- ESPN -----------------------------------------------------------------
async function espnIndex(dates: string[]): Promise<Map<string, Fix>> {
  const idx = new Map<string, Fix>();
  for (const d of dates) {
    let j: any;
    try {
      const r = await fetch(ESPN(d));
      if (!r.ok) continue;
      j = await r.json();
    } catch { continue; }
    for (const ev of j.events ?? []) {
      const comp = ev.competitions?.[0];
      const cs = comp?.competitors ?? [];
      const home = cs.find((c: any) => c.homeAway === "home");
      const away = cs.find((c: any) => c.homeAway === "away");
      if (!home || !away) continue;
      const status = ev.status?.type?.name ?? "";
      const num = (v: any) => (v === null || v === undefined || v === "" ? null : Number(v));
      idx.set(pairKey(home.team?.displayName, away.team?.displayName), {
        home: home.team?.displayName, away: away.team?.displayName,
        hs: num(home.score), as: num(away.score),
        hp: num(home.shootoutScore), ap: num(away.shootoutScore),
        finished: FINISHED.has(status),
        live: !FINISHED.has(status) && !NOT_STARTED.has(status),
      });
    }
  }
  return idx;
}

// ---- API-Football (optional cross-check) ----------------------------------
async function apiFootballIndex(dates: string[]): Promise<Map<string, { hs: number; as: number }>> {
  const idx = new Map<string, { hs: number; as: number }>();
  if (!APIFOOTBALL_KEY) return idx;
  for (const d of dates) {
    const iso = `${d.slice(0, 4)}-${d.slice(4, 6)}-${d.slice(6, 8)}`;
    try {
      const r = await fetch(
        `https://v3.football.api-sports.io/fixtures?league=1&season=2026&date=${iso}`,
        { headers: { "x-apisports-key": APIFOOTBALL_KEY } },
      );
      if (!r.ok) continue;
      const j = await r.json();
      for (const f of j.response ?? []) {
        const st = f.fixture?.status?.short ?? "";
        if (!["FT", "AET", "PEN"].includes(st)) continue;
        const hs = f.goals?.home, as = f.goals?.away;
        if (hs == null || as == null) continue;
        idx.set(pairKey(f.teams?.home?.name, f.teams?.away?.name), { hs, as });
      }
    } catch { /* ignore — cross-check is best-effort */ }
  }
  return idx;
}

async function setResult(m: any, p_home: number, p_away: number, p_home_pen: number | null, p_away_pen: number | null) {
  const r = await fetch(`${SB_URL}/rest/v1/rpc/wc_admin_set_result`, {
    method: "POST",
    headers: { "Content-Type": "application/json", apikey: SVC, Authorization: `Bearer ${SVC}` },
    body: JSON.stringify({
      p_match_id: m.id, p_home, p_away, p_pin: PIN,
      p_winner: null, p_home_pen, p_away_pen,
    }),
  });
  if (!r.ok) throw new Error(`rpc ${r.status}: ${await r.text()}`);
}

Deno.serve(async (req) => {
  // --- auth ---
  const secret = req.headers.get("x-cron-secret");
  const bearer = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  if ((!CRON_SECRET || secret !== CRON_SECRET) && bearer !== SVC) {
    return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401 });
  }
  const url = new URL(req.url);
  const dry = url.searchParams.get("dry") === "1";

  // --- pending matches (both teams, kicked off, not finished) ---
  const nowIso = new Date().toISOString();
  const q = `${SB_URL}/rest/v1/wc_matches?select=id,round,home_team,away_team,kickoff,finished,home_score,away_score,home_pen,away_pen`
    + `&finished=eq.false&home_team=not.is.null&away_team=not.is.null&kickoff=lt.${nowIso}`;
  const pr = await fetch(q, { headers: { apikey: SVC, Authorization: `Bearer ${SVC}` } });
  if (!pr.ok) {
    return new Response(JSON.stringify({ error: `fetch matches ${pr.status}`, detail: await pr.text() }), { status: 500 });
  }
  const pending: any[] = await pr.json();
  if (!pending.length) {
    return new Response(JSON.stringify({ ok: true, dry, approved: [], conflicts: [], waiting: [], liveUpdated: [], msg: "no pending matches" }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  // --- gather sources over the needed date window ---
  const dates = [...new Set(pending.flatMap((m) => daysAround(m.kickoff)))];
  const espn = await espnIndex(dates);
  const cross = await apiFootballIndex(dates);

  const approved: any[] = [], conflicts: any[] = [], waiting: any[] = [], liveUpdated: any[] = [];

  for (const m of pending) {
    const key = pairKey(m.home_team, m.away_team);
    const fx = espn.get(key);
    if (!fx || !fx.finished || fx.hs === null || fx.as === null) {
      // in progress → mirror the live score (and a live shootout) into the row
      // WITHOUT finishing it, so the site + admin see goals as they happen
      if (fx && fx.live && fx.hs !== null && fx.as !== null && !dry) {
        const sameO = canon(fx.home) === canon(m.home_team);
        const lh = sameO ? fx.hs : fx.as;
        const la = sameO ? fx.as : fx.hs;
        const draw = lh === la;
        const lp = draw && fx.hp !== null && fx.ap !== null ? (sameO ? fx.hp : fx.ap) : null;
        const lq = draw && fx.hp !== null && fx.ap !== null ? (sameO ? fx.ap : fx.hp) : null;
        if (lh !== m.home_score || la !== m.away_score || lp !== m.home_pen || lq !== m.away_pen) {
          try {
            const r = await fetch(`${SB_URL}/rest/v1/wc_matches?id=eq.${m.id}&finished=eq.false`, {
              method: "PATCH",
              headers: {
                "Content-Type": "application/json", apikey: SVC,
                Authorization: `Bearer ${SVC}`, Prefer: "return=minimal",
              },
              body: JSON.stringify({ home_score: lh, away_score: la, home_pen: lp, away_pen: lq }),
            });
            if (r.ok) liveUpdated.push({ id: m.id, match: `${m.home_team} vs ${m.away_team}`, live: `${lh}-${la}${lp !== null ? ` (pens ${lp}-${lq})` : ""}` });
          } catch { /* live mirroring is best-effort */ }
        }
      }
      waiting.push({ id: m.id, match: `${m.home_team} vs ${m.away_team}`, reason: fx ? (fx.live ? "live" : "not finished") : "not found on ESPN" });
      continue;
    }
    // map ESPN home/away onto the DB row's home/away by team identity
    const sameOrient = canon(fx.home) === canon(m.home_team);
    const p_home = sameOrient ? fx.hs : fx.as;
    const p_away = sameOrient ? fx.as : fx.hs;
    const isDraw = p_home === p_away;
    let p_home_pen: number | null = null, p_away_pen: number | null = null;
    if (isDraw && fx.hp !== null && fx.ap !== null) {
      p_home_pen = sameOrient ? fx.hp : fx.ap;
      p_away_pen = sameOrient ? fx.ap : fx.hp;
    }

    // cross-check regular-time score against API-Football when available
    const x = cross.get(key);
    if (x) {
      const xh = sameOrient ? x.hs : x.as;
      const xa = sameOrient ? x.as : x.hs;
      if (xh !== p_home || xa !== p_away) {
        conflicts.push({ id: m.id, match: `${m.home_team} vs ${m.away_team}`, espn: `${p_home}-${p_away}`, apifootball: `${xh}-${xa}` });
        continue;
      }
    }

    // a draw with no shootout data yet → wait (needs the penalty winner)
    if (isDraw && (p_home_pen === null || p_away_pen === null)) {
      waiting.push({ id: m.id, match: `${m.home_team} vs ${m.away_team}`, reason: "draw awaiting shootout result" });
      continue;
    }

    const rec = {
      id: m.id, match: `${m.home_team} vs ${m.away_team}`,
      result: `${p_home}-${p_away}${p_home_pen !== null ? ` (pens ${p_home_pen}-${p_away_pen})` : ""}`,
      crossChecked: !!x,
    };
    if (dry) { approved.push({ ...rec, dry: true }); continue; }
    try {
      await setResult(m, p_home!, p_away!, p_home_pen, p_away_pen);
      approved.push(rec);
    } catch (e) {
      conflicts.push({ id: m.id, match: rec.match, error: String(e) });
    }
  }

  return new Response(JSON.stringify({ ok: true, dry, approved, conflicts, waiting, liveUpdated }, null, 2), {
    headers: { "Content-Type": "application/json" },
  });
});
