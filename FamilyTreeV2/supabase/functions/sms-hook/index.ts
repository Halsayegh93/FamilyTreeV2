import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";

// MARK: - Supabase SMS Hook → Unifonic SMS
// يستقبل طلب OTP من Supabase Auth ويرسل SMS عبر Unifonic
// متصل مباشرة بشبكات الكويت والخليج (Zain, Ooredoo, STC, du, Etisalat)

const FETCH_TIMEOUT_MS = 12_000;
const MAX_RETRIES = 2;

async function sendUnifonic(phone: string, message: string): Promise<void> {
  const appSid = Deno.env.get("UNIFONIC_APP_SID");
  const senderId = Deno.env.get("UNIFONIC_SMS_SENDER_ID") ?? "almohali";

  if (!appSid) {
    throw new Error("UNIFONIC_APP_SID not configured");
  }

  // Unifonic يقبل الرقم بدون + (مثال: 96512345678)
  const recipient = phone.replace(/^\+/, "");

  const body = new URLSearchParams({
    AppSid: appSid,
    SenderID: senderId,
    Body: message,
    Recipient: recipient,
  });

  let lastError: Error | undefined;
  for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
    try {
      const response = await fetch("https://el.cloud.unifonic.com/rest/SMS/messages", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: body.toString(),
        signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
      });

      if (!response.ok) {
        const text = await response.text();
        throw new Error(`Unifonic SMS failed: ${response.status} ${text}`);
      }

      const result = await response.json().catch(() => ({}));
      if (result?.success === false || result?.Success === false) {
        throw new Error(`Unifonic SMS error: ${JSON.stringify(result)}`);
      }
      return;
    } catch (err) {
      lastError = err instanceof Error ? err : new Error(String(err));
      console.warn(`[SMS Hook] attempt ${attempt}/${MAX_RETRIES} failed: ${lastError.message}`);
      if (attempt < MAX_RETRIES) await new Promise((r) => setTimeout(r, 1_500));
    }
  }
  throw lastError!;
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

    const senderName = Deno.env.get("UNIFONIC_SMS_SENDER_ID") ?? "almohali";
    const message = `رمز التحقق الخاص بك في ${senderName}: ${otp}`;

    await sendUnifonic(phone, message);
    console.log(`[SMS Hook] ✅ OTP sent via Unifonic to ${phone.slice(0, 6)}***`);

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
