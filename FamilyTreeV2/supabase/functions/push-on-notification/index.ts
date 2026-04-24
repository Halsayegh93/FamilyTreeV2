import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { handleCors, json } from "../_shared/cors.ts";
import { createServiceClient } from "../_shared/auth.ts";
import { createApnsJwt, getApnsConfig, apnsHostFor } from "../_shared/apns.ts";

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const body = await req.json();
    const record = body.record || body;
    const targetMemberId = record.target_member_id;
    const title = record.title || "عائلة المحمدعلي 🌿";
    const notifBody = record.body || "لديك إشعار جديد";
    const kind = record.kind || "notification";

    const supabase = createServiceClient();
    const { teamId, keyId, bundleId, privateKey } = getApnsConfig();

    // جلب tokens: إما لعضو محدد أو broadcast للجميع (مع environment)
    let query = supabase
      .from("device_tokens")
      .select("token, environment")
      .in("platform", ["ios", "ipados"]);

    if (targetMemberId) {
      query = query.eq("member_id", targetMemberId);
    }
    // إذا target_member_id = NULL → broadcast لكل الأجهزة المسجلة

    const { data: rows, error: tokensErr } = await query;
    if (tokensErr) {
      console.error(`[push-on-notification] DB error: ${tokensErr.message}`);
      return json(500, { ok: false, message: tokensErr.message });
    }

    const tokenEntries = (rows || [])
      .map((r: any) => ({ token: r.token?.trim(), env: r.environment as string | null }))
      .filter((e: any) => e.token && e.token.length > 20);

    console.log(
      `[push-on-notification] target=${targetMemberId ?? "BROADCAST"}, tokens=${tokenEntries.length}, kind=${kind}`
    );

    if (!tokenEntries.length) {
      return json(200, { ok: true, sent: 0, message: "No valid tokens" });
    }

    const jwt = await createApnsJwt(teamId, keyId, privateKey);
    let sent = 0;
    const failures: Array<{ token: string; status: number; reason: string; env: string | null }> = [];

    for (const entry of tokenEntries) {
      const { token, env } = entry;
      const host = apnsHostFor(env);
      const res = await fetch(`${host}/3/device/${token}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${jwt}`,
          "apns-topic": bundleId,
          "apns-push-type": "alert",
          "apns-priority": "10",
        },
        body: JSON.stringify({
          aps: { alert: { title, body: notifBody }, sound: "default" },
          kind,
        }),
      });
      if (res.ok) {
        sent++;
      } else {
        const reason = await res.text();
        failures.push({ token: token.substring(0, 8) + "...", status: res.status, reason, env });
        if (res.status === 410) {
          await supabase.from("device_tokens").delete().eq("token", token);
        }
      }
    }

    return json(200, { ok: true, sent, total: tokenEntries.length, failed: failures.length, failures });
  } catch (e) {
    console.error(`[push-on-notification] Exception: ${(e as Error).message}`);
    return json(500, { ok: false, message: (e as Error).message });
  }
});
