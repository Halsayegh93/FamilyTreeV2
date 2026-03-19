import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4";
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};
function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json"
    }
  });
}
function pemToArrayBuffer(pem) {
  const clean = pem.replace("-----BEGIN PRIVATE KEY-----", "").replace("-----END PRIVATE KEY-----", "").replace(/\s+/g, "");
  const binary = atob(clean);
  const bytes = new Uint8Array(binary.length);
  for(let i = 0; i < binary.length; i++){
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}
function toBase64Url(input) {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for(let i = 0; i < bytes.length; i++)binary += String.fromCharCode(bytes[i]);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
async function createApnsJwt(teamId, keyId, privateKeyPem) {
  const header = {
    alg: "ES256",
    kid: keyId
  };
  const payload = {
    iss: teamId,
    iat: Math.floor(Date.now() / 1000)
  };
  const encodedHeader = toBase64Url(JSON.stringify(header));
  const encodedPayload = toBase64Url(JSON.stringify(payload));
  const data = `${encodedHeader}.${encodedPayload}`;
  const key = await crypto.subtle.importKey("pkcs8", pemToArrayBuffer(privateKeyPem), {
    name: "ECDSA",
    namedCurve: "P-256"
  }, false, [
    "sign"
  ]);
  const signature = await crypto.subtle.sign({
    name: "ECDSA",
    hash: "SHA-256"
  }, key, new TextEncoder().encode(data));
  const signatureUrl = toBase64Url(new Uint8Array(signature));
  return `${data}.${signatureUrl}`;
}
serve(async (req)=>{
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders
    });
  }
  if (req.method !== "POST") {
    return json(405, {
      ok: false,
      message: "Method not allowed"
    });
  }
  // JWT verification — require authenticated user
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json(401, { ok: false, message: "Missing authorization" });
  }
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const authClient = createClient(supabaseUrl, anonKey);
  const { error: authError } = await authClient.auth.getUser(
    authHeader.replace("Bearer ", "")
  );
  if (authError) {
    return json(401, { ok: false, message: "Invalid or expired token" });
  }
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !serviceRole) {
    return json(500, {
      ok: false,
      message: "Missing Supabase service env"
    });
  }
  const teamId = Deno.env.get("APPLE_TEAM_ID") ?? "";
  const keyId = Deno.env.get("APPLE_KEY_ID") ?? "";
  const bundleId = Deno.env.get("APPLE_BUNDLE_ID") ?? "";
  const privateKey = (Deno.env.get("APPLE_APNS_KEY_P8") ?? "").replace(/\\n/g, "\n");
  const apnsHost = Deno.env.get("APPLE_APNS_HOST") ?? "https://api.push.apple.com";
  if (!teamId || !keyId || !bundleId || !privateKey) {
    return json(500, {
      ok: false,
      message: "Missing APNs env vars"
    });
  }
  let payload;
  try {
    payload = await req.json();
  } catch  {
    return json(400, {
      ok: false,
      message: "Invalid JSON body"
    });
  }
  const title = (payload.title ?? "").trim();
  const body = (payload.body ?? "").trim();
  if (!title || !body) {
    return json(400, {
      ok: false,
      message: "title/body required"
    });
  }
  const supabase = createClient(supabaseUrl, serviceRole, {
    auth: {
      persistSession: false,
      autoRefreshToken: false
    }
  });
  // جلب tokens الأعضاء المستهدفين
  let tokenQuery = supabase.from("device_tokens").select("token, member_id").eq("platform", "ios");
  const memberIds = payload.member_ids;
  if (memberIds && memberIds.length > 0) {
    // إرسال لأعضاء محددين
    tokenQuery = tokenQuery.in("member_id", memberIds);
  }
  // إذا member_ids فاضي = broadcast لكل الأجهزة المسجلة
  const { data: tokenRows, error: tokenErr } = await tokenQuery;
  if (tokenErr) {
    return json(500, {
      ok: false,
      message: `Failed loading tokens: ${tokenErr.message}`
    });
  }
  const tokens = (tokenRows ?? []).map((r)=>r.token.trim()).filter((t)=>t.length > 20);
  if (!tokens.length) {
    return json(200, {
      ok: true,
      sent: 0,
      message: "No push tokens found"
    });
  }
  let jwt;
  try {
    jwt = await createApnsJwt(teamId, keyId, privateKey);
  } catch (e) {
    console.error(`APNs JWT creation failed: ${e.message}, keyLength=${privateKey.length}`);
    return json(500, {
      ok: false,
      message: "Push notification service configuration error",
    });
  }
  let sent = 0;
  const failures = [];
  for (const token of tokens){
    try {
      const apnsResponse = await fetch(`${apnsHost}/3/device/${token}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${jwt}`,
          "apns-topic": bundleId,
          "apns-push-type": "alert",
          "apns-priority": "10"
        },
        body: JSON.stringify({
          aps: {
            alert: {
              title,
              body
            },
            sound: "default"
          },
          kind: payload.kind ?? "notification"
        })
      });
      if (apnsResponse.ok) {
        sent += 1;
        continue;
      }
      const reason = await apnsResponse.text();
      failures.push({
        token: token.substring(0, 8) + "...",
        status: apnsResponse.status,
        reason
      });
      // حذف tokens منتهية الصلاحية
      if (apnsResponse.status === 410 || apnsResponse.status === 400) {
        await supabase.from("device_tokens").delete().eq("token", token);
      }
    } catch (fetchErr) {
      failures.push({
        token: token.substring(0, 8) + "...",
        status: 0,
        reason: `fetch error: ${fetchErr.message}`
      });
    }
  }
  return json(200, {
    ok: true,
    sent,
    total: tokens.length,
    failed: failures.length,
    failures,
  });
});
