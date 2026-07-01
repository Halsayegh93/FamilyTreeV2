# wc-auto-results (World Cup auto-approval)

Scheduled Supabase Edge Function that auto-approves World Cup match results for
the family prediction game (project `vnyhbppzufadqxpbijnb`).

## What it does

Every 10 minutes a `pg_cron` job calls this function. For each match that has
both teams, has kicked off, and is **not finished**, it looks up the real result
and — if the match is over — approves it through `wc_admin_set_result` (which
advances the bracket and recomputes points). Admins can still edit any result;
the function never touches a match that is already `finished` (so manual edits
win).

## Sources

- **ESPN** scoreboard (`site.api.espn.com/.../soccer/fifa.world/scoreboard`) —
  free, no key, and includes penalty-shootout scores. Primary source.
- **API-Football** — optional cross-check. Set the `APIFOOTBALL_KEY` secret to
  enable it. When both sources return a finished result and their regular-time
  scores disagree, the match is reported as a **conflict** and left for a human
  instead of being written.

Team names are matched by a canonicalised name-set (accent-stripped,
punctuation-removed, plus a small alias map, e.g. `Cape Verde Islands`↔
`Cape Verde`, `United States`↔`USA`).

## Secrets / env

| name | required | notes |
|---|---|---|
| `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` | auto | injected by Supabase |
| `CRON_SECRET` | yes | shared secret; must equal the `x-cron-secret` header the cron job sends |
| `WC_ADMIN_PIN` | no | defaults to `1993` (the PIN baked into `wc_admin_set_result`) |
| `APIFOOTBALL_KEY` | no | enables the API-Football cross-check |

> The live deployment has `CRON_SECRET` set; it is intentionally **not** stored
> in this repo. To rotate it, redeploy with a new value and update the cron job
> header (below).

## Deploy

```bash
supabase functions deploy wc-auto-results --project-ref vnyhbppzufadqxpbijnb --no-verify-jwt
supabase secrets set CRON_SECRET=<random> --project-ref vnyhbppzufadqxpbijnb
# optional:
supabase secrets set APIFOOTBALL_KEY=<key> --project-ref vnyhbppzufadqxpbijnb
```

## Schedule (already applied)

```sql
create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.schedule('wc-auto-results', '*/10 * * * *', $job$
  select net.http_post(
    url     := 'https://vnyhbppzufadqxpbijnb.functions.supabase.co/wc-auto-results',
    headers := jsonb_build_object('Content-Type','application/json','x-cron-secret','<CRON_SECRET>'),
    body    := '{}'::jsonb
  );
$job$);
```

## Manual test

```bash
# dry run — reports what it WOULD approve, writes nothing
curl "https://vnyhbppzufadqxpbijnb.functions.supabase.co/wc-auto-results?dry=1" \
  -H "x-cron-secret: <CRON_SECRET>"
```

Response shape: `{ ok, dry, approved[], conflicts[], waiting[] }`.
