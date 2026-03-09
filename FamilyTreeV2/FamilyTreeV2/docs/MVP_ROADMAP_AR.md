# FamilyTreeV2 - MVP Plan (المرحلة الأولى)

## ما تم تنفيذه الآن
- إضافة Migration جاهز لـ Supabase في:
  - `supabase/migrations/20260209_001_schema.sql`
- إضافة Seed ببيانات وهمية في:
  - `supabase/seed/seed_dummy.sql`
- تفعيل منطق الأدوار في التطبيق:
  - `member`: ينشر خبر بحالة `pending`
  - `supervisor/admin`: ينشر مباشر `approved`
- إضافة شاشة مراجعة طلبات الأخبار للإدارة:
  - `Views/Features/Admin/AdminNewsRequestsView.swift`

## تدفق الدخول المعتمد
1. دخول برقم الهاتف + OTP
2. إذا ملف المستخدم موجود:
   - `role = pending` => شاشة انتظار الموافقة
   - غير ذلك => دخول التطبيق
3. إذا ملفه غير موجود => شاشة التسجيل

## الجداول الأساسية في MVP
- `profiles`
- `news`
- `admin_requests`
- `diwaniyas`
- `notifications`

## ملاحظات مهمة قبل الإنتاج
- OTP عبر WhatsApp يحتاج مزود خارجي (Twilio/Meta) عبر Edge Functions.
- يجب نقل `Supabase URL/Key` من الكود إلى إعدادات آمنة (`xcconfig` + Build Settings).
- إضافة سياسة حذف حساب المستخدم + صفحة سياسة الخصوصية قبل رفع App Store.

## الخطوة التالية (Phase 2)
- موافقات الديوانيات.
- تعليقات/إعجابات الأخبار.
- إشعارات Push فعلية (APNs + Supabase Edge Functions).
- تقارير PDF حسب العمر/الفرع.
