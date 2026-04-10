import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";
import { createHmac } from "node:crypto";

// MARK: - Supabase SMS Hook → AWS SNS
// يستقبل طلب OTP من Supabase Auth ويرسل SMS عبر AWS SNS

// AWS Signature V4 helpers
function hmacSHA256(key: Uint8Array | string, data: string): Uint8Array {
  const hmac = createHmac("sha256", key);
  hmac.update(data);
  return new Uint8Array(hmac.digest());
}

function toHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function sha256Hex(data: string): Promise<string> {
  const encoded = new TextEncoder().encode(data);
  const hash = await crypto.subtle.digest("SHA-256", encoded);
  return toHex(new Uint8Array(hash));
}

function getSignatureKey(
  key: string,
  dateStamp: string,
  region: string,
  service: string
): Uint8Array {
  const kDate = hmacSHA256(`AWS4${key}`, dateStamp);
  const kRegion = hmacSHA256(kDate, region);
  const kService = hmacSHA256(kRegion, service);
  return hmacSHA256(kService, "aws4_request");
}

async function sendSNS(phone: string, message: string): Promise<void> {
  const accessKey = Deno.env.get("AWS_ACCESS_KEY_ID");
  const secretKey = Deno.env.get("AWS_SECRET_ACCESS_KEY");
  const region = Deno.env.get("AWS_REGION") ?? "eu-north-1";

  if (!accessKey || !secretKey) {
    throw new Error("AWS credentials not configured");
  }

  const host = `sns.${region}.amazonaws.com`;
  const endpoint = `https://${host}/`;
  const service = "sns";
  const method = "POST";

  const params = new URLSearchParams({
    Action: "Publish",
    PhoneNumber: phone,
    Message: message,
    "MessageAttributes.entry.1.Name": "AWS.SNS.SMS.SMSType",
    "MessageAttributes.entry.1.Value.DataType": "String",
    "MessageAttributes.entry.1.Value.StringValue": "Transactional",
    "MessageAttributes.entry.2.Name": "AWS.SNS.SMS.SenderID",
    "MessageAttributes.entry.2.Value.DataType": "String",
    "MessageAttributes.entry.2.Value.StringValue": Deno.env.get("SMS_SENDER_ID") ?? "almohali",
    Version: "2010-03-31",
  });
  const body = params.toString();

  const now = new Date();
  const amzDate =
    now.toISOString().replace(/[:-]|\.\d{3}/g, "").slice(0, 15) + "Z";
  const dateStamp = amzDate.slice(0, 8);

  const payloadHash = await sha256Hex(body);

  const canonicalHeaders = `content-type:application/x-www-form-urlencoded\nhost:${host}\nx-amz-date:${amzDate}\n`;
  const signedHeaders = "content-type;host;x-amz-date";

  const canonicalRequest = [
    method,
    "/",
    "",
    canonicalHeaders,
    signedHeaders,
    payloadHash,
  ].join("\n");

  const credentialScope = `${dateStamp}/${region}/${service}/aws4_request`;
  const stringToSign = [
    "AWS4-HMAC-SHA256",
    amzDate,
    credentialScope,
    await sha256Hex(canonicalRequest),
  ].join("\n");

  const signingKey = getSignatureKey(secretKey, dateStamp, region, service);
  const signature = toHex(hmacSHA256(signingKey, stringToSign));

  const authHeader = `AWS4-HMAC-SHA256 Credential=${accessKey}/${credentialScope}, SignedHeaders=${signedHeaders}, Signature=${signature}`;

  const response = await fetch(endpoint, {
    method,
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      "X-Amz-Date": amzDate,
      Authorization: authHeader,
    },
    body,
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`AWS SNS failed: ${response.status} ${text}`);
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    // التحقق من توقيع Supabase webhook
    const payload = await req.text();
    const secret = Deno.env.get("SEND_SMS_HOOK_SECRET") ?? "";
    const base64Secret = secret.replace("v1,whsec_", "");
    const headers = Object.fromEntries(req.headers);
    const wh = new Webhook(base64Secret);

    const { user, sms } = wh.verify(payload, headers) as {
      user: { phone: string };
      sms: { otp: string };
    };

    const phone = user.phone;
    const otp = sms.otp;

    if (!phone || !otp) {
      return new Response(JSON.stringify({ error: "Missing phone or otp" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    // رسالة OTP
    const message = `almohammad ali: Your code is ${otp}`;

    // إرسال عبر AWS SNS
    await sendSNS(phone, message);
    console.log(`[SMS Hook] ✅ OTP sent to ${phone.slice(0, 6)}***`);

    // Supabase يتوقع response فاضي مع 200
    return new Response(JSON.stringify({}), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error(`[SMS Hook] ❌ Error: ${msg}`);

    return new Response(JSON.stringify({ error: msg }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
