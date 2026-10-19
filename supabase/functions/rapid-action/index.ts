// rapid-action — موقوفة (فحص الثغرات ٢٠٢٦-١٠-٠٤، بموافقة المالك).
//
// كانت نسخة من contact-email بلا حد الإرسال (deliveryGuard: ٥ رسائل)، فأي حساب مسجّل — حتى
// المعلّق — يقدر يغرق بريد الإدارة برسائل بلا حد. لا يستدعيها أي تطبيق (الآيفون والأندرويد
// والموقع يرسلون عبر contact-email). الكود القديم في تاريخ git (آخر نسخة: الإصدار ٥١).
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
    JSON.stringify({ ok: false, message: "This function is disabled — use contact-email" }),
    { status: 410, headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});
