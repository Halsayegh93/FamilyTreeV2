# contact-email function

يرسل رسائل "قسم التواصل" إلى البريد الإلكتروني عبر Resend أو SendGrid.

## Environment Variables

- `RESEND_API_KEY` (اختياري إذا كنت تستخدم Resend)
- `SENDGRID_API_KEY` (اختياري إذا كنت تستخدم SendGrid)
- `CONTACT_EMAIL_FROM` مثال: `FamilyTree <no-reply@yourdomain.com>`
- `CONTACT_EMAIL_TO` بريد واحد أو عدة عناوين مفصولة بفاصلة

## Deploy

```bash
supabase functions deploy contact-email
```

## Set secrets

```bash
supabase secrets set RESEND_API_KEY=xxx
# أو بدلها:
supabase secrets set SENDGRID_API_KEY=SG.xxxxx
supabase secrets set CONTACT_EMAIL_FROM="FamilyTree <no-reply@yourdomain.com>"
supabase secrets set CONTACT_EMAIL_TO="you@example.com"
```
