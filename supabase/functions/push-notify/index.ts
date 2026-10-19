// push-notify — معطّلة (لا ترسل شيئاً) منذ ٢٠٢٦-١٠-٠٤ (فحص الثغرات).
//
// الدفع كله يخرج من مشغّل جدول notifications (trg_push_on_notification ← push-on-notification)
// عند إدراج أي إشعار. هذه الدالة كانت تكرّر الدفع لأجهزة الآيفون (الموقع والنسخ القديمة
// تُدرج الإشعار ثم تستدعيها)، وكانت تسمح للمراقب والمشرف بإرسال نص حر لكل الأجهزة
// خلافاً للصلاحيات. التطبيقات الحالية لا تستدعيها. الكود القديم في تاريخ git.
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve((req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  return new Response(
    JSON.stringify({
      ok: true,
      sent: 0,
      message: "push-notify is disabled — pushes are sent by the notifications trigger on insert",
    }),
    { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});
