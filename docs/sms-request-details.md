# SMS request details

Tapping any recipient in KWT SMS opens an SMS case modal, including unregistered
numbers. It does not open a member profile. The sending tiles compare today,
the last seven calendar days and the last thirty calendar days. The separate
request-period selector filters the recipient history; both use Kuwait days.

## Access and data

- The existing `sms_login_attempts` aggregate remains available to owners and
  admins. Admin numbers remain masked and admins do not receive OTPs or the
  detailed provider audit.
- `owner_sms_login_details(p_phone, p_days, p_before)` checks the current role on
  every call and rejects everyone except an active owner. The requested window
  is capped by `login_attempts_retention_days`.
- Each page contains at most 50 attempts, ordered by recorded time and ID. Pass
  `next_before` as `p_before` to read the remaining history without duplicate
  entries when timestamps match. The latest 20 code-access audit entries are
  included with the total access count.
- New requests record request time, result time, sender, provider message ID,
  charged points, resulting balance, provider error/HTTP status and retry wait
  when available. A queue check is saved against that message ID. Old entries
  retain their existing recorded time and outcome; absent metadata is not
  reconstructed or guessed.
- The detailed reader never returns an OTP. The existing
  `owner_reveal_login_code` RPC reveals only the current valid code and records
  the owner, time and outcome of each reveal. Its five-minute lifetime and
  invalidation after sign-in are unchanged.
- iOS keeps a displayed code only in the modal, clears it on backgrounding or
  account/role changes, hides it at expiry, and rechecks availability every 15
  seconds. A replacement requires a new audited reveal. Copying uses a local-only
  clipboard entry expiring with the code.
- Shared recipient caches are scoped to the profile and owner/admin access
  level. Late replies from a previous scope are discarded. A server permission
  denial clears sensitive modal data and refreshes the user's profile.

KWT's status endpoint reports its sending queue, not receipt on a Kuwait
handset: <https://www.kwtsms.com/api-documentation.html>.

## Deployment and compatibility

Apply `20261021160000_sms_request_details.sql` before deploying
`send-sms-kwtsms`. The hook calls the service-only `log_sms_login_attempt`, which
uses the original logger for retention and suspicious-request alerts. It stores
an allowlist of metadata and never stores the OTP or a raw provider/hook payload
in the attempt history. Metadata writes run in parallel with the existing
delivery finalization and transient private-code store.

Only a missing-RPC 404 falls back to the old logger. Timeouts or ambiguous
failures are not retried. Logging failures do not change Auth's response or send
another SMS. The rollback removes the new APIs and restores the queue writer;
captured audit metadata is retained. Old iOS clients keep their existing APIs.
The richer modal is an iOS change; server request logging is shared.

## Validation

```sh
cd supabase/tests/family_links
node sms_request_details.test.mjs
```

The isolated PostgreSQL suite checks 51 conditions covering role/column access,
metadata validation, no OTP in history, code access auditing, used/expired
codes, queue correlation, pagination, retention and rollback/reapply.
`supabase/functions/send-sms-kwtsms/handler_test.ts` additionally checks the
new metadata and 404-only compatibility path with mocked provider calls.
Native UI checks cover recipient routing, masked admin details, pagination,
role changes during code loading, code replacement/sign-in, large text, dark
mode and error/expired/used states. Test fixtures are temporary and are not
included in device builds.
