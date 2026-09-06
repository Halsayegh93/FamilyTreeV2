import { deliveryGuard } from "../_shared/delivery-guard.ts";
import { ownsPendingRequest, adminRoles, requestTitle } from "../_shared/admin-request-policy.ts";
import { handleCors, validatePost, json } from "../_shared/cors.ts";
import { createServiceClient, authenticateRequest, parseBody } from "../_shared/auth.ts";
import { createApnsJwt, getApnsConfig, apnsHostFor } from "../_shared/apns.ts";

type PushRequest = {
  title: string;
  body: string;
  kind?: string;
  request_id?: string;
  request_type?: string;
};

/// تحديد APNs category بناءً على نوع الطلب — يفعّل أزرار قبول/رفض/فتح في الإشعار
function categoryFor(requestType: string | undefined): string {
  if (!requestType) return "ADMIN_REQUEST";
  // طلبات الانضمام لها category خاص (تشمل زر "فتح الطلب")
  if (requestType === "join_request" || requestType === "link_request") {
    return "JOIN_REQUEST";
  }
  return "ADMIN_REQUEST";
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const methodErr = validatePost(req);
  if (methodErr) return methodErr;

  // التحقق من هوية المرسل — أي مستخدم مسجّل يقدر يصدر إشعار للإدارة
  // (طلبات الأعضاء العاديين تحتاج إشعارات للأدمن، فلا نقيّد بالأدوار)
  const auth = await authenticateRequest(req, undefined, { allowInactive: true });
  if (auth instanceof Response) return auth;
  if (!["active", "pending"].includes(auth.status ?? "")) return json(403, { ok: false, message: "Account not authorized" });
  // نستثني المُرسِل من المستلمين عند وجود أكثر من مدير (تجنّب إشعار الذات)،
  // ونُبقيه فقط لو كان المدير الوحيد — انظر فلترة adminIds أدناه.

  // Parse body
  const parsed = await parseBody<PushRequest>(req);
  if (parsed instanceof Response) return parsed;
  const payload = parsed;

  if (!payload || typeof payload !== "object") return json(400, { ok: false, message: "Invalid request" });
  const supabase = createServiceClient();
  const privileged = auth.status === "active" && adminRoles.includes(auth.role ?? "");
  let title: string;
  let body: string;
  if (typeof payload.request_id === "string") {
    if (!/^[0-9a-f-]{36}$/i.test(payload.request_id)) return json(400, { ok: false, message: "Invalid request id" });
    if (payload.request_type === "join_request") {
      const { data: member, error } = await supabase.from("profiles").select("id,status").eq("id", payload.request_id).maybeSingle();
      if (error) return json(503, { ok: false, message: "Request lookup failed" });
      if (!member || member.id !== auth.profileId || member.status !== "pending") return json(403, { ok: false, message: "Request not authorized" });
    } else {
      const { data: saved, error } = await supabase.from("admin_requests")
        .select("id,requester_id,member_id,request_type,status").eq("id", payload.request_id).maybeSingle();
      if (error) return json(503, { ok: false, message: "Request lookup failed" });
      if (!ownsPendingRequest(saved, auth.profileId)) return json(403, { ok: false, message: "Request not authorized" });
      payload.request_type = saved!.request_type;
    }
    title = requestTitle(payload.request_type ?? "");
    body = "يوجد طلب جديد بانتظار المراجعة في مركز طلبات الإدارة.";
    payload.kind = "admin_request";
  } else {
    if (!privileged) return json(403, { ok: false, message: "A saved request is required" });
    title = typeof payload.title === "string" ? payload.title.trim() : "";
    body = typeof payload.body === "string" ? payload.body.trim() : "";
  }
  if (!title || !body || title.length > 200 || body.length > 2000) return json(400, { ok: false, message: "Invalid notification" });
  const limited = await deliveryGuard("push-admins", auth.profileId, payload.request_id ?? [title,body], privileged ? 60 : 10, payload.request_id ? 604800 : 300);
  if (limited) return limited;

  // APNs config
  let apnsConfig;
  try {
    apnsConfig = getApnsConfig();
  } catch (e) {
    return json(500, { ok: false, message: (e as Error).message });
  }
  const { teamId, keyId, bundleId, privateKey } = apnsConfig;

  // جلب أعضاء فريق الإدارة (مع استثناء المُرسِل لو هو نفسه أدمن — لتجنب إشعار الذات)
  const { data: admins, error: adminsErr } = await supabase
    .from("profiles")
    .select("id")
    .in("role", ["owner", "admin", "monitor", "supervisor"])
    .eq("status", "active");

  if (adminsErr) {
    return json(500, {
      ok: false,
      message: `Failed loading admins: ${adminsErr.message}`,
    });
  }

  let adminIds = (admins ?? []).map((a) => a.id as string);
  if (!adminIds.length) {
    return json(200, { ok: true, sent: 0, message: "No admins found" });
  }

  // استثناء المُرسِل لتجنّب «إشعار الذات» (سبب رئيسي لتكرار وصول نفس الإشعار
  // للمدير المنفّذ). نُبقيه فقط لو كان المدير الوحيد — ليستلم تأكيداً على أجهزته.
  const senderId = auth.profileId;
  if (adminIds.length > 1) {
    adminIds = adminIds.filter((id) => id !== senderId);
  }

  // جلب tokens الأجهزة (مع environment)
  const { data: tokenRows, error: tokenErr } = await supabase
    .from("device_tokens")
    .select("token, member_id, environment")
    .in("member_id", adminIds)
    .in("platform", ["ios", "ipados"]);

  if (tokenErr) {
    return json(500, {
      ok: false,
      message: `Failed loading tokens: ${tokenErr.message}`,
    });
  }

  // Filter out null/empty tokens + dedupe by token
  // (نفس الجهاز قد يكون مرتبط بأكثر من حساب مدير → token مكرر → 2 بانرات)
  const seenTokens = new Set<string>();
  const tokenEntries = (tokenRows ?? [])
    .filter((r) => r.token != null)
    .map((r) => ({ token: (r.token as string).trim(), env: r.environment as string | null }))
    .filter((e) => e.token.length > 20)
    .filter((e) => {
      if (seenTokens.has(e.token)) return false;
      seenTokens.add(e.token);
      return true;
    });

  if (!tokenEntries.length) {
    return json(200, { ok: true, sent: 0, message: "No admin push tokens" });
  }

  const jwt = await createApnsJwt(teamId, keyId, privateKey);

  // بناء APNs payload — يحتوي على category لتفعيل أزرار قبول/رفض/فتح في الإشعار
  const apnsCategory = categoryFor(payload.request_type);
  const apnsBody: Record<string, unknown> = {
    aps: {
      alert: { title, body },
      sound: "default",
      category: apnsCategory,
      "mutable-content": 1,
    },
    kind: payload.kind ?? "admin_request",
  };
  if (payload.request_id)   apnsBody.request_id   = payload.request_id;
  if (payload.request_type) apnsBody.request_type = payload.request_type;
  const apnsBodyJson = JSON.stringify(apnsBody);

  let sent = 0;
  const failures: Array<{ token: string; status: number; reason: string; env: string | null }> = [];

  for (const entry of tokenEntries) {
    const { token, env } = entry;
    const host = apnsHostFor(env);
    const apnsResponse = await fetch(`${host}/3/device/${token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": bundleId,
        "apns-push-type": "alert",
        "apns-priority": "10",
      },
      body: apnsBodyJson,
    });

    if (apnsResponse.ok) {
      sent += 1;
      continue;
    }

    const reason = await apnsResponse.text();
    failures.push({ token: token.substring(0, 8) + "...", status: apnsResponse.status, reason, env });

    // حذف tokens المنتهية (410) فقط — 400 قد يكون environment mismatch مؤقت
    if (apnsResponse.status === 410) {
      await supabase.from("device_tokens").delete().eq("token", token);
    }
  }

  return json(200, {
    ok: true,
    sent,
    total: tokenEntries.length,
    failed: failures.length,
    failures,
  });
});
