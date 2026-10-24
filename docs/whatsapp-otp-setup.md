# WhatsApp OTP rollout — iPhone

Status: local hardening only; not deployed or enabled. Meta account and hosted Supabase settings have not been inspected.

## Architecture

Keep Supabase Auth responsible for generating and verifying OTP and issuing sessions. Its Send SMS Hook delivers the generated code through Meta. The hook affects phone authentication delivery project-wide, including other clients and phone changes. It does not provide a per-request SMS/WhatsApp selector.

The current iPhone UI still labels the default request as SMS and its optional WhatsApp path describes Twilio. Before enabling the hook, align delivery labels and channel behavior across clients sharing the Supabase project. Do not just turn on `whatsappOTPEnabled`.

## Required setup

1. In Meta Developers, select or create the app supporting WhatsApp and associate the intended business portfolio and WhatsApp Business Account.
2. Start with Meta test resources and an allowed test recipient. Prepare the intended production sender separately and complete any account-specific registration, billing, or eligibility steps shown by Meta.
3. Prepare an approved Authentication template with a copy-code button. Record its exact template name and language. Confirm the template body and button accept the same OTP.
4. Configure a production access token for the intended system user and sender with `whatsapp_business_messaging` permission. Template management may require additional permissions. Never put this token in the iPhone app or chat.
5. In Supabase Edge Function secrets, set `WHATSAPP_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`, `WHATSAPP_TEMPLATE`, `WHATSAPP_TEMPLATE_LANG`, and a currently supported `WHATSAPP_API_VERSION`. The existing v26.0 default has not been verified against Meta documentation in this review.
6. Create the Send SMS HTTP hook pointing to the deployed `send-sms-whatsapp` function. Save its signing secret as `SEND_SMS_HOOK_SECRET`. JWT gateway verification is disabled because the function verifies the webhook signature itself.
7. Confirm Phone Auth, six-digit OTP, suitable expiration, resend limits, and abuse controls in hosted Supabase. Local configuration alone does not establish hosted settings.

Keep the hook disabled until the client labels, approved template, secrets, and staging checks are ready. Configure secrets using the provider dashboard; do not paste them into commands, screenshots, tickets, or chat.

## Verification

Local: `npx --yes deno test --allow-env supabase/functions/send-sms-whatsapp/index_test.ts`.

Staging with a consented test number: request code, receive it, verify it, confirm a real Supabase session and protected database access. Check wrong, expired, reused codes and resend throttling. Check existing accounts, new accounts, phone changes, and other clients using the same project. API acceptance alone does not prove delivery.

Disable the hook to revert delivery only if the previous SMS provider remains configured and has been tested. Recheck client labels after rollback.

## Review findings addressed

- Reject malformed recipient types, malformed international numbers, non-string OTP, and OTP lengths other than six digits.
- Validate template and endpoint configuration.
- Bound Meta connection wait to four seconds; map network failures to a controlled response.
- Log only numeric provider status/code; never provider message text, token, recipient, or OTP.

## References

- https://supabase.com/docs/guides/auth/auth-hooks/send-sms-hook
- https://developers.facebook.com/apps/
- https://business.facebook.com/wa/manage

Meta documentation could not be fetched during this review. Confirm current Meta requirements in the account before deployment.
