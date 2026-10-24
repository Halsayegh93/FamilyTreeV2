# KWT SMS / Supabase Auth

Status (2026-10-19): function and guard migration deployed to the linked Family tree app project. Six local handler tests, type-checking, lint and rollback-only database guard tests passed. KWT credentials and transactional Sender ID are missing; hosted Auth has not been switched, provider test=1 and device delivery are not yet tested.

Implementation: `supabase/functions/send-sms-kwtsms`. Supabase generates and verifies OTPs and issues sessions. This signed HTTP Send SMS Hook only delivers them. Existing AWS `sms-hook` remains unchanged; no hosted Auth switch is made by deploying this function.

## Implemented

- Fixed HTTPS POST JSON provider endpoint, credentials from Edge Secrets only, Arabic/English fixed branded messages and six ASCII-digit OTP validation.
- Kuwait mobile destinations only (`965` plus eight digits starting 4/5/6/9); leading `+`/`00` normalized. Other countries, spaces, Unicode digits and bulk recipients rejected.
- Standard Webhooks signature/timestamp verification, bounded request body, provider timeout, sanitized errors, no automatic retry on ambiguous outcomes.
- Atomic PostgreSQL reservations across Edge instances: 3-minute phone cooldown, 5 attempts per phone/hour, 5 reservations/second and 100 total/hour as initial budget caps. The hook cannot reliably see the original user's IP: IP and bot protection must be configured at Supabase Auth, not based on the webhook caller's IP.
- HMAC identifiers only; no phone, OTP, message or credentials in database/logs. Two-day lazy retention. Accepted webhook duplicates do not resend; pending/failed/unknown duplicates fail closed. Test and production event identities are separate.
- Provider message ID, charged points and remaining balance stored for operations; no balance API request per send. API acceptance is not proof of handset delivery. Kuwait DLR is unavailable per provider docs.

## Secrets (enter in Supabase dashboard, never in chat)

`KWTSMS_USERNAME`, `KWTSMS_PASSWORD`: API information credentials, not account login.
`KWTSMS_SENDER`: exact approved sender. `KWT-SMS` allowed only for test mode.
`KWTSMS_HASH_KEY`: random independent key of at least 32 bytes; keep stable for rate limits.
`KWTSMS_TEST_MODE`: defaults to safe `true`; set exact `false` only after production prerequisites.
`KWTSMS_LANGUAGE`: `ar` (default) or `en`.
`SEND_SMS_HOOK_SECRET`: signing secret matching the selected Supabase Auth hook.
Built-in `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are used only server-side.

## Activation gates

1. Obtain a private transactional Sender ID from KWT SMS. No business eligibility is assumed. Confirm required documents directly with KWT SMS.
2. Add API credentials and settings to Edge Secrets, without replacing other providers' secrets.
3. Test a signed synthetic hook directly with `test=1`, Arabic and English. Safe test mode deliberately returns a controlled 503 even on provider acceptance, so it must not be selected as the production Auth hook. Check database outcome/metrics, not HTTP success, for these tests.
4. In hosted Auth, review Phone provider/signup policy, OTP length 6, expiry 240 seconds, SMS minimum frequency 180 seconds, IP limits for OTP request and verification, and overall SMS budget. Do not push this repo's entire local Auth configuration to production.
5. Add CAPTCHA/bot protection with compatible clients before enabling enforcement. Existing clients do not yet submit a CAPTCHA token; turning it on blindly breaks login. Client resend countdown should match the 180-second server policy before rollout.
6. After provider test validation, register a new HTTP Send SMS Hook pointing to `https://poxyxsgvzwmnmewytsiw.supabase.co/functions/v1/send-sms-kwtsms`, configure its matching secret, set test mode false with the approved transactional sender, then perform one authorized real-device end-to-end login. The hook affects all phone-auth clients and phone changes in this project.
7. Set operational alerts for failed/unknown outcomes, low `balance_after`, and send volume. Never alert with phone numbers or OTPs. These alerts are not provisioned by this code.
8. Rollback: restore the prior hosted AWS `sms-hook` URL and its original signing secret; this is not equivalent to merely disabling the hook. Preserve existing hosted settings before switching.

## Checks

`npx --yes deno test --allow-env supabase/functions/send-sms-kwtsms/handler_test.ts`
`npx --yes deno check supabase/functions/send-sms-kwtsms/index.ts`
`supabase db query --linked --file supabase/tests/kwtsms_guard.sql`

## Sources

- https://www.kwtsms.com/articles/sms-api-implementation-best-practices.html
- https://www.kwtsms.com/api-documentation.html (current JSON API takes precedence over legacy form-encoded article example)
- https://supabase.com/docs/guides/auth/auth-hooks/send-sms-hook
- https://supabase.com/docs/guides/auth/rate-limits
