import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4";

type PushRequest = {
  title: string;
  body: string;
  kind?: string;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const clean = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");

  const binary = atob(clean);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

function toBase64Url(input: string | Uint8Array): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

async function createApnsJwt(teamId: string, keyId: string, privateKeyPem: string): Promise<string> {
  const header = { alg: "ES256", kid: keyId };
  const payload = {
    iss: teamId,
    iat: Math.floor(Date.now() / 1000),
  };

  const encodedHeader = toBase64Url(JSON.stringify(header));
  const encodedPayload = toBase64Url(JSON.stringify(payload));
  const data = `${encodedHeader}.${encodedPayload}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(privateKeyPem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  const rawSig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(data),
  );
  const sigBytes = new Uint8Array(rawSig);
  let finalSig = sigBytes;
  if (sigBytes.length !== 64 && sigBytes[0] === 0x30) {
    let offset = 2;
    if (sigBytes[1] > 0x80) offset += (sigBytes[1] - 0x80);
    const rLen = sigBytes[offset + 1];
    const rStart = offset + 2;
    let r = sigBytes.slice(rStart, rStart + rLen);
    if (r.length === 33 && r[0] === 0) r = r.slice(1);
    const sOffset = rStart + rLen;
    const sLen = sigBytes[sOffset + 1];
    const sStart = sOffset + 2;
    let s = sigBytes.slice(sStart, sStart + sLen);
    if (s.length === 33 && s[0] === 0) s = s.slice(1);
    const rPad = new Uint8Array(32); rPad.set(r, 32 - r.length);
    const sPad = new Uint8Array(32); sPad.set(s, 32 - s.length);
    finalSig = new Uint8Array(64);
    finalSig.set(rPad, 0);
    finalSig.set(sPad, 32);
  }
  const signatureUrl = toBase64Url(finalSig);
  return `${data}.${signatureUrl}`;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json(405, { ok: false, message: "Method not allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !serviceRole) {
    return json(500, { ok: false, message: "Missing Supabase service env" });
  }

  const teamId = Deno.env.get("APPLE_TEAM_ID") ?? "";
  const keyId = Deno.env.get("APPLE_KEY_ID") ?? "";
  const bundleId = Deno.env.get("APPLE_BUNDLE_ID") ?? "";
  const rawKey = Deno.env.get("APPLE_APNS_KEY_P8") ?? "";
  const privateKey = rawKey.includes("\\n") ? rawKey.replace(/\\n/g, "\n") : rawKey;
  const apnsHost = Deno.env.get("APPLE_APNS_HOST") ?? "https://api.push.apple.com";

  if (!teamId || !keyId || !bundleId || !privateKey) {
    return json(500, { ok: false, message: "Missing APNs env vars" });
  }

  let payload: PushRequest;
  try {
    payload = await req.json();
  } catch (_e) {
    return json(400, { ok: false, message: "Invalid JSON body" });
  }

  const title = (payload.title ?? "").trim();
  const body = (payload.body ?? "").trim();
  if (!title || !body) {
    return json(400, { ok: false, message: "title/body required" });
  }

  const supabase = createClient(supabaseUrl, serviceRole, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: admins, error: adminsErr } = await supabase
    .from("profiles")
    .select("id")
    .in("role", ["owner", "admin", "supervisor"]);

  if (adminsErr) {
    return json(500, { ok: false, message: `Failed loading admins: ${adminsErr.message}` });
  }

  const adminIds = (admins ?? []).map((a) => a.id as string);
  if (!adminIds.length) {
    return json(200, { ok: true, sent: 0, message: "No admins found" });
  }

  const { data: tokenRows, error: tokenErr } = await supabase
    .from("device_tokens")
    .select("token, member_id")
    .in("member_id", adminIds)
    .in("platform", ["ios", "ipados"]);

  if (tokenErr) {
    return json(500, { ok: false, message: `Failed loading tokens: ${tokenErr.message}` });
  }

  // Filter out null/empty tokens (token can be null after device_id migration)
  const tokens = (tokenRows ?? [])
    .filter((r) => r.token != null)
    .map((r) => (r.token as string).trim())
    .filter((t) => t.length > 20);

  if (!tokens.length) {
    return json(200, { ok: true, sent: 0, message: "No admin push tokens" });
  }

  const jwt = await createApnsJwt(teamId, keyId, privateKey);

  let sent = 0;
  const failures: Array<{ token: string; status: number; reason: string }> = [];

  for (const token of tokens) {
    const apnsResponse = await fetch(`${apnsHost}/3/device/${token}`, {
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
    failures.push({ token, status: apnsResponse.status, reason });

    if (apnsResponse.status === 410 || apnsResponse.status === 400) {
      await supabase.from("device_tokens").delete().eq("token", token);
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
