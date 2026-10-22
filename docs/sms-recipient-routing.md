# SMS recipient routing repair — 2026-10-23

The hook used `user.phone` as the recipient for every SMS. On the deployed Auth
version, v2.197.0, `sms.phone` is the delivery destination. During a phone change,
`user.phone` can still contain the original account number. The old hook could
therefore send a phone-change OTP to the original number and record that number
as having a sign-in request. A mocked signed payload reproduces that failure.

The hook now uses `sms.phone` whenever that field is present. Invalid or
unsupported explicit destinations are rejected before reservation or sending;
they never fall back to the account number. Unambiguous old payloads retain the
legacy `user.phone` fallback. Ambiguous old payloads with a pending phone change
are rejected. Hashes, throttling and attempt logs use the actual SMS destination.
An explicit normal sign-in still works while a different number is pending.

OTPs identified as phone-change, MFA or other non-login verification are not
written to the owner's private sign-in-code store. Legacy same-account payloads
retain their existing behavior; an absent type is not proof of a human action.
Optional audit metadata records the recipient source, SMS
purpose, and the signed Auth origin IP and hook UUID. Unsigned edge headers are
not used for client attribution. The service-only writer validates these fields;
the existing owner-only reader can expose them, and masked admin responses do
not include them. An IP or recipient match does not identify the human who
initiated a request. Existing records are retained without guessed backfills.

Apply `20261023010000_sms_recipient_routing_audit.sql`, then deploy only
`send-sms-kwtsms`. The routing repair is server-side and needs no app rebuild.
The rollback restores the previous metadata allowlist while retaining history;
it deliberately does not undo the hook's recipient repair.

Validation uses signed synthetic payloads and a mocked provider, including
different account/destination numbers, malformed and international destinations,
legacy ambiguity, pending changes, MFA, audited source fields and private-code
isolation. The PostgreSQL suite checks allowlists, role restrictions and rollback.
Do not send a real SMS to validate this repair.

The mocked hook suite passed 25 test groups and the isolated PostgreSQL suite
passed 66 assertions. A production unsigned request was rejected before any
reservation, SMS or attempt record. Historical attempts were preserved.

Upstream contract used for verification:

- https://github.com/supabase/auth/blob/v2.197.0/internal/api/phone.go#L89-L99
- https://github.com/supabase/auth/blob/v2.197.0/internal/hooks/v0hooks/v0hooks.go#L208-L224
