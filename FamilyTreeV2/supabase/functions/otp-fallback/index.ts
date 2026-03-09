import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

type Channel = "whatsapp" | "call";

type FallbackRequest = {
  phone: string;
  channels?: Channel[];
  message?: string;
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

function normalizePhone(raw: string): string | null {
  const digits = raw.replace(/\D/g, "");
  if (digits.length === 8) return `+965${digits}`;
  if (digits.startsWith("965") && digits.length === 11) return `+${digits}`;
  if (raw.startsWith("+") && digits.length >= 8) return `+${digits}`;
  return null;
}

function extractBearerToken(authHeader: string | null): string {
  const raw = (authHeader ?? "").trim();
  if (!raw) return "";
  const lower = raw.toLowerCase();
  if (lower.startsWith("bearer ")) {
    return raw.slice(7).trim().replace(/^['"]|['"]$/g, "");
  }
  return raw.replace(/^['"]|['"]$/g, "");
}

async function callTwilioWhatsApp(phone: string, message: string): Promise<void> {
  const sid = Deno.env.get("TWILIO_ACCOUNT_SID");
  const token = Deno.env.get("TWILIO_AUTH_TOKEN");
  const from = Deno.env.get("TWILIO_WHATSAPP_FROM");

  if (!sid || !token || !from) {
    throw new Error("Twilio WhatsApp env vars are missing");
  }

  const body = new URLSearchParams({
    To: `whatsapp:${phone}`,
    From: `whatsapp:${from}`,
    Body: message,
  });

  const response = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`, {
    method: "POST",
    headers: {
      Authorization: `Basic ${btoa(`${sid}:${token}`)}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body,
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Twilio WhatsApp failed: ${response.status} ${text}`);
  }
}

async function callTwilioVoice(phone: string, message: string): Promise<void> {
  const sid = Deno.env.get("TWILIO_ACCOUNT_SID");
  const token = Deno.env.get("TWILIO_AUTH_TOKEN");
  const from = Deno.env.get("TWILIO_VOICE_FROM");

  if (!sid || !token || !from) {
    throw new Error("Twilio Voice env vars are missing");
  }

  const twiml = `<Response><Say language=\"ar-SA\">${message}</Say></Response>`;
  const body = new URLSearchParams({
    To: phone,
    From: from,
    Twiml: twiml,
  });

  const response = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${sid}/Calls.json`, {
    method: "POST",
    headers: {
      Authorization: `Basic ${btoa(`${sid}:${token}`)}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body,
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Twilio Voice failed: ${response.status} ${text}`);
  }
}

async function callWebhook(channel: Channel, phone: string, message: string): Promise<void> {
  const key = channel === "whatsapp" ? "WHATSAPP_FALLBACK_WEBHOOK_URL" : "CALL_FALLBACK_WEBHOOK_URL";
  const url = Deno.env.get(key);
  if (!url) {
    throw new Error(`Missing ${key}`);
  }

  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ phone, channel, message }),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Webhook ${channel} failed: ${response.status} ${text}`);
  }
}

async function callUnifonicWhatsApp(phone: string, message: string): Promise<void> {
  const appSid = Deno.env.get("UNIFONIC_WHATSAPP_APP_SID");
  const token = Deno.env.get("UNIFONIC_ACCESS_TOKEN");
  const sender = Deno.env.get("UNIFONIC_WHATSAPP_SENDER");

  if (!appSid || !token || !sender) {
    throw new Error("Unifonic WhatsApp env vars are missing");
  }

  const body = new URLSearchParams({
    AppSid: appSid,
    Recipient: phone.replace(/^\+/, ""),
    Sender: sender,
    Body: message,
  });

  const response = await fetch("https://el.cloud.unifonic.com/rest/SMS/messages", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body,
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Unifonic WhatsApp failed: ${response.status} ${text}`);
  }
}

async function callUnifonicVoice(phone: string, message: string): Promise<void> {
  const token = Deno.env.get("UNIFONIC_ACCESS_TOKEN");
  const callerId = Deno.env.get("UNIFONIC_VOICE_CALLER_ID");
  const endpoint = Deno.env.get("UNIFONIC_VOICE_ENDPOINT")
    ?? "https://voice.cloud.unifonic.com/v1/calls";

  if (!token || !callerId) {
    throw new Error("Unifonic Voice env vars are missing");
  }

  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      to: phone.replace(/^\+/, ""),
      from: callerId,
      text: message,
      language: "ar-SA",
    }),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Unifonic Voice failed: ${response.status} ${text}`);
  }
}

async function sendByChannel(channel: Channel, phone: string, message: string): Promise<void> {
  const provider = (Deno.env.get("FALLBACK_PROVIDER") ?? "twilio").toLowerCase();

  if (provider === "webhook") {
    await callWebhook(channel, phone, message);
    return;
  }

  if (provider === "unifonic") {
    if (channel === "whatsapp") {
      await callUnifonicWhatsApp(phone, message);
      return;
    }
    await callUnifonicVoice(phone, message);
    return;
  }

  if (channel === "whatsapp") {
    await callTwilioWhatsApp(phone, message);
    return;
  }

  await callTwilioVoice(phone, message);
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json(405, { accepted: false, message: "Method not allowed" });
  }

  const expectedKey = (Deno.env.get("OTP_FALLBACK_API_KEY") ?? "")
    .trim()
    .replace(/^['"]|['"]$/g, "");
  if (expectedKey) {
    const tokenFromAuthorization = extractBearerToken(req.headers.get("authorization"));
    const tokenFromApiKey = (req.headers.get("apikey") ?? "").trim().replace(/^['"]|['"]$/g, "");
    const providedToken = tokenFromAuthorization || tokenFromApiKey;
    if (providedToken !== expectedKey) {
      return json(401, { accepted: false, message: "Unauthorized" });
    }
  }

  let payload: FallbackRequest;
  try {
    payload = await req.json();
  } catch {
    return json(400, { accepted: false, message: "Invalid JSON body" });
  }

  const normalizedPhone = normalizePhone(payload.phone ?? "");
  if (!normalizedPhone) {
    return json(400, { accepted: false, message: "Invalid phone format" });
  }

  const channels = (payload.channels?.length ? payload.channels : ["whatsapp", "call"]).filter(
    (c): c is Channel => c === "whatsapp" || c === "call",
  );

  const defaultMessage = Deno.env.get("OTP_FALLBACK_MESSAGE") ??
    "تعذر إرسال رمز SMS. سيتم التواصل معك عبر قناة بديلة لإكمال التحقق.";
  const message = (payload.message?.trim() || defaultMessage).slice(0, 400);

  const errors: string[] = [];

  for (const channel of channels) {
    try {
      await sendByChannel(channel, normalizedPhone, message);
      return json(200, {
        accepted: true,
        channel,
        message: `Fallback sent via ${channel}`,
      });
    } catch (error) {
      const reason = error instanceof Error ? error.message : String(error);
      errors.push(`${channel}: ${reason}`);
    }
  }

  return json(502, {
    accepted: false,
    message: "All fallback channels failed",
    details: errors,
  });
});
