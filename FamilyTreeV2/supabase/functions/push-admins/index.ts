import { handleCors, validatePost, json } from "../_shared/cors.ts";
import { createServiceClient, authenticateRequest, parseBody } from "../_shared/auth.ts";
import { createApnsJwt, getApnsConfig, apnsHostFor } from "../_shared/apns.ts";

type PushRequest = {
  title: string;
  body: string;
  kind?: string;
};

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const methodErr = validatePost(req);
  if (methodErr) return methodErr;

  // التحقق من هوية المرسل — فقط فريق الإدارة
  const auth = await authenticateRequest(req, [
    "owner",
    "admin",
    "monitor",
    "supervisor",
  ]);
  if (auth instanceof Response) return auth;

  // Parse body
  const parsed = await parseBody<PushRequest>(req);
  if (parsed instanceof Response) return parsed;
  const payload = parsed;

  const title = (payload.title ?? "").trim();
  const body = (payload.body ?? "").trim();
  if (!title || !body) {
    return json(400, { ok: false, message: "title/body required" });
  }

  // APNs config
  let apnsConfig;
  try {
    apnsConfig = getApnsConfig();
  } catch (e) {
    return json(500, { ok: false, message: (e as Error).message });
  }
  const { teamId, keyId, bundleId, privateKey } = apnsConfig;

  const supabase = createServiceClient();

  // جلب أعضاء فريق الإدارة
  const { data: admins, error: adminsErr } = await supabase
    .from("profiles")
    .select("id")
    .in("role", ["owner", "admin", "monitor", "supervisor"]);

  if (adminsErr) {
    return json(500, {
      ok: false,
      message: `Failed loading admins: ${adminsErr.message}`,
    });
  }

  const adminIds = (admins ?? []).map((a) => a.id as string);
  if (!adminIds.length) {
    return json(200, { ok: true, sent: 0, message: "No admins found" });
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

  // Filter out null/empty tokens (token can be null after device_id migration)
  const tokenEntries = (tokenRows ?? [])
    .filter((r) => r.token != null)
    .map((r) => ({ token: (r.token as string).trim(), env: r.environment as string | null }))
    .filter((e) => e.token.length > 20);

  if (!tokenEntries.length) {
    return json(200, { ok: true, sent: 0, message: "No admin push tokens" });
  }

  const jwt = await createApnsJwt(teamId, keyId, privateKey);

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
      body: JSON.stringify({
        aps: {
          alert: { title, body },
          sound: "default",
        },
        kind: payload.kind ?? "admin_request",
      }),
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
