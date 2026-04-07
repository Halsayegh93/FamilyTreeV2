import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { corsHeaders, handleCors, json } from "../_shared/cors.ts";
import { createServiceClient } from "../_shared/auth.ts";
import { createApnsJwt, getApnsConfig } from "../_shared/apns.ts";

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const body = await req.json();
    const record = body.record || body;
    const targetMemberId = record.target_member_id;
    const title = record.title || "عائلة المحمدعلي 🌿";
    const notifBody = record.body || "لديك إشعار جديد";

    if (!targetMemberId) {
      return json(200, { ok: true, sent: 0, message: "No target" });
    }

    const supabase = createServiceClient();
    const { teamId, keyId, bundleId, privateKey, apnsHost } = getApnsConfig();

    const { data: tokens } = await supabase
      .from("device_tokens")
      .select("token")
      .eq("member_id", targetMemberId)
      .in("platform", ["ios", "ipados"]);

    const validTokens = (tokens || []).map((t: any) => t.token?.trim()).filter((t: string) => t && t.length > 20);
    if (!validTokens.length) {
      return json(200, { ok: true, sent: 0 });
    }

    const jwt = await createApnsJwt(teamId, keyId, privateKey);
    let sent = 0;

    for (const token of validTokens) {
      const res = await fetch(`${apnsHost}/3/device/${token}`, {
        method: "POST",
        headers: { authorization: `bearer ${jwt}`, "apns-topic": bundleId, "apns-push-type": "alert", "apns-priority": "10" },
        body: JSON.stringify({ aps: { alert: { title, body: notifBody }, sound: "default" } }),
      });
      if (res.ok) sent++;
      else if (res.status === 410 || res.status === 400) {
        await supabase.from("device_tokens").delete().eq("token", token);
      }
    }

    return json(200, { ok: true, sent });
  } catch (e) {
    return json(500, { ok: false, message: (e as Error).message });
  }
});
