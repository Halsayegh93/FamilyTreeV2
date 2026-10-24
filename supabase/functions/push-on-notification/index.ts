import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { handleCors, json } from "../_shared/cors.ts";
import { createServiceClient } from "../_shared/auth.ts";
import { createApnsJwt, getApnsConfig, apnsHostFor } from "../_shared/apns.ts";
import { getFcmServiceAccount, getFcmAccessToken, sendFcm } from "../_shared/fcm.ts";

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  // أمان: لا تُستدعى إلا من dispatch المجدول (cron) عبر سرّ مشترك.
  // يمنع أي شخص على الإنترنت من بثّ إشعارات (verify_jwt=false في البوابة).
  const expectedSecret = Deno.env.get("PUSH_WEBHOOK_SECRET");
  const providedSecret = req.headers.get("x-webhook-secret");
  if (!expectedSecret || providedSecret !== expectedSecret) {
    console.warn("[push-on-notification] rejected: missing/invalid webhook secret");
    return json(401, { ok: false, message: "Unauthorized" });
  }

  try {
    const body = await req.json();
    const record = body.record || body;
    const targetMemberId = record.target_member_id;
    const title = record.title || "عائلة المحمدعلي 🌿";
    const notifBody = record.body || "لديك إشعار جديد";
    const kind = record.kind || "notification";
    const isJoinRequest = record.request_type === "join_request" || record.request_type === "link_request";

    const supabase = createServiceClient();
    const { teamId, keyId, bundleId, privateKey } = getApnsConfig();

    // جلب tokens: إما لعضو محدد أو broadcast للجميع (مع environment)
    let query = supabase
      .from("device_tokens")
      .select("token, environment")
      .in("platform", ["ios", "ipados"]);

    // أجهزة الأندرويد (FCM) — كانت لا تُرسَل إطلاقاً فلا يصل للأندرويد شيء والتطبيق مغلق
    let androidQuery = supabase
      .from("device_tokens")
      .select("token")
      .eq("platform", "android");
    if (targetMemberId) {
      androidQuery = androidQuery.eq("member_id", targetMemberId);
    }
    const { data: androidRows } = await androidQuery;
    const androidTokens = (androidRows || [])
      .map((r: any) => (r.token as string | null)?.trim())
      .filter((t: string | undefined): t is string => !!t && t.length > 20);

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

    let sent = 0;
    const failures: Array<{ token: string; status: number; reason: string; env: string | null }> = [];

    // ── الأندرويد عبر FCM ──
    let androidSent = 0;
    if (androidTokens.length) {
      const sa = getFcmServiceAccount();
      if (!sa) {
        console.error("[push-on-notification] FCM_SERVICE_ACCOUNT_JSON missing/invalid");
      } else {
        try {
          const accessToken = await getFcmAccessToken(sa);
          for (const token of androidTokens) {
            const r = await sendFcm(sa, accessToken, token, title, notifBody, kind);
            if (r.ok) {
              androidSent++;
            } else {
              failures.push({ token: token.substring(0, 8) + "...", status: r.status, reason: r.reason ?? "", env: "android" });
              if (r.unregistered) {
                await supabase.from("device_tokens").delete().eq("token", token);
              }
            }
          }
        } catch (e) {
          console.error(`[push-on-notification] FCM error: ${(e as Error).message}`);
          failures.push({ token: "fcm", status: 0, reason: (e as Error).message, env: "android" });
        }
      }
    }

    if (!tokenEntries.length) {
      return json(200, {
        ok: true, sent: androidSent, total: androidTokens.length,
        android: { sent: androidSent, total: androidTokens.length },
        failed: failures.length, failures,
      });
    }

    const jwt = await createApnsJwt(teamId, keyId, privateKey);

    for (const entry of tokenEntries) {
      const { token, env } = entry;
      const sendApns = (host: string) => fetch(`${host}/3/device/${token}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${jwt}`,
          "apns-topic": bundleId,
          "apns-push-type": "alert",
          "apns-priority": "10",
        },
        body: JSON.stringify({
          aps: {
            alert: { title, body: notifBody }, sound: "default",
            ...(isJoinRequest ? { category: "JOIN_REQUEST" } : {}),
          },
          kind,
          ...(typeof record.request_id === "string" ? { request_id: record.request_id } : {}),
          ...(typeof record.request_type === "string" ? { request_type: record.request_type } : {}),
          ...(typeof record.notification_id === "string" ? { notification_id: record.notification_id } : {}),
        }),
      });
      const res = await sendApns(apnsHostFor(env));
      if (res.ok) {
        sent++;
        continue;
      }
      const reason = await res.text();
      failures.push({ token: token.substring(0, 8) + "...", status: res.status, reason, env });
      if (res.status === 410) {
        await supabase.from("device_tokens").delete().eq("token", token);
      } else if (res.status === 400 && reason.includes("BadDeviceToken")) {
        // ٢٠٢٦-١٠-٢١ (موافقة المالك): BadDeviceToken = التوكن لبيئة Apple الثانية (نسخة تجريبية ↔ متجر) أو ميت.
        // محاولة واحدة على البيئة الثانية: قبلته ← وصل الإشعار ونصحّح العمود؛ رفضته كذلك ← التوكن ميت فيُحذف.
        const otherEnv = env === "sandbox" ? "production" : "sandbox";
        const retry = await sendApns(apnsHostFor(otherEnv));
        if (retry.ok) {
          sent++;
          failures.pop();
          await supabase.from("device_tokens").update({ environment: otherEnv }).eq("token", token);
        } else {
          const retryReason = await retry.text();
          if (retry.status === 410 || (retry.status === 400 && retryReason.includes("BadDeviceToken"))) {
            await supabase.from("device_tokens").delete().eq("token", token);
          }
        }
      }
    }

    return json(200, {
      ok: true,
      sent: sent + androidSent,
      total: tokenEntries.length + androidTokens.length,
      ios: { sent, total: tokenEntries.length },
      android: { sent: androidSent, total: androidTokens.length },
      failed: failures.length,
      failures,
    });
  } catch (e) {
    console.error(`[push-on-notification] Exception: ${(e as Error).message}`);
    return json(500, { ok: false, message: (e as Error).message });
  }
});
