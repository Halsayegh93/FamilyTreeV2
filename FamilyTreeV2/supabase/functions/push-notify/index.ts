import { handleCors, validatePost, json } from "../_shared/cors.ts";
import { createServiceClient, parseBody, authenticateRequest } from "../_shared/auth.ts";
import { createApnsJwt, getApnsConfig, apnsHostFor } from "../_shared/apns.ts";

type PushRequest = {
  title: string;
  body: string;
  kind?: string;
  member_ids?: string[];
};

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const methodErr = validatePost(req);
  if (methodErr) return methodErr;

  // التحقق من هوية المرسل — فقط فريق الإدارة يقدر يرسل push خارجي
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

  // جلب tokens الأعضاء المستهدفين (مع environment لاختيار host صحيح)
  const memberIds = payload.member_ids;
  let allTokenRows: Array<{ token: string; member_id: string; environment: string | null }> = [];

  if (memberIds && memberIds.length > 0) {
    // تقسيم member_ids لمجموعات عشان ما يطول الـ URL
    const CHUNK_SIZE = 100;
    for (let i = 0; i < memberIds.length; i += CHUNK_SIZE) {
      const chunk = memberIds.slice(i, i + CHUNK_SIZE);
      const { data, error } = await supabase
        .from("device_tokens")
        .select("token, member_id, environment")
        .in("platform", ["ios", "ipados"])
        .in("member_id", chunk);
      if (error) {
        return json(500, {
          ok: false,
          message: `Failed loading tokens: ${error.message}`,
        });
      }
      if (data) allTokenRows.push(...data);
    }
  } else {
    // broadcast لكل الأجهزة المسجلة
    const { data, error } = await supabase
      .from("device_tokens")
      .select("token, member_id, environment")
      .in("platform", ["ios", "ipados"]);
    if (error) {
      return json(500, {
        ok: false,
        message: `Failed loading tokens: ${error.message}`,
      });
    }
    if (data) allTokenRows = data;
  }

  const tokenEntries = allTokenRows
    .filter((r) => r.token != null)
    .map((r) => ({ token: (r.token as string).trim(), env: r.environment }))
    .filter((e) => e.token.length > 20);

  if (!tokenEntries.length) {
    return json(200, { ok: true, sent: 0, message: "No push tokens found" });
  }

  let jwt: string;
  try {
    jwt = await createApnsJwt(teamId, keyId, privateKey);
    console.log(
      `JWT created: teamId=${teamId}, keyId=${keyId}, keyLen=${privateKey.length}, jwtLen=${jwt.length}`
    );
  } catch (e) {
    const err = e as Error;
    console.error(
      `APNs JWT creation failed: ${err.message}, keyLength=${privateKey.length}, keyStart=${privateKey.substring(0, 30)}`
    );
    return json(500, {
      ok: false,
      message: `JWT error: ${err.message}, keyLen=${privateKey.length}`,
    });
  }

  let sent = 0;
  const failures: Array<{ token: string; status: number; reason: string; env: string | null }> = [];

  for (const entry of tokenEntries) {
    const { token, env } = entry;
    const host = apnsHostFor(env);
    try {
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
          kind: payload.kind ?? "notification",
        }),
      });

      if (apnsResponse.ok) {
        sent += 1;
        continue;
      }

      const reason = await apnsResponse.text();
      failures.push({
        token: token.substring(0, 8) + "...",
        status: apnsResponse.status,
        reason,
        env,
      });

      // حذف tokens المنتهية (410) فقط — 400 قد يكون environment mismatch مؤقت
      if (apnsResponse.status === 410) {
        await supabase.from("device_tokens").delete().eq("token", token);
      }
    } catch (fetchErr) {
      const err = fetchErr as Error;
      failures.push({
        token: token.substring(0, 8) + "...",
        status: 0,
        reason: `fetch error: ${err.message}`,
        env,
      });
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
