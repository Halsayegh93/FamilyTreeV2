// ============================================================================
// Configuration — fill these in before using the site.
// ============================================================================

// 1) Create a free Supabase project at https://supabase.com (or reuse one).
// 2) Run db.sql in the Supabase SQL Editor.
// 3) Project Settings → API → paste the URL and the anon/publishable key here.
export const SUPABASE_URL = 'https://YOUR-PROJECT.supabase.co';
export const SUPABASE_ANON_KEY = 'YOUR-ANON-OR-PUBLISHABLE-KEY';

// Points system (highest matching tier wins — not additive):
//   5 — exact score: both teams' goals predicted correctly
//   3 — correct winner AND the winning team's goals correct (loser's wrong)
//   1 — correct winner only (or a correctly-predicted draw), score wrong
//   0 — wrong winner / wrong outcome
export const POINTS = {
  exact: 5,        // both teams correct
  winnerScore: 3,  // right winner + winning team's score right
  winner: 1,       // right winner / draw only
};

// The admin PIN is validated SERVER-SIDE inside db.sql (search for CHANGE_ME).
// Change it there. This site never trusts a client-side password.
