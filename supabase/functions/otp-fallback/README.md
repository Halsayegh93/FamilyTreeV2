# otp-fallback (Supabase Edge Function)

قالب جاهز لقناة بديلة عند فشل إرسال OTP عبر SMS.

## الفكرة

- التطبيق يستدعي endpoint بديل عند فشل SMS.
- الدالة تحاول القنوات بالترتيب: `whatsapp` ثم `call`.
- تدعم مزودين:
  - `twilio` (افتراضي)
  - `webhook` (للربط مع مزودك الحالي)
  - `unifonic` (مناسب للسوق الخليجي)

## ملاحظة مهمة

هذا القالب مسؤول عن **الإرسال البديل** فقط.
إذا كنت تتحقق من الكود عبر Supabase (`verifyOTP`)، فتأكد أن القناة البديلة ترسل **نفس كود التحقق الصادر من Supabase** أو استخدم تدفق تحقق موحد في مزود واحد.

## الملفات

- `index.ts`: منطق الدالة
- `.env.example`: متغيرات البيئة المطلوبة

## إعداد المتغيرات

1. انسخ القيم من `.env.example`.
2. اضبطها عبر:

```bash
supabase secrets set --env-file supabase/functions/otp-fallback/.env.example
```

## تشغيل محلي

```bash
supabase functions serve otp-fallback --no-verify-jwt
```

## نشر

```bash
supabase functions deploy otp-fallback --no-verify-jwt
```

## اختبار سريع

```bash
curl -i -X POST "https://<PROJECT_REF>.supabase.co/functions/v1/otp-fallback" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <OTP_FALLBACK_API_KEY>" \
  -d '{"phone":"+96551234567","channels":["whatsapp","call"]}'
```

استجابة نجاح:

```json
{
  "accepted": true,
  "channel": "whatsapp",
  "message": "Fallback sent via whatsapp"
}
```

## ربط iOS

في `Info.plist` للتطبيق أضف:

- `OTP_FALLBACK_URL`
- `OTP_FALLBACK_API_KEY`

مثال:

- `OTP_FALLBACK_URL = https://<PROJECT_REF>.supabase.co/functions/v1/otp-fallback`
- `OTP_FALLBACK_API_KEY = <same-secret>`

## تفعيل Unifonic مباشرة

1. عدل:
   - `FALLBACK_PROVIDER=unifonic`
2. ضع القيم:
   - `UNIFONIC_ACCESS_TOKEN`
   - `UNIFONIC_WHATSAPP_APP_SID`
   - `UNIFONIC_WHATSAPP_SENDER`
   - `UNIFONIC_VOICE_CALLER_ID`
3. أعد نشر الدالة.
