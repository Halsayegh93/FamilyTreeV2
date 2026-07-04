// ============================================================================
// Configuration — fill these in before using the site.
// ============================================================================

// 1) Create a free Supabase project at https://supabase.com (or reuse one).
// 2) Run db.sql in the Supabase SQL Editor.
// 3) Project Settings → API → paste the URL and the anon/publishable key here.
export const SUPABASE_URL = 'https://vnyhbppzufadqxpbijnb.supabase.co';
export const SUPABASE_ANON_KEY = 'sb_publishable_OPnob-SkO9u-Z7PN7tYTog_paKjdBTJ';

// Points. The match result is judged on the score BEFORE penalties:
//   5 — exact score
//   3 — correct winner AND the winning team's goals correct, OR a correct draw
//   1 — correct winner only (score wrong)
//   0 — wrong outcome
// Penalty-shootout matches (draw predicted + match actually reached pens):
//   7 — exact draw score + correct shootout winner
//   5 — different draw score + correct shootout winner
//   3 — exact draw score + wrong shootout winner
//   0 — different draw score + wrong shootout winner
export const POINTS = {
  exact: 5,        // exact score
  winnerScore: 3,  // correct winner + winning team's goal count
  draw: 3,         // correct draw outcome (not exact), match decided without pens
  winner: 1,       // correct winner only
  pensExactRight: 7,  // exact draw score + correct shootout winner
  pensDiffRight: 5,   // different draw score + correct shootout winner
  pensExactWrong: 3,  // exact draw score + wrong shootout winner
  champion: 50,       // picked the World Cup champion (one pick, locks at the end of R16)
};

// The admin PIN is validated SERVER-SIDE inside db.sql (search for CHANGE_ME).
// Change it there. This site never trusts a client-side password.
