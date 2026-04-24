/// APNs JWT creation — مشترك بين push-admins و push-notify

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
  const bytes =
    typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (let i = 0; i < bytes.length; i++)
    binary += String.fromCharCode(bytes[i]);
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

export async function createApnsJwt(
  teamId: string,
  keyId: string,
  privateKeyPem: string
): Promise<string> {
  const header = { alg: "ES256", kid: keyId };
  const payload = { iss: teamId, iat: Math.floor(Date.now() / 1000) };
  const encodedHeader = toBase64Url(JSON.stringify(header));
  const encodedPayload = toBase64Url(JSON.stringify(payload));
  const data = `${encodedHeader}.${encodedPayload}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(privateKeyPem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );

  const rawSig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(data)
  );
  const sigBytes = new Uint8Array(rawSig);
  let finalSig = sigBytes;
  if (sigBytes.length !== 64 && sigBytes[0] === 0x30) {
    let offset = 2;
    if (sigBytes[1] > 0x80) offset += sigBytes[1] - 0x80;
    const rLen = sigBytes[offset + 1];
    const rStart = offset + 2;
    let r = sigBytes.slice(rStart, rStart + rLen);
    if (r.length === 33 && r[0] === 0) r = r.slice(1);
    const sOffset = rStart + rLen;
    const sLen = sigBytes[sOffset + 1];
    const sStart = sOffset + 2;
    let s = sigBytes.slice(sStart, sStart + sLen);
    if (s.length === 33 && s[0] === 0) s = s.slice(1);
    const rPad = new Uint8Array(32);
    rPad.set(r, 32 - r.length);
    const sPad = new Uint8Array(32);
    sPad.set(s, 32 - s.length);
    finalSig = new Uint8Array(64);
    finalSig.set(rPad, 0);
    finalSig.set(sPad, 32);
  }
  return `${data}.${toBase64Url(finalSig)}`;
}

/// APNs hosts — ثابتة من Apple
export const APNS_HOST_PRODUCTION = "https://api.push.apple.com";
export const APNS_HOST_SANDBOX = "https://api.sandbox.push.apple.com";

/// اختيار host حسب environment الجهاز (من device_tokens.environment)
export function apnsHostFor(environment: string | null | undefined): string {
  return environment === "sandbox" ? APNS_HOST_SANDBOX : APNS_HOST_PRODUCTION;
}

/// قراءة إعدادات APNs من البيئة
export function getApnsConfig() {
  const teamId = Deno.env.get("APPLE_TEAM_ID") ?? "";
  const keyId = Deno.env.get("APPLE_KEY_ID") ?? "";
  const bundleId = Deno.env.get("APPLE_BUNDLE_ID") ?? "";
  const rawKey = Deno.env.get("APPLE_APNS_KEY_P8") ?? "";
  const privateKey = rawKey.includes("\\n")
    ? rawKey.replace(/\\n/g, "\n")
    : rawKey;
  // apnsHost للـ fallback فقط — المنطق الجديد يختار host لكل توكن حسب environment
  const apnsHost =
    Deno.env.get("APPLE_APNS_HOST") ?? APNS_HOST_PRODUCTION;

  if (!teamId || !keyId || !bundleId || !privateKey) {
    throw new Error("Missing APNs env vars");
  }

  return { teamId, keyId, bundleId, privateKey, apnsHost };
}
