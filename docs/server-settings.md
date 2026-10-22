# Server settings release — 2026-10-21

The iOS source is based on `ios/admin-redesign-2026-10-20` at `12f46ecb`, with the compact family summary / persistent attention panel from `bd3abb02`. The implementation branch is `codex/admin-family-summary`.

## Owner workflow

Open **لوحة الإدارة → التطبيق → إعدادات السيرفر → القيم والنصوص من السيرفر**. Search or open a category, edit the value, and save. Preset announcement titles are entered one per line. The server validates every value, restricts writes to the owner, and records old/new values, the actor ID and a snapshot of their name. The admin role can read settings and the latest 100 history entries.

Restoring a single default uses the same validated API and creates an audit entry if the value changes. The existing app settings, SMS limits, sender selection, approval SLA settings and death-alert duration keep their existing editors; they are not duplicated here.

## Published values and consumers

| Category | Keys | Consumer |
| --- | --- | --- |
| Members | `living_check_old_birth_year`, `living_check_median_year`, `living_check_min_births` | iOS living-member verification |
| Members | `activity_heartbeat_seconds` | iOS activity timer, 30–600 seconds |
| News | `news_max_photos` | iOS add/edit pickers, combined existing/new photo limit; existing posts remain editable |
| News | `report_review_hours` | iOS report receipts and terms text |
| Announcements | `announce_preset_titles` | iOS announcement composer |
| Notifications | `notify_join_approved_title`, `notify_join_approved_body` | iOS legacy join approval notification |
| Notifications | `notify_news_like_title`, `notify_news_like_body`, `notify_news_like_admin_body` | iOS news-like push and in-app notifications |
| Notifications | `notify_news_comment_title`, `notify_news_comment_body`, `notify_news_comment_admin_body` | iOS comment push and in-app notifications |
| Approvals | `approvals_info_hours` | Server reminder job and approvals report |
| Deaths | `death_announce_window_days`, `death_announce_template_male`, `death_announce_template_female` | Server `announce_death` and iOS announcement composer |
| SMS | `sms_suspicious_per_hour` | Server suspicious-attempt reporting and alerts |
| SMS | `sms_otp_template`, `sms_otp_template_en` | Published `send-sms-kwtsms` hook via reservation format 3 |
| Links | `site_url`, `privacy_url`, `privacy_url_en`, `terms_url`, `terms_url_en`, `support_email` | iOS family links, available before login |
| General | `greeting_morning_start_hour`, `greeting_afternoon_start_hour`, `greeting_evening_start_hour` | iOS greeting and time artwork |

There are **31 active keys**. The draft's profile-edit enforcement, terms-version enforcement, age bands, and branch topology were excluded because they are separate behavioral changes whose consumers were not migrated. Their current behavior is preserved. `death_alert_days` remains an `app_settings` value (1–30 days, default 7), separate from the allowed death-announcement window.

## Refresh and compatibility

Server-side consumers use the next stored value on their next call. The updated iOS app refreshes on login/session-state changes, return to the foreground, admin dashboard refresh and settings-page refresh. Saving immediately refreshes the in-memory settings. This is refresh-based, not a realtime subscription.

Only public link values persist between launches; member values and owner metadata are cleared across sessions. Requests from an older session cannot overwrite a newer session's values. Missing keys, wrong types and failed network reads fall back safely. Unchanged notification defaults retain the app's existing Arabic/English translations; custom notification text is sent as entered by the owner. Existing app versions continue to work with the old SMS reservation contracts.

The Flutter client was not modified in this release; it must adopt the same APIs before its client-side constants respond to these values. Server-side SMS / approvals / announcement behavior is shared immediately.

## Production deployment

Project: `poxyxsgvzwmnmewytsiw`.

Applied in one transaction with a deployment advisory lock and checks that all six replaced live function bodies matched their reviewed baselines:

1. `20261021100000_death_alert_days` (column already existed; idempotent).
2. `20261021110000_app_config`.
3. `20261021120000_app_config_server_reads`.

All three versions were recorded in `supabase_migrations.schema_migrations`, and PostgREST's schema cache was reloaded. All 31 values stayed at their defaults. Published only the `send-sms-kwtsms` Edge Function, preserving its signature validation and existing configuration/secrets.

The restored October 20–21 historical SMS migrations are test prerequisites already present in production; they were not replayed during this deployment.

## Verification

- `node supabase/tests/family_links/app_config.test.mjs`: 170 checks passed.
- `node supabase/tests/family_links/app_config_server_reads.test.mjs`: 72 checks passed, including rollback/reapply and backwards-compatible reservation formats.
- `npx --yes deno test --allow-net supabase/functions/send-sms-kwtsms/handler_test.ts`: 17 tests passed with mocked provider requests.
- `python3 supabase/tests/family_links/remote_settings_client_test.py`: 16 Swift checks passed for types, limits, placeholders, translations and cache isolation.
- Eight production SQL checks passed for public/owner/admin scopes, grants, history and recorded migrations.
- Public API reachable; anonymous member-config access and edits denied; unsigned SMS hook requests rejected. No real SMS was sent for verification.
- Signed iPhone Debug build passed. Device installation is recorded in the release chat.

## Rollback

First redeploy the previous `send-sms-kwtsms` handler (reservation format 2). Run `20261021120000_app_config_server_reads_rollback.sql`, then `20261021110000_app_config_rollback.sql`; record their reverted migration status. The second rollback refuses to run while database functions still depend on `config_*`. The new iOS app falls back to bundled defaults after the RPCs disappear. Keep `death_alert_days` to retain its existing production behavior unless explicitly reverting that feature separately.
