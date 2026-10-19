// send-sms-whatsapp — رمز الدخول عبر واتساب من ميتا مباشرة (طلب المالك ٢٠٢٦-١٠-١٣ «الربط من ميتا مو منصة أخرى»).
//
// هذي «Send SMS Hook» في Supabase Auth: لما تفعَّل من لوحة Supabase (Authentication ← Hooks ← Send SMS)
// كل رمز تحقق (الدخول، تغيير الرقم) يمر من هنا بدل مزوّد الرسائل، ونرسله بقالب «مصادقة» معتمد من ميتا
// عبر WhatsApp Cloud API. الرمز نفسه يولّده Supabase ويتحقق منه — التطبيقات ما تتغيّر في الإرسال والتحقق.
//
// التراجع: إطفاء الـ Hook من لوحة Supabase يرجّع الرسائل النصية القديمة فوراً.
//
// الأسرار (Edge Functions ← Secrets) — يضيفها المالك بنفسه:
//   SEND_SMS_HOOK_SECRET      سر التوقيع اللي تولّده لوحة Supabase عند تفعيل الـ Hook (v1,whsec_…)
//   WHATSAPP_TOKEN            توكن دائم لمستخدم النظام في ميتا (whatsapp_business_messaging)
//   WHATSAPP_PHONE_NUMBER_ID  معرّف رقم الإرسال من WhatsApp Manager (مو الرقم نفسه)
//   WHATSAPP_TEMPLATE         اسم قالب المصادقة (افتراضي family_login_code)
//   WHATSAPP_TEMPLATE_LANG    لغة القالب (افتراضي ar)
//   WHATSAPP_API_VERSION      إصدار Graph API (افتراضي v26.0 — نفس مستكشف ميتا ٢٠٢٦-١٠)
import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";

type HookPayload = {
  user: { id: string; phone: string };
  sms: { otp: string };
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

/// خطأ يرجع لـ Supabase Auth — رسالته توصل للتطبيق
const hookError = (message: string, status = 500) =>
  json({ error: { http_code: status, message } }, status);

/// أرقام فقط بدون + أو 00 — Cloud API ياخذ الرقم الدولي أرقام بس
function waNumber(phone: string): string {
  const digits = (phone ?? "").replace(/\D/g, "");
  return digits.startsWith("00") ? digits.slice(2) : digits;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("not allowed", { status: 405 });

  const secret = Deno.env.get("SEND_SMS_HOOK_SECRET")?.replace("v1,whsec_", "");
  const token = Deno.env.get("WHATSAPP_TOKEN");
  const phoneNumberId = Deno.env.get("WHATSAPP_PHONE_NUMBER_ID");
  if (!secret || !token || !phoneNumberId) {
    console.error("[send-sms-whatsapp] secrets missing");
    return hookError("WhatsApp sender is not configured");
  }

  // توقيع Supabase — أي طلب من غيره ينرفض (ما نرسل رسائل لأي أحد يطلب)
  let payload: HookPayload;
  try {
    const raw = await req.text();
    payload = new Webhook(secret).verify(raw, Object.fromEntries(req.headers)) as HookPayload;
  } catch {
    return hookError("invalid signature", 401);
  }

  const to = waNumber(payload.user?.phone);
  const otp = payload.sms?.otp ?? "";
  if (to.length < 8 || !/^\d{4,10}$/.test(otp)) return hookError("bad payload", 400);

  const template = Deno.env.get("WHATSAPP_TEMPLATE") ?? "family_login_code";
  const lang = Deno.env.get("WHATSAPP_TEMPLATE_LANG") ?? "ar";
  const version = Deno.env.get("WHATSAPP_API_VERSION") ?? "v26.0";

  // قالب «مصادقة» بزر «نسخ الرمز»: الرمز في النص وفي الزر
  const res = await fetch(`https://graph.facebook.com/${version}/${phoneNumberId}/messages`, {
    method: "POST",
    headers: { "Authorization": `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      messaging_product: "whatsapp",
      recipient_type: "individual",
      to,
      type: "template",
      template: {
        name: template,
        language: { code: lang },
        components: [
          { type: "body", parameters: [{ type: "text", text: otp }] },
          { type: "button", sub_type: "url", index: "0", parameters: [{ type: "text", text: otp }] },
        ],
      },
    }),
  });

  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    const code = body?.error?.code;
    // ما نطبع الرقم ولا الرمز في السجل
    console.error("[send-sms-whatsapp] meta error", res.status, code, body?.error?.error_subcode, body?.error?.message);
    if (code === 131026) return hookError("This number is not on WhatsApp", 400);
    if (code === 131047 || code === 131049) return hookError("WhatsApp could not deliver the code, try again later", 429);
    return hookError("WhatsApp send failed");
  }

  return json({});
});
