// send-web-push — معطّلة (لا ترسل شيئاً) منذ ٢٠٢٦-١٠-٠٤ (فحص الثغرات).
//
// كانت تسمح للمراقب والمشرف بإرسال إشعار ويب بنص حر خلافاً للصلاحيات، ولا يستدعيها أي
// تطبيق ولا الموقع (لا يوجد Service Worker في الموقع) ولا السيرفر. الكود القديم في تاريخ git.
// إن عاد إشعار الويب مستقبلاً: صلاحية المالك/المدير فقط، والإرسال من مشغّل جدول notifications.
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
    JSON.stringify({ ok: true, sent: 0, message: "send-web-push is disabled" }),
    { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});
