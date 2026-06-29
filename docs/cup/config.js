// ============================================================================
// Configuration — fill these in before using the site.
// ============================================================================

// 1) Create a free Supabase project at https://supabase.com (or reuse one).
// 2) Run db.sql in the Supabase SQL Editor.
// 3) Project Settings → API → paste the URL and the anon/publishable key here.
export const SUPABASE_URL = 'https://vnyhbppzufadqxpbijnb.supabase.co';
export const SUPABASE_ANON_KEY = 'sb_publishable_OPnob-SkO9u-Z7PN7tYTog_paKjdBTJ';

// Points system. The match result uses the highest matching tier (not additive):
//   7 — exact score: both teams' goals predicted correctly
//   5 — correct winner AND the winning team's goals correct (loser's wrong)
//   3 — correct winner only, score wrong
//   0 — wrong winner / wrong outcome
// A knockout decided on penalties adds a bonus (same principle, on the pen score):
//   +2 — exact penalty-shootout score
//   +1 — correct penalty qualifier only
export const POINTS = {
  exact: 7,        // both teams' goals correct
  winnerScore: 5,  // right winner + winning team's score right
  winner: 3,       // right winner only
  penExact: 2,     // bonus: exact penalty-shootout score
  penWinner: 1,    // bonus: correct penalty qualifier only
};

// The admin PIN is validated SERVER-SIDE inside db.sql (search for CHANGE_ME).
// Change it there. This site never trusts a client-side password.
