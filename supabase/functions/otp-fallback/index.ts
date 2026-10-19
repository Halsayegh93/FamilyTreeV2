// otp-fallback — موقوفة (فحص الثغرات ٢٠٢٦-١٠-٠٤).
//
// كانت ترسل واتساب/اتصالاً بنص يحدّده المتصل لأي رقم، بمفتاح ثابت مخزّن داخل التطبيق —
// فمن يستخرج المفتاح يرسل رسائل على حساب العائلة. لا يستعملها أي تطبيق حالي
// (الآيفون والأندرويد والموقع). الكود القديم محفوظ في supabase/archive/otp-fallback-v67/.
// أي بديل مستقبلاً: JWT المستخدم + قالب ثابت + رقم المتصل نفسه + حد للإرسال.
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
    JSON.stringify({ accepted: false, message: "This channel is disabled" }),
    { status: 410, headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});
